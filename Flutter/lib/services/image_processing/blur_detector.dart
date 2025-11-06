import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Blur Detection Module
/// Detects motion blur using Laplacian variance.
class BlurDetector {
  final double blurThreshold;

  BlurDetector({this.blurThreshold = 40.0});

  /// Detect blur in the frame, optionally only within card region
  /// Returns: (isBlurry: bool, variance: double)
  Future<({bool isBlurry, double variance})> detectBlur(
    Uint8List imageBytes, {
    List<math.Point<int>>? cardCorners,
  }) async {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return (isBlurry: true, variance: 0.0);
      }

      // Convert to grayscale
      final gray = img.grayscale(image);

      // If card corners provided, analyze only card region
      if (cardCorners != null && cardCorners.length == 4) {
        final variance = _calculateLaplacianVarianceMasked(gray, cardCorners);
        final isBlurry = variance < blurThreshold;
        return (isBlurry: isBlurry, variance: variance);
      } else {
        // Analyze entire frame
        final variance = _calculateLaplacianVariance(gray);
        final isBlurry = variance < blurThreshold;
        return (isBlurry: isBlurry, variance: variance);
      }
    } catch (e) {
      // Error handled silently
      return (isBlurry: true, variance: 0.0);
    }
  }

  /// Calculate Laplacian variance for entire image
  double _calculateLaplacianVariance(img.Image gray) {
    // Laplacian kernel: [[0, 1, 0], [1, -4, 1], [0, 1, 0]]
    final laplacian = Float64List(gray.width * gray.height);
    double sum = 0;
    int count = 0;

    for (var y = 1; y < gray.height - 1; y++) {
      for (var x = 1; x < gray.width - 1; x++) {
        final p1 = gray.getPixel(x, y - 1).r;
        final p2 = gray.getPixel(x - 1, y).r;
        final p3 = gray.getPixel(x, y).r;
        final p4 = gray.getPixel(x + 1, y).r;
        final p5 = gray.getPixel(x, y + 1).r;

        final laplacianValue = (p1 + p2 + p4 + p5 - 4 * p3).toDouble();
        final idx = y * gray.width + x;
        laplacian[idx] = laplacianValue;
        sum += laplacianValue;
        count++;
      }
    }

    if (count == 0) return 0.0;

    final mean = sum / count;
    double variance = 0;
    for (var i = 0; i < laplacian.length; i++) {
      if (laplacian[i] != 0) {
        variance += math.pow(laplacian[i] - mean, 2);
      }
    }
    variance /= count;

    return variance;
  }

  /// Calculate Laplacian variance only within card region
  double _calculateLaplacianVarianceMasked(
    img.Image gray,
    List<math.Point<int>> cardCorners,
  ) {
    // Create mask for card region
    final mask = _createPolygonMask(gray.width, gray.height, cardCorners);
    
    // Laplacian kernel
    final laplacian = Float64List(gray.width * gray.height);
    double sum = 0;
    int count = 0;

    for (var y = 1; y < gray.height - 1; y++) {
      for (var x = 1; x < gray.width - 1; x++) {
        final idx = y * gray.width + x;
        if (!mask[idx]) continue; // Skip pixels outside mask

        final p1 = gray.getPixel(x, y - 1).r;
        final p2 = gray.getPixel(x - 1, y).r;
        final p3 = gray.getPixel(x, y).r;
        final p4 = gray.getPixel(x + 1, y).r;
        final p5 = gray.getPixel(x, y + 1).r;

        final laplacianValue = (p1 + p2 + p4 + p5 - 4 * p3).toDouble();
        laplacian[idx] = laplacianValue;
        sum += laplacianValue;
        count++;
      }
    }

    if (count == 0) return 0.0;

    final mean = sum / count;
    double variance = 0;
    for (var i = 0; i < laplacian.length; i++) {
      if (mask[i] && laplacian[i] != 0) {
        variance += math.pow(laplacian[i] - mean, 2);
      }
    }
    variance /= count;

    return variance;
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

