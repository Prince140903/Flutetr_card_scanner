import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Distance Guide Module
/// Analyzes card size relative to frame and provides distance guidance.
class DistanceGuide {
  final double minAreaRatio;
  final double maxAreaRatio;
  final double optimalMin;
  final double optimalMax;

  DistanceGuide({
    this.minAreaRatio = 0.10,
    this.maxAreaRatio = 0.75,
    this.optimalMin = 0.20,
    this.optimalMax = 0.65,
  });

  /// Analyze card distance and provide guidance
  /// Returns: {
  ///   isOptimal: bool,
  ///   message: String,
  ///   status: 'optimal' | 'too_close' | 'too_far' | 'unknown'
  /// }
  ({
    bool isOptimal,
    String message,
    String status,
  }) analyzeDistance(
    Uint8List imageBytes,
    List<math.Point<int>> cardCorners,
  ) {
    try {
      // Decode image to get dimensions (or pass dimensions directly to avoid decode)
      final image = img.decodeImage(imageBytes);
      if (image == null || cardCorners.isEmpty) {
        return (
          isOptimal: false,
          message: 'Card not detected',
          status: 'unknown',
        );
      }

      // Calculate frame area
      final frameArea = image.width * image.height;

      // Calculate card area using Shoelace formula
      final cardArea = _calculatePolygonArea(cardCorners);

      // Calculate area ratio
      final areaRatio = frameArea > 0 ? cardArea / frameArea : 0.0;

      // Determine status
      if (areaRatio < minAreaRatio) {
        return (
          isOptimal: false,
          message: 'Move document closer',
          status: 'too_far',
        );
      } else if (areaRatio > maxAreaRatio) {
        return (
          isOptimal: false,
          message: 'Move document farther',
          status: 'too_close',
        );
      } else if (areaRatio >= optimalMin && areaRatio <= optimalMax) {
        return (
          isOptimal: true,
          message: 'Distance OK',
          status: 'optimal',
        );
      } else {
        // Between min and optimalMin, or optimalMax and maxAreaRatio
        if (areaRatio < optimalMin) {
          return (
            isOptimal: false,
            message: 'Move document closer',
            status: 'too_far',
          );
        } else {
          return (
            isOptimal: false,
            message: 'Move document farther',
            status: 'too_close',
          );
        }
      }
    } catch (e) {
      // Error handled silently
      return (
        isOptimal: false,
        message: 'Card not detected',
        status: 'unknown',
      );
    }
  }

  /// Calculate polygon area using Shoelace formula
  double _calculatePolygonArea(List<math.Point<int>> points) {
    double area = 0;
    for (var i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].x * points[j].y;
      area -= points[j].x * points[i].y;
    }
    return area.abs() / 2.0;
  }
}

