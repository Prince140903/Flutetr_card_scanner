"""
Glare Detection Module
Detects hotspots and reflections on card surface using multi-channel analysis,
spatial analysis, and adaptive thresholding.
"""
import cv2
import numpy as np


class GlareDetector:
    """Detects glare and hotspots on ID cards with enhanced algorithms."""
    
    def __init__(self, glare_threshold_value=240, max_glare_percentage=0.015, min_hotspot_size=50):
        """
        Initialize glare detector.
        
        Args:
            glare_threshold_value: Base pixel intensity threshold for glare (0-255, default: 240)
            max_glare_percentage: Maximum allowed percentage of card area with glare (default: 1.5%)
            min_hotspot_size: Minimum size of glare hotspot in pixels (default: 50)
        """
        self.glare_threshold_value = glare_threshold_value
        self.max_glare_percentage = max_glare_percentage
        self.min_hotspot_size = min_hotspot_size
    
    def detect_glare(self, frame, card_corners):
        """
        Detect glare/hotspots within the card region using multi-channel analysis.
        
        Args:
            frame: Input BGR frame
            card_corners: 4x2 array of card corner coordinates
        
        Returns:
            dict: {
                'is_acceptable': bool,
                'message': str,
                'glare_percentage': float
            }
        """
        if frame is None or card_corners is None:
            return {
                'is_acceptable': False,
                'message': 'Card not detected',
                'glare_percentage': 1.0
            }
        
        # Create mask for card region
        mask = np.zeros(frame.shape[:2], dtype=np.uint8)
        cv2.fillPoly(mask, [card_corners.astype(np.int32)], 255)
        
        # Calculate card area
        card_area = np.sum(mask == 255)
        
        if card_area == 0:
            return {
                'is_acceptable': False,
                'message': 'Card not detected',
                'glare_percentage': 1.0
            }
        
        # Extract card region
        x, y, w, h = cv2.boundingRect(card_corners.astype(np.int32))
        x = max(0, x)
        y = max(0, y)
        w = min(w, frame.shape[1] - x)
        h = min(h, frame.shape[0] - y)
        
        if w <= 0 or h <= 0:
            return {
                'is_acceptable': False,
                'message': 'Invalid card region',
                'glare_percentage': 1.0
            }
        
        card_region = frame[y:y+h, x:x+w]
        card_mask = mask[y:y+h, x:x+w]
        
        # Method 1: Grayscale analysis
        gray = cv2.cvtColor(card_region, cv2.COLOR_BGR2GRAY)
        
        # Method 2: HSV Value channel analysis (more sensitive to brightness)
        hsv = cv2.cvtColor(card_region, cv2.COLOR_BGR2HSV)
        v_channel = hsv[:, :, 2]  # Value channel
        
        # Calculate adaptive threshold based on card brightness
        mean_brightness = np.mean(gray[card_mask > 0])
        std_brightness = np.std(gray[card_mask > 0])
        
        # Adaptive threshold: higher for brighter cards, lower for darker
        adaptive_threshold = min(255, max(200, mean_brightness + 2 * std_brightness))
        threshold_value = min(self.glare_threshold_value, adaptive_threshold)
        
        # Detect glare in grayscale
        _, glare_gray = cv2.threshold(gray, threshold_value, 255, cv2.THRESH_BINARY)
        
        # Detect glare in HSV Value channel
        _, glare_v = cv2.threshold(v_channel, threshold_value, 255, cv2.THRESH_BINARY)
        
        # Combine both methods
        glare_combined = cv2.bitwise_or(glare_gray, glare_v)
        
        # Apply mask to only consider card region
        glare_masked = cv2.bitwise_and(glare_combined, card_mask)
        
        # Edge-aware detection: exclude edges from glare calculation
        # Edges are naturally bright and shouldn't count as glare
        edges = cv2.Canny(gray, 50, 150)
        edges_dilated = cv2.dilate(edges, np.ones((5, 5), np.uint8), iterations=2)
        glare_no_edges = cv2.bitwise_and(glare_masked, cv2.bitwise_not(edges_dilated))
        
        # Spatial analysis: find connected components (hotspots)
        num_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(glare_no_edges, connectivity=8)
        
        # Filter hotspots by size (ignore small noise)
        significant_hotspots = 0
        total_hotspot_pixels = 0
        
        for i in range(1, num_labels):  # Skip background (label 0)
            area = stats[i, cv2.CC_STAT_AREA]
            if area >= self.min_hotspot_size:
                significant_hotspots += 1
                total_hotspot_pixels += area
        
        # Also calculate overall glare percentage (for compatibility)
        glare_pixels = np.sum(glare_no_edges == 255)
        glare_percentage = glare_pixels / card_area if card_area > 0 else 1.0
        
        # Determine if acceptable based on both percentage and hotspot count
        # More lenient if hotspots are small and scattered
        is_acceptable = (
            glare_percentage <= self.max_glare_percentage and
            significant_hotspots <= 3  # Allow up to 3 significant hotspots
        )
        
        # Provide more specific feedback
        if is_acceptable:
            message = 'Glare acceptable'
        elif significant_hotspots > 3:
            message = 'Too many reflections'
        elif glare_percentage > self.max_glare_percentage * 2:
            message = 'Strong reflections detected'
        else:
            message = 'Avoid reflections'
        
        return {
            'is_acceptable': bool(is_acceptable),
            'message': message,
            'glare_percentage': float(glare_percentage),
            'hotspot_count': int(significant_hotspots)
        }

