import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Improved card detection matching Python logic more closely
class SimpleCardDetector {
  static const double aspectRatioMin = 1.3;
  static const double aspectRatioMax = 1.8;
  static const double verticalAspectMin = 0.55; // 1/1.8
  static const double verticalAspectMax = 0.77; // 1/1.3

  final double minAreaRatio;
  final double maxAreaRatio;

  SimpleCardDetector({
    this.minAreaRatio = 0.02, // 2% of frame
    this.maxAreaRatio = 0.85, // 85% of frame
  });

  /// Detect card using improved algorithm
  Future<({bool found, List<math.Point<int>>? corners})> detectCard(
    Uint8List imageBytes,
  ) async {
    try {
      // Decode and resize to lower resolution for faster processing
      var image = img.decodeImage(imageBytes);
      if (image == null) {
        return (found: false, corners: null);
      }

      // Store original dimensions for scaling
      final originalWidth = image.width;
      final originalHeight = image.height;
      double scaleX = 1.0;
      double scaleY = 1.0;

      // Don't resize for detection - Python processes at full resolution for accuracy
      // Only resize if image is extremely large (>800px) to prevent memory issues
      if (image.width > 800) {
        final ratio = 800.0 / image.width;
        scaleX = originalWidth / 800.0;
        scaleY = originalHeight / (image.height * ratio);
        image = img.copyResize(
          image,
          width: 800,
          height: (image.height * ratio).round(),
        );
      }

      // Convert to grayscale
      final gray = img.grayscale(image);

      // Apply Gaussian blur - Python uses (5,5) kernel which is ~radius 2.5
      final blurred = img.gaussianBlur(gray, radius: 2);

      // Improved edge detection - combine multiple methods
      final edges = _improvedEdgeDetection(blurred);

      // Find contours
      final contours = _findContours(edges, image.width, image.height);

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

        // Approximate polygon - Python uses [0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08]
        List<math.Point<int>>? approx;
        for (final epsilonFactor in [0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08]) {
          final testApprox = _approximatePolygon(contour, epsilon: epsilonFactor);
          if (testApprox.length == 4) {
            approx = testApprox;
            break;
          } else if (testApprox.length >= 3 && testApprox.length <= 5 && approx == null) {
            approx = testApprox;
          }
        }

        if (approx == null || approx.length < 3) {
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
          // Create corners from approximation or bounding rect
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
        return (found: false, corners: null);
      }

      // Select largest contour
      validContours.sort((a, b) => b.area.compareTo(a.area));
      final best = validContours.first;

      // Scale corners back to original image size
      final scaledCorners = best.corners.map((p) => math.Point(
        (p.x * scaleX).round(),
        (p.y * scaleY).round(),
      )).toList();

      return (found: true, corners: scaledCorners);
    } catch (e) {
      return (found: false, corners: null);
    }
  }

  /// Improved edge detection matching Python's Canny + adaptive threshold
  Uint8List _improvedEdgeDetection(img.Image gray) {
    final width = gray.width;
    final height = gray.height;
    
    // Python uses 3 Canny edge detections with different thresholds
    // Canny uses hysteresis (low, high) thresholds - we'll simulate with Sobel
    final edges1 = _cannyLikeEdgeDetection(gray, lowThreshold: 20, highThreshold: 80);
    final edges2 = _cannyLikeEdgeDetection(gray, lowThreshold: 40, highThreshold: 120);
    final edges3 = _cannyLikeEdgeDetection(gray, lowThreshold: 30, highThreshold: 100);
    
    // Combine all three (like Python's bitwise_or)
    final combined = Uint8List(width * height);
    for (var i = 0; i < combined.length; i++) {
      combined[i] = (edges1[i] == 255 || edges2[i] == 255 || edges3[i] == 255) ? 255 : 0;
    }
    
    // Add adaptive thresholding (like Python)
    final adaptive = _adaptiveThreshold(gray);
    for (var i = 0; i < combined.length; i++) {
      if (adaptive[i] == 255) combined[i] = 255;
    }
    
    // Python uses: dilate(3) -> erode(1) -> dilate(1)
    var result = _dilate(combined, width, height, iterations: 3);
    result = _erode(result, width, height, iterations: 1);
    result = _dilate(result, width, height, iterations: 1);
    
    return result;
  }
  
