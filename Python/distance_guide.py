"""
Distance Guide Module
Analyzes card size relative to frame and provides distance guidance using
physical size estimation, multi-factor analysis, and hysteresis for stability.
"""
import cv2
import numpy as np


class DistanceGuide:
    """Provides guidance for optimal card distance with enhanced accuracy."""
    
    # Standard ID card physical dimensions (ISO/IEC 7810 ID-1)
    CARD_WIDTH_MM = 85.60  # millimeters
    CARD_HEIGHT_MM = 53.98  # millimeters
    CARD_AREA_MM2 = CARD_WIDTH_MM * CARD_HEIGHT_MM
    
    # Typical camera FOV assumptions (can be calibrated per device)
    # Assuming typical smartphone camera: ~60-70 degrees horizontal FOV
    DEFAULT_HORIZONTAL_FOV_DEG = 65.0  # degrees
    DEFAULT_ASPECT_RATIO = 16.0 / 9.0  # Typical camera aspect ratio
    
    def __init__(self, min_area_ratio=0.10, max_area_ratio=0.75, optimal_min=0.25, optimal_max=0.60):
        """
        Initialize distance guide.
        
        Args:
            min_area_ratio: Minimum card area ratio to be considered (default: 10%)
            max_area_ratio: Maximum card area ratio to be considered (default: 75%)
            optimal_min: Minimum optimal area ratio (default: 25%)
            optimal_max: Maximum optimal area ratio (default: 60%)
        """
        self.min_area_ratio = min_area_ratio
        self.max_area_ratio = max_area_ratio
        self.optimal_min = optimal_min
        self.optimal_max = optimal_max
        
        # Hysteresis for stability (prevent flickering)
        self.last_status = None
        self.hysteresis_threshold = 0.02  # 2% threshold for state change
        
        # Estimated camera parameters (can be calibrated)
        self.camera_fov_horizontal = self.DEFAULT_HORIZONTAL_FOV_DEG
        self.camera_aspect_ratio = self.DEFAULT_ASPECT_RATIO
    
    def analyze_distance(self, frame, card_corners):
        """
        Analyze card distance using multi-factor analysis: area ratio, edge length,
        perspective angle, and physical size estimation.
        
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
        
        # Calculate frame dimensions
        frame_height, frame_width = frame.shape[:2]
        frame_area = frame_height * frame_width
        
        # Factor 1: Area ratio (primary metric)
        card_area = cv2.contourArea(card_corners)
        area_ratio = card_area / frame_area if frame_area > 0 else 0
        
        # Factor 2: Edge length analysis
        # Calculate average edge length in pixels
        edge_lengths = []
        for i in range(4):
            p1 = card_corners[i]
            p2 = card_corners[(i + 1) % 4]
            edge_length = np.linalg.norm(p2 - p1)
            edge_lengths.append(edge_length)
        
        avg_edge_length = np.mean(edge_lengths)
        max_edge_length = max(edge_lengths)
        
        # Estimate card width/height in pixels
        card_width_px = max(edge_lengths[0], edge_lengths[2])  # Top/bottom edges
        card_height_px = max(edge_lengths[1], edge_lengths[3])  # Left/right edges
        
        # Factor 3: Perspective angle (tilt affects apparent size)
        # Calculate perspective distortion
        top_edge = np.linalg.norm(card_corners[1] - card_corners[0])
        bottom_edge = np.linalg.norm(card_corners[2] - card_corners[3])
        left_edge = np.linalg.norm(card_corners[3] - card_corners[0])
        right_edge = np.linalg.norm(card_corners[2] - card_corners[1])
        
        # Perspective distortion factor (ratio of opposite edges)
        horizontal_distortion = min(top_edge, bottom_edge) / max(top_edge, bottom_edge) if max(top_edge, bottom_edge) > 0 else 1.0
        vertical_distortion = min(left_edge, right_edge) / max(left_edge, right_edge) if max(left_edge, right_edge) > 0 else 1.0
        perspective_factor = (horizontal_distortion + vertical_distortion) / 2.0
        
        # Factor 4: Physical size estimation
        # Estimate distance based on known card dimensions
        # This is approximate and depends on camera calibration
        frame_diagonal_px = np.sqrt(frame_width**2 + frame_height**2)
        card_diagonal_px = np.sqrt(card_width_px**2 + card_height_px**2)
        card_diagonal_mm = np.sqrt(self.CARD_WIDTH_MM**2 + self.CARD_HEIGHT_MM**2)
        
        # Estimate pixels per mm (rough approximation)
        # Assuming card fills reasonable portion of frame
        if card_diagonal_px > 0:
            pixels_per_mm = card_diagonal_px / card_diagonal_mm
            # Estimate frame width in mm (approximate)
            frame_width_mm_est = frame_width / pixels_per_mm
            # Estimate FOV based on frame width
            # This is a rough approximation
            estimated_distance_factor = frame_width_mm_est / (2 * np.tan(np.radians(self.camera_fov_horizontal / 2)))
        else:
            estimated_distance_factor = 1.0
        
        # Combine factors with weights
        # Area ratio is primary (70%), edge length (15%), perspective (10%), physical size (5%)
        area_score = self._score_area_ratio(area_ratio)
        edge_score = self._score_edge_length(avg_edge_length, frame_diagonal_px)
        perspective_score = perspective_factor  # Higher is better (less distortion)
        physical_score = min(1.0, estimated_distance_factor)  # Normalize
        
        combined_score = (
            0.70 * area_score +
            0.15 * edge_score +
            0.10 * perspective_score +
            0.05 * physical_score
        )
        
        # Apply hysteresis to prevent flickering
        status = self._determine_status_with_hysteresis(area_ratio, combined_score)
        
        # Generate message
        if status == 'optimal':
            message = 'Distance OK'
            is_optimal = True
        elif status == 'too_far':
            message = 'Move document closer'
            is_optimal = False
        elif status == 'too_close':
            message = 'Move document farther'
            is_optimal = False
        else:
            message = 'Adjust distance'
            is_optimal = False
        
        return {
            'is_optimal': bool(is_optimal),
            'message': message,
            'status': status
        }
    
    def _score_area_ratio(self, area_ratio):
        """Score area ratio (0-1, higher is better)."""
        if area_ratio < self.min_area_ratio:
            return 0.0
        elif area_ratio > self.max_area_ratio:
            return 0.0
        elif self.optimal_min <= area_ratio <= self.optimal_max:
            return 1.0
        else:
            # Linear interpolation for in-between values
            if area_ratio < self.optimal_min:
                return (area_ratio - self.min_area_ratio) / (self.optimal_min - self.min_area_ratio)
            else:
                return 1.0 - (area_ratio - self.optimal_max) / (self.max_area_ratio - self.optimal_max)
    
    def _score_edge_length(self, avg_edge_length, frame_diagonal):
        """Score edge length relative to frame (0-1, higher is better)."""
        if frame_diagonal == 0:
            return 0.5
        
        # Optimal edge length is roughly 30-50% of frame diagonal
        edge_ratio = avg_edge_length / frame_diagonal
        optimal_min_ratio = 0.25
        optimal_max_ratio = 0.45
        
        if optimal_min_ratio <= edge_ratio <= optimal_max_ratio:
            return 1.0
        elif edge_ratio < optimal_min_ratio:
            return edge_ratio / optimal_min_ratio
        else:
            return max(0.0, 1.0 - (edge_ratio - optimal_max_ratio) / (0.6 - optimal_max_ratio))
    
    def _determine_status_with_hysteresis(self, area_ratio, combined_score):
        """Determine status with hysteresis to prevent flickering."""
        # Determine new status based on area ratio
        if area_ratio < self.min_area_ratio:
            new_status = 'too_far'
        elif area_ratio > self.max_area_ratio:
            new_status = 'too_close'
        elif self.optimal_min <= area_ratio <= self.optimal_max:
            new_status = 'optimal'
        elif area_ratio < self.optimal_min:
            new_status = 'too_far'
        else:
            new_status = 'too_close'
        
        # Apply hysteresis: only change status if difference is significant
        if self.last_status is None:
            self.last_status = new_status
            return new_status
        
        # If status would change, check if difference is significant
        if new_status != self.last_status:
            # Calculate threshold boundaries with hysteresis
            if self.last_status == 'optimal':
                # Need larger change to leave optimal zone
                if new_status == 'too_far':
                    threshold = self.optimal_min - self.hysteresis_threshold
                    if area_ratio >= threshold:
                        return self.last_status  # Stay in optimal
                elif new_status == 'too_close':
                    threshold = self.optimal_max + self.hysteresis_threshold
                    if area_ratio <= threshold:
                        return self.last_status  # Stay in optimal
            else:
                # Need larger change to enter optimal zone
                if new_status == 'optimal':
                    if self.last_status == 'too_far':
                        threshold = self.optimal_min + self.hysteresis_threshold
                        if area_ratio < threshold:
                            return self.last_status  # Stay too_far
                    elif self.last_status == 'too_close':
                        threshold = self.optimal_max - self.hysteresis_threshold
                        if area_ratio > threshold:
                            return self.last_status  # Stay too_close
        
        # Status change is significant, update
        self.last_status = new_status
        return new_status

