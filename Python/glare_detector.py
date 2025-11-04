"""
Glare Detection Module
Detects hotspots and reflections on card surface.
"""
import cv2
import numpy as np


class GlareDetector:
    """Detects glare and hotspots on ID cards."""
    
    def __init__(self, glare_threshold_value=240, max_glare_percentage=0.01):
        """
        Initialize glare detector.
        
        Args:
            glare_threshold_value: Pixel intensity threshold for glare (0-255, default: 240)
            max_glare_percentage: Maximum allowed percentage of card area with glare (default: 1%)
        """
        self.glare_threshold_value = glare_threshold_value
        self.max_glare_percentage = max_glare_percentage
    
    def detect_glare(self, frame, card_corners):
        """
        Detect glare/hotspots within the card region.
        
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
        
        # Convert to grayscale
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # Create mask for card region
        mask = np.zeros(gray.shape, dtype=np.uint8)
        cv2.fillPoly(mask, [card_corners.astype(np.int32)], 255)
        
        # Calculate card area
        card_area = np.sum(mask == 255)
        
        if card_area == 0:
            return {
                'is_acceptable': False,
                'message': 'Card not detected',
                'glare_percentage': 1.0
            }
        
        # Threshold to find bright pixels (glare)
        _, glare_mask = cv2.threshold(gray, self.glare_threshold_value, 255, cv2.THRESH_BINARY)
        
        # Find glare pixels within card region
        glare_in_card = cv2.bitwise_and(glare_mask, mask)
        glare_pixels = np.sum(glare_in_card == 255)
        
        # Calculate glare percentage
        glare_percentage = glare_pixels / card_area if card_area > 0 else 1.0
        
        # Determine if acceptable (ensure Python bool for JSON serialization)
        is_acceptable = glare_percentage <= self.max_glare_percentage
        
        if is_acceptable:
            message = 'Glare acceptable'
        else:
            message = 'Avoid reflections'
        
        return {
            'is_acceptable': bool(is_acceptable),
            'message': message,
            'glare_percentage': float(glare_percentage)
        }