  /// Canny-like edge detection with hysteresis (low and high thresholds)
  Uint8List _cannyLikeEdgeDetection(img.Image gray, {required int lowThreshold, required int highThreshold}) {
    final width = gray.width;
    final height = gray.height;
    final result = Uint8List(width * height);
    
    // First pass: detect strong edges (above high threshold)
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final gx = -gray.getPixel(x - 1, y - 1).r +
            gray.getPixel(x + 1, y - 1).r -
            2 * gray.getPixel(x - 1, y).r +
            2 * gray.getPixel(x + 1, y).r -
            gray.getPixel(x - 1, y + 1).r +
            gray.getPixel(x + 1, y + 1).r;

        final gy = -gray.getPixel(x - 1, y - 1).r -
            2 * gray.getPixel(x, y - 1).r -
            gray.getPixel(x + 1, y - 1).r +
            gray.getPixel(x - 1, y + 1).r +
            2 * gray.getPixel(x, y + 1).r +
            gray.getPixel(x + 1, y + 1).r;

        final magnitude = math.sqrt(gx * gx + gy * gy);
        
        // Strong edge
        if (magnitude > highThreshold) {
          result[y * width + x] = 255;
        }
      }
    }
    
    // Second pass: connect weak edges (between low and high) to strong edges
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        if (result[y * width + x] == 0) {
          final gx = -gray.getPixel(x - 1, y - 1).r +
              gray.getPixel(x + 1, y - 1).r -
              2 * gray.getPixel(x - 1, y).r +
              2 * gray.getPixel(x + 1, y).r -
              gray.getPixel(x - 1, y + 1).r +
              gray.getPixel(x + 1, y + 1).r;

          final gy = -gray.getPixel(x - 1, y - 1).r -
              2 * gray.getPixel(x, y - 1).r -
              gray.getPixel(x + 1, y - 1).r +
              gray.getPixel(x - 1, y + 1).r +
              2 * gray.getPixel(x, y + 1).r +
              gray.getPixel(x + 1, y + 1).r;

          final magnitude = math.sqrt(gx * gx + gy * gy);
          
          // Weak edge - check if connected to strong edge
          if (magnitude > lowThreshold && magnitude <= highThreshold) {
            // Check 8 neighbors for strong edge
            bool connected = false;
            for (var dy = -1; dy <= 1 && !connected; dy++) {
              for (var dx = -1; dx <= 1 && !connected; dx++) {
                if (dx == 0 && dy == 0) continue;
                final nx = x + dx;
                final ny = y + dy;
                if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
                  if (result[ny * width + nx] == 255) {
                    connected = true;
                  }
                }
              }
            }
            if (connected) {
              result[y * width + x] = 255;
            }
          }
        }
      }
    }
    
    return result;
  }
  
  /// Adaptive thresholding (like Python's cv2.adaptiveThreshold)
  Uint8List _adaptiveThreshold(img.Image gray) {
    final width = gray.width;
    final height = gray.height;
    final result = Uint8List(width * height);
    
    const blockSize = 11;
    const c = 2;
    
    // Process every 2nd pixel for speed
    for (var y = 0; y < height; y += 2) {
      for (var x = 0; x < width; x += 2) {
        // Calculate mean of local neighborhood
        var sum = 0.0;
        var count = 0;

        for (var dy = -blockSize ~/ 2; dy <= blockSize ~/ 2; dy++) {
          for (var dx = -blockSize ~/ 2; dx <= blockSize ~/ 2; dx++) {
            final nx = math.max(0, math.min(width - 1, x + dx)).toInt();
            final ny = math.max(0, math.min(height - 1, y + dy)).toInt();
            sum += gray.getPixel(nx, ny).r.toDouble();
            count++;
          }
        }

        final mean = sum / count;
        final pixelValue = gray.getPixel(x, y).r;
        final threshold = (mean - c).round();
        
        // THRESH_BINARY_INV: pixel < threshold ? 255 : 0
        final value = pixelValue < threshold ? 255 : 0;
        
        // Fill 2x2 block
        result[y * width + x] = value;
        if (x + 1 < width) result[y * width + (x + 1)] = value;
        if (y + 1 < height) result[(y + 1) * width + x] = value;
        if (x + 1 < width && y + 1 < height) {
          result[(y + 1) * width + (x + 1)] = value;
        }
      }
    }
    
    return result;
  }
  
  /// Erosion operation
  Uint8List _erode(Uint8List binary, int width, int height, {int iterations = 1}) {
    var result = Uint8List.fromList(binary);

    for (var iter = 0; iter < iterations; iter++) {
      final temp = Uint8List.fromList(result);
      for (var y = 1; y < height - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          if (temp[y * width + x] == 255) {
            // Check if all 4-connected neighbors are 255
            bool allNeighbors = true;
            if (x > 0 && temp[y * width + (x - 1)] != 255) allNeighbors = false;
            if (x < width - 1 && temp[y * width + (x + 1)] != 255) allNeighbors = false;
            if (y > 0 && temp[(y - 1) * width + x] != 255) allNeighbors = false;
            if (y < height - 1 && temp[(y + 1) * width + x] != 255) allNeighbors = false;
            
            if (!allNeighbors) {
              result[y * width + x] = 0;
            }
          }
        }
      }
    }

    return result;
  }
  
  /// Simple dilation operation
  Uint8List _dilate(Uint8List binary, int width, int height, {int iterations = 1}) {
    if (iterations == 0) return binary;
    
    var result = Uint8List.fromList(binary);

    for (var iter = 0; iter < iterations; iter++) {
      final temp = Uint8List.fromList(result);
      for (var y = 1; y < height - 1; y++) {
        for (var x = 1; x < width - 1; x++) {
          if (temp[y * width + x] == 255) {
            // Dilate with 4-connected (faster than 8-connected)
            if (x > 0) result[y * width + (x - 1)] = 255;
            if (x < width - 1) result[y * width + (x + 1)] = 255;
            if (y > 0) result[(y - 1) * width + x] = 255;
            if (y < height - 1) result[(y + 1) * width + x] = 255;
          }
        }
      }
    }

    return result;
  }

  /// Find contours in binary image (check all pixels for accuracy)
  List<List<math.Point<int>>> _findContours(Uint8List binary, int width, int height) {
    final visited = List.generate(width * height, (_) => false);
    final contours = <List<math.Point<int>>>[];

    // Check all pixels for better accuracy (but limit contour tracing depth)
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        if (idx < binary.length && binary[idx] == 255 && !visited[idx]) {
          final contour = <math.Point<int>>[];
          _traceContour(binary, visited, width, height, x, y, contour);
          if (contour.length >= 10) { // Minimum contour size for valid shapes
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
    final sums = corners.map((p) => p.x + p.y).toList();
    final diffs = corners.map((p) => p.x - p.y).toList();

    final topLeft = corners[sums.indexOf(sums.reduce(math.min))];
    final bottomRight = corners[sums.indexOf(sums.reduce(math.max))];
    final topRight = corners[diffs.indexOf(diffs.reduce(math.min))];
    final bottomLeft = corners[diffs.indexOf(diffs.reduce(math.max))];

    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  void resetSizeTracking() {
    // No-op for simple detector
  }
}
