import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Centering Guide Module
/// Checks if card is centered in frame and provides centering guidance.
class CenteringGuide {
  final double centerThresholdRatio;

  CenteringGuide({this.centerThresholdRatio = 0.15});

  /// Analyze card centering and provide guidance
  /// Returns: {
  ///   isCentered: bool,
  ///   message: String,
  ///   status: 'centered' | 'off_center'
  /// }
  ({
    bool isCentered,
    String message,
    String status,
  }) analyzeCentering(
    Uint8List imageBytes,
    List<math.Point<int>> cardCorners,
  ) {
    try {
      // Decode image to get dimensions
      final image = img.decodeImage(imageBytes);
      if (image == null || cardCorners.isEmpty) {
        return (
          isCentered: false,
          message: 'Card not detected',
          status: 'off_center',
        );
      }

      // Get frame dimensions
      final frameWidth = image.width.toDouble();
      final frameHeight = image.height.toDouble();
      final frameCenterX = frameWidth / 2.0;
      final frameCenterY = frameHeight / 2.0;

      // Calculate card center using centroid
      final cardCenter = _calculateCentroid(cardCorners);
      final cardCenterX = cardCenter.x;
      final cardCenterY = cardCenter.y;

      // Calculate distance from frame center
      final dx = cardCenterX - frameCenterX;
      final dy = cardCenterY - frameCenterY;

      // Calculate threshold
      final thresholdX = frameWidth * centerThresholdRatio;
      final thresholdY = frameHeight * centerThresholdRatio;

      // Check if centered
      final isCenteredX = dx.abs() <= thresholdX;
      final isCenteredY = dy.abs() <= thresholdY;
      final isCentered = isCenteredX && isCenteredY;

      if (isCentered) {
        return (
          isCentered: true,
          message: 'Centered',
          status: 'centered',
        );
      } else {
        // Provide directional guidance
        String message;
        if (dx.abs() > dy.abs()) {
          // Horizontal offset is larger
          message = dx > 0 ? 'Move document left' : 'Move document right';
        } else {
          // Vertical offset is larger
          message = dy > 0 ? 'Move document up' : 'Move document down';
        }

        return (
          isCentered: false,
          message: message,
          status: 'off_center',
        );
      }
    } catch (e) {
      // Error handled silently
      return (
        isCentered: false,
        message: 'Center document',
        status: 'off_center',
      );
    }
  }

  /// Calculate centroid of polygon
  math.Point<double> _calculateCentroid(List<math.Point<int>> points) {
    double sumX = 0;
    double sumY = 0;
    for (final point in points) {
      sumX += point.x;
      sumY += point.y;
    }
    return math.Point(sumX / points.length, sumY / points.length);
  }
}

