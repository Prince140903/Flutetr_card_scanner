"""
Centering Guide Module
Checks if card is centered in frame and provides centering guidance.
"""
import numpy as np
import cv2


class CenteringGuide:
    """Provides guidance for centering the card in frame."""
    
    def __init__(self, center_threshold_ratio=0.15):
        """
        Initialize centering guide.
        
        Args:
            center_threshold_ratio: Maximum allowed distance from center as ratio of frame dimension (default: 15%)
        """
        self.center_threshold_ratio = center_threshold_ratio
    
    def analyze_centering(self, frame, card_corners):
        """
        Analyze card centering and provide guidance.
        
        Args:
            frame: Input BGR frame
            card_corners: 4x2 array of card corner coordinates
        
        Returns:
            dict: {
                'is_centered': bool,
                'message': str,
                'status': 'centered' | 'off_center'
            }
        """
        if frame is None or card_corners is None:
            return {
                'is_centered': False,
                'message': 'Card not detected',
                'status': 'off_center'
            }
        
        # Get frame dimensions
        frame_height, frame_width = frame.shape[:2]
        frame_center_x = frame_width / 2.0
        frame_center_y = frame_height / 2.0
        
        # Calculate card center using moments
        M = cv2.moments(card_corners)
        if M["m00"] == 0:
            return {
                'is_centered': False,
                'message': 'Center document',
                'status': 'off_center'
            }
        
        card_center_x = M["m10"] / M["m00"]
        card_center_y = M["m01"] / M["m00"]
        
        # Calculate distance from frame center
        dx = card_center_x - frame_center_x
        dy = card_center_y - frame_center_y
        
        # Calculate threshold (use average of width and height)
        threshold_x = frame_width * self.center_threshold_ratio
        threshold_y = frame_height * self.center_threshold_ratio
        
        # Check if centered
        is_centered_x = abs(dx) <= threshold_x
        is_centered_y = abs(dy) <= threshold_y
        is_centered = is_centered_x and is_centered_y
        
        # Ensure Python bools for JSON serialization
        if is_centered:
            return {
                'is_centered': bool(True),
                'message': 'Centered',
                'status': 'centered'
            }
        else:
            # Provide directional guidance
            if abs(dx) > abs(dy):
                # Horizontal offset is larger
                if dx > 0:
                    message = 'Move document left'
                else:
                    message = 'Move document right'
            else:
                # Vertical offset is larger
                if dy > 0:
                    message = 'Move document up'
                else:
                    message = 'Move document down'
            
            return {
                'is_centered': bool(False),
                'message': message,
                'status': 'off_center'
            }

