"""
Quality Validator Module
Validates that captured image meets all quality requirements.
"""
from card_detector import CardDetector
from blur_detector import BlurDetector
from glare_detector import GlareDetector
from distance_guide import DistanceGuide
from centering_guide import CenteringGuide


class QualityValidator:
    """Validates final captured image quality."""
    
    def __init__(self):
        """Initialize quality validator with all detection modules."""
        self.card_detector = CardDetector()
        self.blur_detector = BlurDetector()
        self.glare_detector = GlareDetector()
        self.distance_guide = DistanceGuide()
        self.centering_guide = CenteringGuide()
    
    def validate(self, frame):
        """
        Validate that frame meets all quality requirements.
        
        Args:
            frame: Input BGR frame to validate
        
        Returns:
            dict: {
                'is_valid': bool,
                'card_detected': bool,
                'is_sharp': bool,
                'glare_acceptable': bool,
                'distance_optimal': bool,
                'is_centered': bool,
                'messages': list of str,
                'card_corners': np.array or None
            }
        """
        result = {
            'is_valid': False,
            'card_detected': False,
            'is_sharp': False,
            'glare_acceptable': False,
            'distance_optimal': False,
            'is_centered': False,
            'messages': [],
            'card_corners': None
        }
        
        # Check if card is detected
        card_found, card_corners = self.card_detector.detect_card(frame)
        result['card_detected'] = bool(card_found)
        result['card_corners'] = card_corners
        
        if not card_found:
            result['messages'].append('Card not detected')
            return result
        
        # Check blur
        is_blurry, blur_variance = self.blur_detector.detect_blur(frame, card_corners)
        result['is_sharp'] = bool(not is_blurry)
        if is_blurry:
            result['messages'].append(f'Image is blurry (variance: {blur_variance:.1f})')
        
        # Check glare
        glare_result = self.glare_detector.detect_glare(frame, card_corners)
        result['glare_acceptable'] = bool(glare_result['is_acceptable'])
        if not glare_result['is_acceptable']:
            result['messages'].append(glare_result['message'])
        
        # Check distance
        distance_result = self.distance_guide.analyze_distance(frame, card_corners)
        result['distance_optimal'] = bool(distance_result['is_optimal'])
        if not distance_result['is_optimal']:
            result['messages'].append(distance_result['message'])
        
        # Check centering (less critical, but good to have)
        centering_result = self.centering_guide.analyze_centering(frame, card_corners)
        result['is_centered'] = bool(centering_result['is_centered'])
        
        # Determine overall validity (ensure all are Python bools)
        # Relaxed requirements: card detected, reasonable quality (not perfect)
        # Allow capture even with minor issues
        result['is_valid'] = bool(
            result['card_detected'] and
            result['is_sharp'] and  # Still need sharpness for readability
            result['distance_optimal']  # Distance is important
            # Glare and centering are less critical - allow minor issues
        )
        
        if result['is_valid']:
            result['messages'].append('Quality check passed')
        
        return result
    
    def is_valid(self, frame):
        """
        Quick check if frame is valid (convenience method).
        
        Args:
            frame: Input BGR frame
        
        Returns:
            bool: True if valid
        """
        result = self.validate(frame)
        return result['is_valid']

