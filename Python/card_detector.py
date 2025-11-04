"""
Card Detection Module
Detects ID cards in camera frames using contour detection and aspect ratio filtering.
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
    
    def __init__(self, min_area_ratio=0.02, max_area_ratio=0.85):  # Changed default from 0.03 to 0.02
        """
        Initialize card detector.
        
        Args:
            min_area_ratio: Minimum card area as ratio of frame area (default: 2%)
            max_area_ratio: Maximum card area as ratio of frame area (default: 85%)
        """
        self.min_area_ratio = min_area_ratio
        self.max_area_ratio = max_area_ratio
        # Size retention for stable detection
        self.last_detected_area = None
        self.area_tolerance = 0.3  # 30% variance allowed for size matching
    
    def detect_card(self, frame):
        """
        Detect ID card in the frame.
        
        Args:
            frame: Input BGR frame from camera
        
        Returns:
            tuple: (card_found: bool, corners: np.array or None)
                corners is a 4x2 array of card corner coordinates if found
        """
        if frame is None:
            return False, None
        
        # Convert to grayscale
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # Apply Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # Multiple edge detection methods for better coverage
        # Lower thresholds for better edge detection in varying lighting
        edges1 = cv2.Canny(blurred, 20, 80)  # Lowered from 30, 100
        edges2 = cv2.Canny(blurred, 40, 120)  # Lowered from 50, 150
        edges3 = cv2.Canny(blurred, 30, 100)
        edges = cv2.bitwise_or(edges1, edges2)
        edges = cv2.bitwise_or(edges, edges3)
        
        # Also try adaptive thresholding for low contrast scenarios
        adaptive_thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, 
            cv2.THRESH_BINARY_INV, 11, 2
        )
        edges = cv2.bitwise_or(edges, adaptive_thresh)
        
        # More aggressive dilation to close gaps
        kernel = np.ones((3, 3), np.uint8)
        edges = cv2.dilate(edges, kernel, iterations=3)  # Increased from 2
        edges = cv2.erode(edges, kernel, iterations=1)
        edges = cv2.dilate(edges, kernel, iterations=1)  # Additional dilation
        
        # Find contours
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        
        if not contours:
            return False, None
        
        # Filter contours by area and shape
        frame_area = frame.shape[0] * frame.shape[1]
        min_area = frame_area * self.min_area_ratio
        max_area = frame_area * self.max_area_ratio
        
        valid_contours = []
        
        for contour in contours:
            area = cv2.contourArea(contour)
            
            # Check area bounds
            if area < min_area or area > max_area:
                continue
            
            # Approximate contour to polygon (more lenient epsilon)
            peri = cv2.arcLength(contour, True)
            if peri == 0:
                continue
            
            # Try with lenient approximation first (0.04 instead of 0.03)
            approx = cv2.approxPolyDP(contour, 0.04 * peri, True)
            
            # Allow 3-6 vertices for better detection (was 3-5)
            if len(approx) < 3 or len(approx) > 6:
                continue
            
            # If we have 3-5 vertices, try to refine to 4
            if len(approx) != 4:
                # Try with slightly stricter epsilon
                approx = cv2.approxPolyDP(contour, 0.03 * peri, True)
                if len(approx) < 4 or len(approx) > 5:
                    # If still not 4-5, try even more lenient
                    approx = cv2.approxPolyDP(contour, 0.05 * peri, True)
                    if len(approx) < 3 or len(approx) > 6:
                        continue
            
            # If we have 3 or 5+ points, we'll create a bounding rectangle
            if len(approx) != 4:
                # Create bounding box from the approximation
                x, y, w, h = cv2.boundingRect(approx)
                # Create 4 corners from bounding box
                approx = np.array([
                    [[x, y]],           # top-left
                    [[x+w, y]],         # top-right
                    [[x+w, y+h]],       # bottom-right
                    [[x, y+h]]          # bottom-left
                ], dtype=np.float32)
            
            # Calculate bounding rectangle
            x, y, w, h = cv2.boundingRect(approx)
            rect_area = w * h
            
            # Check aspect ratio (handle both horizontal and vertical orientations)
            aspect_ratio = float(w) / h if h > 0 else 0
            inverse_aspect = float(h) / w if w > 0 else 0
            
            # Check if aspect ratio matches ID card dimensions (more lenient ranges)
            is_horizontal = (self.ASPECT_RATIO_MIN <= aspect_ratio <= self.ASPECT_RATIO_MAX)
            is_vertical = (self.VERTICAL_ASPECT_MIN <= inverse_aspect <= self.VERTICAL_ASPECT_MAX)
            
            if is_horizontal or is_vertical:
                # Reshape to 4x2 array of points
                corners = approx.reshape(4, 2)
                valid_contours.append((corners, area))
        
        if not valid_contours:
            return False, None
        
        # If we have a previous detection, prefer similar-sized cards
        if self.last_detected_area is not None:
            # Sort by closeness to last detected area, then by size
            def sort_key(item):
                corners, area = item
                area_diff = abs(area - self.last_detected_area) / self.last_detected_area
                # Prefer cards within tolerance, then by size
                if area_diff <= self.area_tolerance:
                    return (0, -area)  # Within tolerance, prefer larger
                else:
                    return (1, area_diff)  # Outside tolerance, prefer closer
            
            valid_contours.sort(key=sort_key)
        else:
            # No previous detection, just sort by size
            valid_contours.sort(key=lambda x: x[1], reverse=True)
        
        best_corners, best_area = valid_contours[0]
        
        # Update last detected area if we found a good match
        if self.last_detected_area is None or best_area > 0:
            # Use exponential moving average for stability
            if self.last_detected_area is None:
                self.last_detected_area = best_area
            else:
                # Weighted average: 70% old, 30% new
                self.last_detected_area = 0.7 * self.last_detected_area + 0.3 * best_area
        
        # Order corners: top-left, top-right, bottom-right, bottom-left
        ordered_corners = self._order_corners(best_corners)
        
        return True, ordered_corners
    
    def reset_size_tracking(self):
        """Reset size tracking (call when card is no longer visible)."""
        self.last_detected_area = None
    
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

