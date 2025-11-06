"""
Card Detection Module
Detects ID cards in camera frames using contour detection and aspect ratio filtering.
Enhanced with multi-scale detection, improved edge detection, and temporal smoothing.
"""
import cv2
import numpy as np


class CardDetector:
    """Detects ID cards with standard credit/debit card dimensions."""
    
    # Standard ID card aspect ratio (85.60mm × 53.98mm ≈ 1.586)
    # Made more lenient for better detection
    ASPECT_RATIO_MIN = 1.3  # Was 1.4
    ASPECT_RATIO_MAX = 1.8  # Was 1.7
    VERTICAL_ASPECT_MIN = 0.55  # Was 0.6 (1/1.8)
    VERTICAL_ASPECT_MAX = 0.77  # Was 0.75 (1/1.3)
    
    def __init__(self, min_area_ratio=0.02, max_area_ratio=0.95):
        """
        Initialize card detector.
        
        Args:
            min_area_ratio: Minimum card area as ratio of frame area (default: 2%)
            max_area_ratio: Maximum card area as ratio of frame area (default: 95% for close range)
        """
        self.min_area_ratio = min_area_ratio
        self.max_area_ratio = max_area_ratio
        # Size retention for stable detection
        self.last_detected_area = None
        self.area_tolerance = 0.5  # 50% variance allowed for size matching (more lenient)
        # Temporal smoothing for corners
        self.last_detected_corners = None
        self.corner_smoothing_alpha = 0.8  # Higher weight for more stability
        # Multi-scale detection - prioritize full scale for close range
        self.scale_factors = [1.0, 0.85, 0.7, 0.5]  # More scales, prioritize full size
        # Detection retention
        self.consecutive_failures = 0
        self.max_consecutive_failures = 10  # Allow up to 10 frames without detection before resetting
        self.has_ever_detected = False  # Track if we've ever detected a card
    
    def detect_card(self, frame):
        """
        Detect ID card in the frame using multi-scale detection with improved retention.
        
        Args:
            frame: Input BGR frame from camera
        
        Returns:
            tuple: (card_found: bool, corners: np.array or None)
                corners is a 4x2 array of card corner coordinates if found
        """
        if frame is None:
            return False, None
        
        # Try multi-scale detection - prioritize full scale first for close range
        best_result = None
        best_score = 0
        
        for scale in self.scale_factors:
            if scale != 1.0:
                # Resize frame for multi-scale detection
                h, w = frame.shape[:2]
                scaled_frame = cv2.resize(frame, (int(w * scale), int(h * scale)))
            else:
                scaled_frame = frame
            
            result = self._detect_at_scale(scaled_frame, scale)
            
            if result is not None:
                corners, score = result
                # Scale corners back to original frame size
                if scale != 1.0:
                    corners = corners / scale
                
                # Boost score for full-scale detection (close range)
                if scale == 1.0:
                    score *= 1.3
                
                if score > best_score:
                    best_score = score
                    best_result = corners
        
        if best_result is not None:
            # Successful detection
            self.consecutive_failures = 0
            self.has_ever_detected = True
            
            # Apply temporal smoothing
            if self.last_detected_corners is not None:
                # Exponential smoothing of corners - more aggressive smoothing for stability
                smoothed_corners = (
                    self.corner_smoothing_alpha * self.last_detected_corners +
                    (1 - self.corner_smoothing_alpha) * best_result
                )
                self.last_detected_corners = smoothed_corners
                return True, smoothed_corners
            else:
                self.last_detected_corners = best_result
                return True, best_result
        
        # No detection in this frame
        self.consecutive_failures += 1
        
        # Retention logic: if we've detected before and failures are below threshold, retain last detection
        if self.has_ever_detected and self.consecutive_failures <= self.max_consecutive_failures:
            if self.last_detected_corners is not None:
                # Retain last known corners - don't lose detection immediately
                return True, self.last_detected_corners
        
        # Too many failures or never detected - reset tracking
        if self.consecutive_failures > self.max_consecutive_failures:
            self.last_detected_corners = None
            self.has_ever_detected = False
            self.consecutive_failures = 0
        
        return False, None
    
    def _detect_at_scale(self, frame, scale=1.0):
        """
        Detect card at a specific scale.
        
        Args:
            frame: Input frame at this scale
            scale: Scale factor (1.0 = full size, <1.0 = downscaled)
        
        Returns:
            tuple: (corners, score) or None if not found
        """
        # Convert to grayscale
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # Apply Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # Enhanced edge detection with multiple methods
        # Adjust parameters based on scale (close range needs different handling)
        is_close_range = scale >= 1.0
        
        # Method 1: Multi-threshold Canny
        # For close range, use higher thresholds to reduce noise
        if is_close_range:
            edges1 = cv2.Canny(blurred, 30, 100)
            edges2 = cv2.Canny(blurred, 50, 150)
            edges3 = cv2.Canny(blurred, 40, 120)
        else:
            edges1 = cv2.Canny(blurred, 20, 80)
            edges2 = cv2.Canny(blurred, 40, 120)
            edges3 = cv2.Canny(blurred, 30, 100)
        
        edges = cv2.bitwise_or(edges1, edges2)
        edges = cv2.bitwise_or(edges, edges3)
        
        # Method 2: Adaptive thresholding for low contrast
        # Use larger block size for close range to reduce noise
        block_size = 15 if is_close_range else 11
        adaptive_thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
            cv2.THRESH_BINARY_INV, block_size, 2
        )
        edges = cv2.bitwise_or(edges, adaptive_thresh)
        
        # Method 3: Sobel edge detection
        sobel_x = cv2.Sobel(blurred, cv2.CV_64F, 1, 0, ksize=3)
        sobel_y = cv2.Sobel(blurred, cv2.CV_64F, 0, 1, ksize=3)
        sobel = np.sqrt(sobel_x**2 + sobel_y**2)
        if np.max(sobel) > 0:
            sobel = np.uint8(255 * sobel / np.max(sobel))
            sobel_thresh_val = 60 if is_close_range else 50
            _, sobel_thresh = cv2.threshold(sobel, sobel_thresh_val, 255, cv2.THRESH_BINARY)
            edges = cv2.bitwise_or(edges, sobel_thresh)
        
        # Morphological operations to close gaps
        # More aggressive for close range to handle larger gaps
        kernel_size = 5 if is_close_range else 3
        kernel = np.ones((kernel_size, kernel_size), np.uint8)
        iterations = 3 if is_close_range else 2
        edges = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=iterations)
        edges = cv2.dilate(edges, kernel, iterations=iterations)
        edges = cv2.erode(edges, kernel, iterations=1)
        
        # Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            return None
        
        # Filter contours by area and shape
        frame_area = frame.shape[0] * frame.shape[1]
        min_area = frame_area * self.min_area_ratio
        max_area = frame_area * self.max_area_ratio
        
        # For close range (full scale), be more lenient with area
        if scale >= 1.0:
            # Allow slightly larger areas for close-up detection
            max_area = frame_area * min(0.98, self.max_area_ratio * 1.05)
        
        valid_contours = []
        
        for contour in contours:
            area = cv2.contourArea(contour)
            
            # Check area bounds
            if area < min_area or area > max_area:
                continue
            
            # Check convexity defects for better shape validation
            hull = cv2.convexHull(contour)
            hull_area = cv2.contourArea(hull)
            solidity = 1.0  # Default solidity
            if hull_area > 0:
                solidity = area / hull_area
                # Reject shapes that are too irregular (solidity < 0.85)
                if solidity < 0.85:
                    continue
            
            # Approximate contour to polygon
            peri = cv2.arcLength(contour, True)
            if peri == 0:
                continue
            
            # Try different epsilon values to get 4 vertices (preferred) or 3-5 (acceptable)
            approx = None
            vertex_count = None
            for epsilon_factor in [0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08]:
                test_approx = cv2.approxPolyDP(contour, epsilon_factor * peri, True)
                v_count = len(test_approx)
                if v_count == 4:
                    # Perfect 4 vertices
                    approx = test_approx
                    vertex_count = 4
                    break
                elif v_count >= 3 and v_count <= 5 and approx is None:
                    # Accept 3-5 vertices as backup
                    approx = test_approx
                    vertex_count = v_count
            
            # Need at least 3 vertices to form a rectangle
            if approx is None or vertex_count < 3:
                continue
            
            # Get corners
            if vertex_count == 4:
                corners = approx.reshape(4, 2).astype(np.float32)
                # Validate perspective rectangle - more lenient for close range
                if not self._validate_perspective_rectangle(corners, scale):
                    continue
            else:
                # For 3 or 5 vertices, create a bounding rectangle
                x, y, w, h = cv2.boundingRect(approx)
                if w == 0 or h == 0:
                    continue
                corners = np.array([
                    [x, y],           # top-left
                    [x + w, y],       # top-right
                    [x + w, y + h],   # bottom-right
                    [x, y + h]        # bottom-left
                ], dtype=np.float32)
            
            # Calculate aspect ratio from corners
            x, y, w, h = cv2.boundingRect(corners.astype(np.int32))
            aspect_ratio = float(w) / h if h > 0 else 0
            inverse_aspect = float(h) / w if w > 0 else 0
            
            # Check if aspect ratio matches ID card dimensions
            is_horizontal = (self.ASPECT_RATIO_MIN <= aspect_ratio <= self.ASPECT_RATIO_MAX)
            is_vertical = (self.VERTICAL_ASPECT_MIN <= inverse_aspect <= self.VERTICAL_ASPECT_MAX)
            
            if is_horizontal or is_vertical:
                # Calculate score based on multiple factors
                score = self._calculate_detection_score(corners, area, solidity)
                valid_contours.append((corners, area, score))
        
        if not valid_contours:
            return None
        
        # Sort by score (higher is better)
        valid_contours.sort(key=lambda x: x[2], reverse=True)
        
        # If we have a previous detection, prefer similar-sized cards
        # More aggressive matching for retention
        if self.last_detected_area is not None:
            # Boost score for similar size - more lenient matching
            for i, (corners, area, score) in enumerate(valid_contours):
                area_diff = abs(area - self.last_detected_area) / self.last_detected_area
                if area_diff <= self.area_tolerance:
                    # Strong boost for similar size (helps retention)
                    valid_contours[i] = (corners, area, score * 2.0)
                elif area_diff <= self.area_tolerance * 1.5:
                    # Moderate boost for somewhat similar size
                    valid_contours[i] = (corners, area, score * 1.2)
            valid_contours.sort(key=lambda x: x[2], reverse=True)
        
        best_corners, best_area, _ = valid_contours[0]
        
        # Update last detected area - more stable updates for retention
        if self.last_detected_area is None:
            self.last_detected_area = best_area
        else:
            # Exponential moving average - slower update for stability
            # This helps retain detection even when size changes slightly
            self.last_detected_area = 0.8 * self.last_detected_area + 0.2 * best_area
        
        # Order corners: top-left, top-right, bottom-right, bottom-left
        ordered_corners = self._order_corners(best_corners)
        
        return (ordered_corners, valid_contours[0][2])
    
    def _validate_perspective_rectangle(self, corners, scale=1.0):
        """
        Validate that corners form a valid perspective rectangle.
        More lenient for close range (full scale) detection.
        
        Args:
            corners: 4x2 array of corner coordinates
            scale: Scale factor (more lenient for scale >= 1.0)
        
        Returns:
            bool: True if valid perspective rectangle
        """
        if corners.shape[0] != 4:
            return False
        
        # More lenient thresholds for close range
        is_close_range = scale >= 1.0
        parallel_threshold = 0.6 if is_close_range else 0.7
        angle_threshold = 0.4 if is_close_range else 0.3
        
        # Check that opposite sides are roughly parallel
        # Calculate vectors for each side
        v1 = corners[1] - corners[0]  # Top edge
        v2 = corners[2] - corners[1]   # Right edge
        v3 = corners[3] - corners[2]  # Bottom edge
        v4 = corners[0] - corners[3]  # Left edge
        
        # Check for zero-length edges
        if np.linalg.norm(v1) < 1 or np.linalg.norm(v2) < 1 or \
           np.linalg.norm(v3) < 1 or np.linalg.norm(v4) < 1:
            return False
        
        # Normalize vectors
        def normalize(v):
            norm = np.linalg.norm(v)
            return v / norm if norm > 0 else v
        
        v1_norm = normalize(v1)
        v3_norm = normalize(v3)
        v2_norm = normalize(v2)
        v4_norm = normalize(v4)
        
        # Check parallelism (dot product should be close to 1 or -1)
        top_bottom_parallel = abs(np.dot(v1_norm, v3_norm)) > parallel_threshold
        left_right_parallel = abs(np.dot(v2_norm, v4_norm)) > parallel_threshold
        
        # Check that angles are roughly 90 degrees (more lenient for close range)
        top_right_angle = abs(np.dot(v1_norm, v2_norm)) < angle_threshold
        
        # For close range, only require 2 out of 3 checks to pass
        if is_close_range:
            checks_passed = sum([top_bottom_parallel, left_right_parallel, top_right_angle])
            return checks_passed >= 2
        
        return top_bottom_parallel and left_right_parallel and top_right_angle
    
    def _calculate_detection_score(self, corners, area, solidity):
        """
        Calculate detection score based on multiple factors.
        
        Args:
            corners: Detected corners
            area: Contour area
            solidity: Contour solidity (area/hull_area)
        
        Returns:
            float: Detection score
        """
        score = 1.0
        
        # Prefer larger areas (up to a point)
        score *= min(area / 10000, 2.0)  # Normalize
        
        # Prefer higher solidity
        score *= solidity
        
        # Prefer rectangles with 4 vertices
        if len(corners) == 4:
            score *= 1.2
        
        return score
    
    def reset_size_tracking(self):
        """Reset size tracking (call when card is no longer visible)."""
        self.last_detected_area = None
        self.last_detected_corners = None
        self.consecutive_failures = 0
        self.has_ever_detected = False
    
    def _order_corners(self, corners):
        """
        Order corners in consistent order: top-left, top-right, bottom-right, bottom-left.
        
        Args:
            corners: 4x2 array of corner coordinates
        
        Returns:
            4x2 array of ordered corners
        """
        # Reshape to (4, 2)
        corners = corners.reshape(4, 2)
        
        # Calculate sum and difference
        sum_points = corners.sum(axis=1)
        diff_points = np.diff(corners, axis=1)
        
        # Top-left: smallest sum
        # Bottom-right: largest sum
        # Top-right: smallest difference
        # Bottom-left: largest difference
        top_left = corners[np.argmin(sum_points)]
        bottom_right = corners[np.argmax(sum_points)]
        top_right = corners[np.argmin(diff_points)]
        bottom_left = corners[np.argmax(diff_points)]
        
        return np.array([top_left, top_right, bottom_right, bottom_left], dtype=np.float32)

