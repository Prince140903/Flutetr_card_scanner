"""
Blur Detection Module
Detects motion blur using Laplacian variance.
"""
import cv2
import numpy as np


class BlurDetector:
    """Detects blur in images using Laplacian variance."""
    
    def __init__(self, blur_threshold=40.0):
        """
        Initialize blur detector.
        
        Args:
            blur_threshold: Laplacian variance threshold (default: 40.0)
                Lower values indicate more blur
        """
        self.blur_threshold = blur_threshold
    
    def detect_blur(self, frame, card_corners=None):
        """
        Detect blur in the frame, optionally only within card region.
        
        Args:
            frame: Input BGR frame
            card_corners: Optional 4x2 array of card corner coordinates
                If provided, only analyze blur within card region
        
        Returns:
            tuple: (is_blurry: bool, variance: float)
        """
        if frame is None:
            return True, 0.0
        
        # Convert to grayscale
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        
        # If card corners provided, create mask and analyze only card region
        if card_corners is not None:
            # Create mask for card region
            mask = np.zeros(gray.shape, dtype=np.uint8)
            cv2.fillPoly(mask, [card_corners.astype(np.int32)], 255)
            
            # Apply mask
            masked_gray = cv2.bitwise_and(gray, mask)
            
            # Calculate Laplacian variance only in card region
            laplacian = cv2.Laplacian(masked_gray, cv2.CV_64F)
            variance = laplacian.var()
        else:
            # Analyze entire frame
            laplacian = cv2.Laplacian(gray, cv2.CV_64F)
            variance = laplacian.var()
        
        # Lower variance indicates more blur
        is_blurry = variance < self.blur_threshold
        
        return is_blurry, variance

