import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Card Detection Module
/// Detects ID cards in camera frames using edge detection and contour analysis.
class CardDetector {
  // Standard ID card aspect ratio (85.60mm × 53.98mm ≈ 1.586)
  static const double aspectRatioMin = 1.3;
  static const double aspectRatioMax = 1.8;
  static const double verticalAspectMin = 0.55; // 1/1.8
  static const double verticalAspectMax = 0.77; // 1/1.3

  final double minAreaRatio;
  final double maxAreaRatio;
  
  // Size retention for stable detection
  double? _lastDetectedArea;
  final double areaTolerance = 0.3; // 30% variance allowed

  CardDetector({
    this.minAreaRatio = 0.02,
    this.maxAreaRatio = 0.85,
  });

  /// Detect ID card in the frame
  /// Returns: (cardFound: bool, corners: List<Point>? or null)
  /// corners is a list of 4 points [top-left, top-right, bottom-right, bottom-left]
  Future<({bool found, List<math.Point<int>>? corners})> detectCard(
    Uint8List imageBytes,
  ) async {
    try {
      // Decode image
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return (found: false, corners: null);
      }

      // Convert to grayscale
      final gray = img.grayscale(image);

      // Apply Gaussian blur
      final blurred = img.gaussianBlur(gray, radius: 5);

      // Edge detection using Canny algorithm
      final edges = _cannyEdgeDetection(blurred);

      // Find contours
      final contours = _findContours(edges);

      if (contours.isEmpty) {
        return (found: false, corners: null);
      }

      // Filter contours by area and shape
      final frameArea = image.width * image.height;
      final minArea = frameArea * minAreaRatio;
      final maxArea = frameArea * maxAreaRatio;

      final validContours = <({List<math.Point<int>> corners, double area})>[];

      for (final contour in contours) {
        final area = _calculatePolygonArea(contour);
        
        // Check area bounds
        if (area < minArea || area > maxArea) {
          continue;
        }

        // Approximate polygon
        final approx = _approximatePolygon(contour);
        
        if (approx.length < 3) {
          continue;
        }

        // Get bounding rectangle
        final bounds = _getBoundingRect(approx);
        final width = bounds.width;
        final height = bounds.height;

        if (width == 0 || height == 0) {
          continue;
        }

        // Calculate aspect ratio
        final aspectRatio = width / height;
        final inverseAspect = height / width;

        // Check if aspect ratio matches ID card dimensions
        final isHorizontal = aspectRatio >= aspectRatioMin && aspectRatio <= aspectRatioMax;
        final isVertical = inverseAspect >= verticalAspectMin && inverseAspect <= verticalAspectMax;

        if (isHorizontal || isVertical) {
          // Create corners from bounding rect or use approximated polygon
          List<math.Point<int>> corners;
          if (approx.length == 4) {
            corners = _orderCorners(approx);
          } else {
            // Create bounding rectangle corners
            corners = [
              math.Point(bounds.left, bounds.top),
              math.Point(bounds.right, bounds.top),
              math.Point(bounds.right, bounds.bottom),
              math.Point(bounds.left, bounds.bottom),
            ];
          }
          validContours.add((corners: corners, area: area));
        }
      }

      if (validContours.isEmpty) {
        _resetSizeTracking();
        return (found: false, corners: null);
      }

      // Select best contour (prefer similar size if we have previous detection)
      final best = _selectBestContour(validContours);
      
      // Update last detected area
      _lastDetectedArea = best.area;

      return (found: true, corners: best.corners);
    } catch (e) {
      // Error handled silently
      return (found: false, corners: null);
    }
  }

  /// Reset size tracking (call when card is no longer visible)
  void resetSizeTracking() {
    _lastDetectedArea = null;
  }

  void _resetSizeTracking() {
    _lastDetectedArea = null;
  }

  /// Canny edge detection implementation
  Uint8List _cannyEdgeDetection(img.Image gray) {
    // Apply Sobel operator for gradient
    final sobelX = _sobelX(gray);
    final sobelY = _sobelY(gray);
    
    // Calculate gradient magnitude and direction
    final gradient = _calculateGradient(sobelX, sobelY);
    
    // Non-maximum suppression
    final suppressed = _nonMaximumSuppression(gradient);
    
    // Double threshold and edge tracking
    return _doubleThreshold(suppressed, lowThreshold: 20, highThreshold: 80);
  }

  Uint8List _sobelX(img.Image gray) {
    final result = Uint8List(gray.width * gray.height);
    final kernel = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
    
    for (var y = 1; y < gray.height - 1; y++) {
      for (var x = 1; x < gray.width - 1; x++) {
        var sum = 0.0;
        for (var ky = 0; ky < 3; ky++) {
          for (var kx = 0; kx < 3; kx++) {
            final px = gray.getPixel(x + kx - 1, y + ky - 1);
            sum += (px.r * kernel[ky * 3 + kx]);
          }
        }
        result[y * gray.width + x] = sum.abs().round().clamp(0, 255);
      }
    }
    return result;
  }

  Uint8List _sobelY(img.Image gray) {
    final result = Uint8List(gray.width * gray.height);
    final kernel = [-1, -2, -1, 0, 0, 0, 1, 2, 1];
    
    for (var y = 1; y < gray.height - 1; y++) {
      for (var x = 1; x < gray.width - 1; x++) {
        var sum = 0.0;
        for (var ky = 0; ky < 3; ky++) {
          for (var kx = 0; kx < 3; kx++) {
            final px = gray.getPixel(x + kx - 1, y + ky - 1);
            sum += (px.r * kernel[ky * 3 + kx]);
          }
        }
        result[y * gray.width + x] = sum.abs().round().clamp(0, 255);
      }
    }
    return result;
  }

  List<({int magnitude, double direction})> _calculateGradient(
    Uint8List sobelX,
    Uint8List sobelY,
  ) {
    final gradient = <({int magnitude, double direction})>[];
    for (var i = 0; i < sobelX.length; i++) {
      final gx = sobelX[i].toDouble();
      final gy = sobelY[i].toDouble();
      final magnitude = math.sqrt(gx * gx + gy * gy).toInt();
      final direction = math.atan2(gy, gx);
      gradient.add((magnitude: magnitude, direction: direction));
    }
    return gradient;
  }

  Uint8List _nonMaximumSuppression(
    List<({int magnitude, double direction})> gradient,
  ) {
    final width = math.sqrt(gradient.length).toInt();
    final height = width;
    final result = Uint8List(gradient.length);
    
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final idx = y * width + x;
        final mag = gradient[idx].magnitude;
        final dir = gradient[idx].direction;
        
        // Determine neighbors based on gradient direction
        int neighbor1, neighbor2;
        if ((dir >= -math.pi / 8 && dir < math.pi / 8) ||
            (dir >= 7 * math.pi / 8 || dir < -7 * math.pi / 8)) {
          // Horizontal
          neighbor1 = gradient[idx - 1].magnitude;
          neighbor2 = gradient[idx + 1].magnitude;
        } else if ((dir >= math.pi / 8 && dir < 3 * math.pi / 8) ||
                   (dir >= -7 * math.pi / 8 && dir < -5 * math.pi / 8)) {
          // Diagonal 1
          neighbor1 = gradient[(y - 1) * width + (x + 1)].magnitude;
          neighbor2 = gradient[(y + 1) * width + (x - 1)].magnitude;
        } else if ((dir >= 3 * math.pi / 8 && dir < 5 * math.pi / 8) ||
                   (dir >= -5 * math.pi / 8 && dir < -3 * math.pi / 8)) {
          // Vertical
          neighbor1 = gradient[(y - 1) * width + x].magnitude;
          neighbor2 = gradient[(y + 1) * width + x].magnitude;
        } else {
          // Diagonal 2
          neighbor1 = gradient[(y - 1) * width + (x - 1)].magnitude;
          neighbor2 = gradient[(y + 1) * width + (x + 1)].magnitude;
        }
        
        if (mag >= neighbor1 && mag >= neighbor2) {
          result[idx] = mag.clamp(0, 255).toInt();
        } else {
          result[idx] = 0;
        }
      }
    }
    return result;
  }

  Uint8List _doubleThreshold(
    Uint8List suppressed, {
    required int lowThreshold,
    required int highThreshold,
  }) {
    final result = Uint8List(suppressed.length);
    final width = math.sqrt(suppressed.length).toInt();
    final height = width;
    
    // Mark strong and weak edges
    for (var i = 0; i < suppressed.length; i++) {
      if (suppressed[i] >= highThreshold) {
        result[i] = 255; // Strong edge
      } else if (suppressed[i] >= lowThreshold) {
        result[i] = 128; // Weak edge
      } else {
        result[i] = 0;
      }
    }
    
    // Edge tracking by hysteresis
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final idx = y * width + x;
        if (result[idx] == 128) {
          // Check if connected to strong edge
          bool connected = false;
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nIdx = (y + dy) * width + (x + dx);
              if (result[nIdx] == 255) {
                connected = true;
                break;
              }
            }
            if (connected) break;
          }
          result[idx] = connected ? 255 : 0;
        }
      }
    }
    
    return result;
  }

  /// Find contours in binary image
  List<List<math.Point<int>>> _findContours(Uint8List binary) {
    final width = math.sqrt(binary.length).toInt();
    final height = width;
    final visited = List.generate(width * height, (_) => false);
    final contours = <List<math.Point<int>>>[];
    
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        if (binary[idx] == 255 && !visited[idx]) {
          // Found new contour
          final contour = <math.Point<int>>[];
          _traceContour(binary, visited, width, height, x, y, contour);
          if (contour.length >= 4) {
            contours.add(contour);
          }
        }
      }
    }
    
    return contours;
  }

  void _traceContour(
    Uint8List binary,
    List<bool> visited,
    int width,
    int height,
    int startX,
    int startY,
    List<math.Point<int>> contour,
  ) {
    final stack = <math.Point<int>>[math.Point(startX, startY)];
    
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final x = point.x;
      final y = point.y;
      
      if (x < 0 || x >= width || y < 0 || y >= height) continue;
      final idx = y * width + x;
      if (visited[idx] || binary[idx] != 255) continue;
      
      visited[idx] = true;
      contour.add(point);
      
      // Add 8-connected neighbors
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          stack.add(math.Point(x + dx, y + dy));
        }
      }
    }
  }

  /// Approximate polygon using Douglas-Peucker algorithm
  List<math.Point<int>> _approximatePolygon(
    List<math.Point<int>> contour, {
    double epsilon = 0.02,
  }) {
    if (contour.length <= 2) return contour;
    
    final peri = _calculatePerimeter(contour);
    final epsilonScaled = epsilon * peri;
    
    return _douglasPeucker(contour, epsilonScaled);
  }

  List<math.Point<int>> _douglasPeucker(
    List<math.Point<int>> points,
    double epsilon,
  ) {
    if (points.length <= 2) return points;
    
    // Find point with maximum distance from line
    double maxDist = 0;
    int maxIndex = 0;
    final start = points.first;
    final end = points.last;
    
    for (var i = 1; i < points.length - 1; i++) {
      final dist = _pointToLineDistance(points[i], start, end);
      if (dist > maxDist) {
        maxDist = dist;
        maxIndex = i;
      }
    }
    
    if (maxDist > epsilon) {
      // Recursively simplify
      final left = _douglasPeucker(points.sublist(0, maxIndex + 1), epsilon);
      final right = _douglasPeucker(points.sublist(maxIndex), epsilon);
      
      // Combine (remove duplicate point)
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      // Return only endpoints
      return [start, end];
    }
  }

  double _pointToLineDistance(
    math.Point<int> point,
    math.Point<int> lineStart,
    math.Point<int> lineEnd,
  ) {
    final dx = lineEnd.x - lineStart.x;
    final dy = lineEnd.y - lineStart.y;
    
    if (dx == 0 && dy == 0) {
      return math.sqrt(
        math.pow(point.x - lineStart.x, 2) + math.pow(point.y - lineStart.y, 2),
      );
    }
    
    final t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) /
        (dx * dx + dy * dy);
    
    final clampedT = t.clamp(0.0, 1.0);
    final projX = lineStart.x + clampedT * dx;
    final projY = lineStart.y + clampedT * dy;
    
    return math.sqrt(
      math.pow(point.x - projX, 2) + math.pow(point.y - projY, 2),
    );
  }

  double _calculatePerimeter(List<math.Point<int>> points) {
    double peri = 0;
    for (var i = 0; i < points.length; i++) {
      final next = points[(i + 1) % points.length];
      final dx = next.x - points[i].x;
      final dy = next.y - points[i].y;
      peri += math.sqrt(dx * dx + dy * dy);
    }
    return peri;
  }

  double _calculatePolygonArea(List<math.Point<int>> points) {
    // Shoelace formula
    double area = 0;
    for (var i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].x * points[j].y;
      area -= points[j].x * points[i].y;
    }
    return area.abs() / 2.0;
  }

  ({int left, int top, int right, int bottom, int width, int height})
      _getBoundingRect(List<math.Point<int>> points) {
    int minX = points[0].x;
    int maxX = points[0].x;
    int minY = points[0].y;
    int maxY = points[0].y;
    
    for (final point in points) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
    }
    
    return (
      left: minX,
      top: minY,
      right: maxX,
      bottom: maxY,
      width: maxX - minX,
      height: maxY - minY,
    );
  }

  List<math.Point<int>> _orderCorners(List<math.Point<int>> corners) {
    // Order corners: top-left, top-right, bottom-right, bottom-left
    // Calculate sum and difference
    final sums = corners.map((p) => p.x + p.y).toList();
    final diffs = corners.map((p) => p.x - p.y).toList();
    
    final topLeft = corners[sums.indexOf(sums.reduce(math.min))];
    final bottomRight = corners[sums.indexOf(sums.reduce(math.max))];
    final topRight = corners[diffs.indexOf(diffs.reduce(math.min))];
    final bottomLeft = corners[diffs.indexOf(diffs.reduce(math.max))];
    
    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  ({List<math.Point<int>> corners, double area}) _selectBestContour(
    List<({List<math.Point<int>> corners, double area})> contours,
  ) {
    if (_lastDetectedArea == null) {
      // Sort by area (largest first)
      contours.sort((a, b) => b.area.compareTo(a.area));
      return contours.first;
    }
    
    // Prefer similar size
    contours.sort((a, b) {
      final aDiff = ((a.area - _lastDetectedArea!).abs() / _lastDetectedArea!);
      final bDiff = ((b.area - _lastDetectedArea!).abs() / _lastDetectedArea!);
      
      if (aDiff <= areaTolerance && bDiff <= areaTolerance) {
        return b.area.compareTo(a.area); // Prefer larger
      } else if (aDiff <= areaTolerance) {
        return -1; // a is better
      } else if (bDiff <= areaTolerance) {
        return 1; // b is better
      } else {
        return aDiff.compareTo(bDiff); // Prefer closer
      }
    });
    
    return contours.first;
  }
}

