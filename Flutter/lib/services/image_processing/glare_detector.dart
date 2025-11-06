import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Glare Detection Module
/// Detects hotspots and reflections on card surface.
class GlareDetector {
  final int glareThresholdValue; // 0-255
  final double maxGlarePercentage;

  GlareDetector({
    this.glareThresholdValue = 240,
    this.maxGlarePercentage = 0.01, // 1%
  });

  /// Detect glare/hotspots within the card region
  /// Returns: {
  ///   isAcceptable: bool,
  ///   message: String,
  ///   glarePercentage: double
  /// }
  Future<({
    bool isAcceptable,
    String message,
    double glarePercentage,
  })> detectGlare(
    Uint8List imageBytes,
    List<math.Point<int>> cardCorners,
  ) async {
    try {
      if (cardCorners.isEmpty || cardCorners.length != 4) {
        return (
          isAcceptable: false,
          message: 'Card not detected',
          glarePercentage: 1.0,
        );
      }

      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return (
          isAcceptable: false,
          message: 'Card not detected',
          glarePercentage: 1.0,
        );
      }

      // Convert to grayscale
      final gray = img.grayscale(image);

      // Create mask for card region
      final mask = _createPolygonMask(image.width, image.height, cardCorners);

      // Calculate card area
      int cardArea = 0;
      for (var i = 0; i < mask.length; i++) {
        if (mask[i]) cardArea++;
      }

      if (cardArea == 0) {
        return (
          isAcceptable: false,
          message: 'Card not detected',
          glarePercentage: 1.0,
        );
      }

      // Count bright pixels (glare) within card region
      int glarePixels = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final idx = y * image.width + x;
          if (mask[idx]) {
            final pixel = gray.getPixel(x, y);
            if (pixel.r >= glareThresholdValue) {
              glarePixels++;
            }
          }
        }
      }

      // Calculate glare percentage
      final glarePercentage = glarePixels / cardArea;

      // Determine if acceptable
      final isAcceptable = glarePercentage <= maxGlarePercentage;

      final message = isAcceptable ? 'Glare acceptable' : 'Avoid reflections';

      return (
        isAcceptable: isAcceptable,
        message: message,
        glarePercentage: glarePercentage,
      );
    } catch (e) {
      // Error handled silently
      return (
        isAcceptable: false,
        message: 'Error detecting glare',
        glarePercentage: 1.0,
      );
    }
  }

  /// Create a mask for polygon region using ray casting algorithm
  List<bool> _createPolygonMask(
    int width,
    int height,
    List<math.Point<int>> corners,
  ) {
    final mask = List.generate(width * height, (_) => false);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (_isPointInPolygon(math.Point(x, y), corners)) {
          mask[y * width + x] = true;
        }
      }
    }

    return mask;
  }

  /// Ray casting algorithm to check if point is inside polygon
  bool _isPointInPolygon(math.Point<int> point, List<math.Point<int>> polygon) {
    bool inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final xi = polygon[i].x;
      final yi = polygon[i].y;
      final xj = polygon[j].x;
      final yj = polygon[j].y;

      final intersect = ((yi > point.y) != (yj > point.y)) &&
          (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi);
      if (intersect) {
        inside = !inside;
      }
    }
    return inside;
  }
}

