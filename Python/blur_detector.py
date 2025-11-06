"""
Blur Detection Module
Detects blur using multi-metric approach: Laplacian variance, FFT analysis,
edge sharpness, and motion blur detection.
"""
import cv2
import numpy as np


class BlurDetector:
    """Detects blur in images using multiple metrics."""
    
    def __init__(self, blur_threshold=40.0, fft_threshold=0.1, edge_sharpness_threshold=0.3):
        """
        Initialize blur detector.
        
        Args:
            blur_threshold: Laplacian variance threshold (default: 40.0)
                Lower values indicate more blur
            fft_threshold: FFT-based blur threshold (default: 0.1)
                Lower values indicate more blur
            edge_sharpness_threshold: Edge sharpness threshold (default: 0.3)
                Lower values indicate more blur
        """
        self.blur_threshold = blur_threshold
        self.fft_threshold = fft_threshold
        self.edge_sharpness_threshold = edge_sharpness_threshold
    
    def detect_blur(self, frame, card_corners=None):
        """
        Detect blur using multiple metrics: Laplacian variance, FFT, and edge sharpness.
        
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
        
        # Extract region of interest
        if card_corners is not None:
            # Extract card region for focused analysis
            x, y, w, h = cv2.boundingRect(card_corners.astype(np.int32))
            x = max(0, x)
            y = max(0, y)
            w = min(w, frame.shape[1] - x)
            h = min(h, frame.shape[0] - y)
            
            if w > 0 and h > 0:
                roi = gray[y:y+h, x:x+w]
            else:
                roi = gray
        else:
            roi = gray
        
        if roi.size == 0:
            return True, 0.0
        
        # Method 1: Laplacian variance (traditional method)
        laplacian = cv2.Laplacian(roi, cv2.CV_64F)
        laplacian_variance = laplacian.var()
        
        # Method 2: FFT-based blur detection
        # Blurry images have less high-frequency content
        fft_score = self._fft_blur_score(roi)
        
        # Method 3: Edge sharpness analysis
        # Analyze gradient magnitudes at edges
        edge_sharpness = self._edge_sharpness_score(roi)
        
        # Method 4: Motion blur detection (directional blur)
        motion_blur_score = self._detect_motion_blur(roi)
        
        # Adaptive threshold based on image brightness
        # Darker images naturally have lower variance
        mean_brightness = np.mean(roi)
        adaptive_threshold = self.blur_threshold * (mean_brightness / 128.0)
        adaptive_threshold = max(20.0, min(60.0, adaptive_threshold))
        
        # Combine metrics with weights
        # Laplacian variance is primary, others are supporting
        laplacian_score = 1.0 if laplacian_variance >= adaptive_threshold else 0.0
        fft_score_normalized = 1.0 if fft_score >= self.fft_threshold else 0.0
        edge_score_normalized = 1.0 if edge_sharpness >= self.edge_sharpness_threshold else 0.0
        motion_score_normalized = 1.0 if motion_blur_score > 0.5 else 0.0
        
        # Weighted combination (Laplacian is most reliable)
        combined_score = (
            0.5 * laplacian_score +
            0.2 * fft_score_normalized +
            0.2 * edge_score_normalized +
            0.1 * motion_score_normalized
        )
        
        # Consider blurry if combined score is below threshold
        is_blurry = combined_score < 0.5
        
        # Return Laplacian variance for compatibility (primary metric)
        return is_blurry, laplacian_variance
    
    def _fft_blur_score(self, gray_roi):
        """
        Calculate FFT-based blur score.
        Blurry images have less high-frequency content.
        
        Args:
            gray_roi: Grayscale region of interest
        
        Returns:
            float: Blur score (higher = sharper)
        """
        # Resize to power of 2 for efficient FFT
        h, w = gray_roi.shape
        h_pow2 = 2 ** int(np.log2(h))
        w_pow2 = 2 ** int(np.log2(w))
        
        if h_pow2 < 32 or w_pow2 < 32:
            # Too small for meaningful FFT
            return 0.5
        
        roi_resized = cv2.resize(gray_roi, (w_pow2, h_pow2))
        
        # Compute FFT
        fft = np.fft.fft2(roi_resized)
        fft_shift = np.fft.fftshift(fft)
        magnitude = np.abs(fft_shift)
        
        # Calculate high-frequency content
        # Focus on frequencies in the outer 30% of the spectrum
        center_y, center_x = h_pow2 // 2, w_pow2 // 2
        y, x = np.ogrid[:h_pow2, :w_pow2]
        
        # Create mask for high frequencies
        radius = min(h_pow2, w_pow2) * 0.35
        mask = (x - center_x) ** 2 + (y - center_y) ** 2 > radius ** 2
        
        high_freq_energy = np.sum(magnitude[mask])
        total_energy = np.sum(magnitude)
        
        if total_energy == 0:
            return 0.0
        
        # Normalize score
        score = high_freq_energy / total_energy
        return float(score)
    
    def _edge_sharpness_score(self, gray_roi):
        """
        Calculate edge sharpness by analyzing gradient magnitudes.
        
        Args:
            gray_roi: Grayscale region of interest
        
        Returns:
            float: Edge sharpness score (higher = sharper)
        """
        # Calculate gradients
        grad_x = cv2.Sobel(gray_roi, cv2.CV_64F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(gray_roi, cv2.CV_64F, 0, 1, ksize=3)
        gradient_magnitude = np.sqrt(grad_x**2 + grad_y**2)
        
        # Find edges using Canny
        edges = cv2.Canny(gray_roi, 50, 150)
        
        # Calculate average gradient magnitude at edge locations
        edge_pixels = gradient_magnitude[edges > 0]
        
        if len(edge_pixels) == 0:
            return 0.0
        
        # Normalize by image brightness
        mean_brightness = np.mean(gray_roi)
        if mean_brightness == 0:
            return 0.0
        
        avg_gradient = np.mean(edge_pixels)
        normalized_score = avg_gradient / (mean_brightness * 2.0)
        
        return float(min(1.0, normalized_score))
    
    def _detect_motion_blur(self, gray_roi):
        """
        Detect directional motion blur.
        
        Args:
            gray_roi: Grayscale region of interest
        
        Returns:
            float: Motion blur score (higher = more motion blur detected)
        """
        # Calculate gradients
        grad_x = cv2.Sobel(gray_roi, cv2.CV_64F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(gray_roi, cv2.CV_64F, 0, 1, ksize=3)
        
        # Calculate gradient direction
        direction = np.arctan2(grad_y, grad_x)
        magnitude = np.sqrt(grad_x**2 + grad_y**2)
        
        # Find dominant direction (motion blur creates directional patterns)
        # Use histogram of gradient directions weighted by magnitude
        hist_bins = 36  # 10 degrees per bin
        hist, _ = np.histogram(direction.flatten(), bins=hist_bins, 
                              range=(-np.pi, np.pi), weights=magnitude.flatten())
        
        # Motion blur creates peaks in the histogram
        # Calculate peakiness (variance of histogram)
        if np.sum(hist) == 0:
            return 0.0
        
        hist_normalized = hist / np.sum(hist)
        peakiness = np.std(hist_normalized)
        
        # High peakiness indicates motion blur
        return float(min(1.0, peakiness * 5.0))

