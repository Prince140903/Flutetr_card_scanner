"""
Distance Guide Module
Analyzes card size relative to frame and provides distance guidance.
"""
import cv2
import numpy as np


class DistanceGuide:
    """Provides guidance for optimal card distance."""
    
    def __init__(self, min_area_ratio=0.10, max_area_ratio=0.75, optimal_min=0.20, optimal_max=0.65):
        """
        Initialize distance guide.
        
        Args:
            min_area_ratio: Minimum card area ratio to be considered (default: 10%)
            max_area_ratio: Maximum card area ratio to be considered (default: 75%)
            optimal_min: Minimum optimal area ratio (default: 20%)
            optimal_max: Maximum optimal area ratio (default: 65%)
        """
        self.min_area_ratio = min_area_ratio
        self.max_area_ratio = max_area_ratio
        self.optimal_min = optimal_min
        self.optimal_max = optimal_max
    
    def analyze_distance(self, frame, card_corners):
        """
        Analyze card distance and provide guidance.
        
        Args:
            frame: Input BGR frame
            card_corners: 4x2 array of card corner coordinates
        
        Returns:
            dict: {
                'is_optimal': bool,
                'message': str,
                'status': 'optimal' | 'too_close' | 'too_far'
            }
        """
        if frame is None or card_corners is None:
            return {
                'is_optimal': False,
                'message': 'Card not detected',
                'status': 'unknown'
            }
        
        # Calculate frame area
        frame_area = frame.shape[0] * frame.shape[1]
        
        # Calculate card area using contour area
        card_area = cv2.contourArea(card_corners)
        
        # Calculate area ratio
        area_ratio = card_area / frame_area if frame_area > 0 else 0
        
        # Determine status (ensure Python bools for JSON serialization)
        if area_ratio < self.min_area_ratio:
            return {
                'is_optimal': bool(False),
                'message': 'Move document closer',
                'status': 'too_far'
            }
        elif area_ratio > self.max_area_ratio:
            return {
                'is_optimal': bool(False),
                'message': 'Move document farther',
                'status': 'too_close'
            }
        elif self.optimal_min <= area_ratio <= self.optimal_max:
            return {
                'is_optimal': bool(True),
                'message': 'Distance OK',
                'status': 'optimal'
            }
        else:
            # Between min and optimal_min, or optimal_max and max_area_ratio
            if area_ratio < self.optimal_min:
                return {
                    'is_optimal': bool(False),
                    'message': 'Move document closer',
                    'status': 'too_far'
                }
            else:
                return {
                    'is_optimal': bool(False),
                    'message': 'Move document farther',
                    'status': 'too_close'
                }

