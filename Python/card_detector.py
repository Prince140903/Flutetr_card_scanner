"""
Card Detection Module
Detects ID cards in camera frames using contour detection and aspect ratio filtering.
"""
import cv2
import numpy as np


class CardDetector:
    """Detects ID cards with standard credit/debit card dimensions."""
    
    # Standard ID card aspect ratio (85.60mm × 53.98mm ≈ 1.586)
    ASPECT_RATIO_MIN = 1.4
    ASPECT_RATIO_MAX = 1.7
    VERTICAL_ASPECT_MIN = 0.6  # 1/1.7
    VERTICAL_ASPECT_MAX = 0.75  # 1/1.4
    
    def __init__(self, min_area_ratio=0.03, max_area_ratio=0.85):
        """
        Initialize card detector.
        
        Args:
            min_area_ratio: Minimum card area as ratio of frame area (default: 3%)
            max_area_ratio: Maximum card area as ratio of frame area (default: 85%)
        """
        self.min_area_ratio = min_area_ratio
        self.max_area_ratio = max_area_ratio
    
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
        
        # Adaptive thresholding to improve detection in varying lighting
        # Try multiple Canny thresholds for better edge detection
        edges1 = cv2.Canny(blurred, 30, 100)
        edges2 = cv2.Canny(blurred, 50, 150)
        edges = cv2.bitwise_or(edges1, edges2)
        
        # Dilate edges to close gaps (more aggressive)
        kernel = np.ones((3, 3), np.uint8)
        edges = cv2.dilate(edges, kernel, iterations=2)
        edges = cv2.erode(edges, kernel, iterations=1)
        
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
            
            # Approximate contour to polygon (more lenient epsilon for better detection)
            peri = cv2.arcLength(contour, True)
            # Try with more lenient approximation first
            approx = cv2.approxPolyDP(contour, 0.03 * peri, True)
            
            # Must have 4 vertices for a rectangle (allow 3-5 for robustness)
            if len(approx) < 3 or len(approx) > 5:
                continue
            
            # If not exactly 4, try to refine
            if len(approx) != 4:
                # Try with stricter epsilon
                approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
                if len(approx) != 4:
                    # If still not 4, try to make it 4-sided
                    if len(approx) == 3:
                        # Add a 4th point for triangle-like shapes
                        # This happens when one corner is obscured
                        continue
                    elif len(approx) > 4:
                        # Too many points, skip
                        continue
            
            # Calculate bounding rectangle
            x, y, w, h = cv2.boundingRect(approx)
            rect_area = w * h
            
            # Check aspect ratio (handle both horizontal and vertical orientations)
            aspect_ratio = float(w) / h if h > 0 else 0
            inverse_aspect = float(h) / w if w > 0 else 0
            
            # Check if aspect ratio matches ID card dimensions
            is_horizontal = (self.ASPECT_RATIO_MIN <= aspect_ratio <= self.ASPECT_RATIO_MAX)
            is_vertical = (self.VERTICAL_ASPECT_MIN <= inverse_aspect <= self.VERTICAL_ASPECT_MAX)
            
            if is_horizontal or is_vertical:
                # Reshape to 4x2 array of points
                corners = approx.reshape(4, 2)
                valid_contours.append((corners, area))
        
        if not valid_contours:
            return False, None
        
        # Select the largest valid contour
        valid_contours.sort(key=lambda x: x[1], reverse=True)
        best_corners, _ = valid_contours[0]
        
        # Order corners: top-left, top-right, bottom-right, bottom-left
        ordered_corners = self._order_corners(best_corners)
        
        return True, ordered_corners
    
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

