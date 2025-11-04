"""
Perspective Transformation Module
Extracts and warps card image to rectangular format.
"""
import cv2
import numpy as np


class WarpTransformer:
    """Transforms detected card to rectangular image using perspective transformation."""
    
    # Standard ID card dimensions at 100 DPI (85.6mm × 53.98mm)
    CARD_WIDTH_MM = 85.6
    CARD_HEIGHT_MM = 53.98
    DPI = 100
    
    def __init__(self, output_width=None, output_height=None, dpi=None):
        """
        Initialize warp transformer.
        
        Args:
            output_width: Output image width in pixels (default: calculated from DPI)
            output_height: Output image height in pixels (default: calculated from DPI)
            dpi: Dots per inch for output (default: 100)
        """
        if dpi is not None:
            self.DPI = dpi
        
        # Calculate output dimensions
        if output_width is None or output_height is None:
            # Convert mm to inches, then to pixels
            width_inches = self.CARD_WIDTH_MM / 25.4
            height_inches = self.CARD_HEIGHT_MM / 25.4
            self.output_width = int(width_inches * self.DPI)
            self.output_height = int(height_inches * self.DPI)
        else:
            self.output_width = output_width
            self.output_height = output_height
    
    def warp_card(self, frame, card_corners):
        """
        Extract and warp card to rectangular image.
        
        Args:
            frame: Input BGR frame
            card_corners: 4x2 array of card corner coordinates (ordered)
        
        Returns:
            np.ndarray: Warped rectangular card image, or None if transformation fails
        """
        if frame is None or card_corners is None:
            return None
        
        try:
            # Ensure corners are float32
            src_points = card_corners.astype(np.float32)
            
            # Define destination points for rectangular output
            # Order: top-left, top-right, bottom-right, bottom-left
            dst_points = np.array([
                [0, 0],                                    # top-left
                [self.output_width - 1, 0],                # top-right
                [self.output_width - 1, self.output_height - 1],  # bottom-right
                [0, self.output_height - 1]               # bottom-left
            ], dtype=np.float32)
            
            # Calculate perspective transform matrix
            M = cv2.getPerspectiveTransform(src_points, dst_points)
            
            # Apply perspective transformation
            warped = cv2.warpPerspective(
                frame,
                M,
                (self.output_width, self.output_height),
                flags=cv2.INTER_LINEAR,
                borderMode=cv2.BORDER_CONSTANT,
                borderValue=(0, 0, 0)
            )
            
            return warped
        except Exception as e:
            print(f"Error in warp_card: {e}")
            return None
    
    def get_output_dimensions(self):
        """
        Get output image dimensions.
        
        Returns:
            tuple: (width, height)
        """
        return (self.output_width, self.output_height)

