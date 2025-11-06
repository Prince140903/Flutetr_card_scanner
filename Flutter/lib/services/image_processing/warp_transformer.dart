import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Perspective Transformation Module
/// Extracts and warps card image to rectangular format.
class WarpTransformer {
  // Standard ID card dimensions at 100 DPI (85.6mm × 53.98mm)
  static const double cardWidthMM = 85.6;
  static const double cardHeightMM = 53.98;
  static const int defaultDpi = 100;

  final int outputWidth;
  final int outputHeight;

  WarpTransformer({
    int? outputWidth,
    int? outputHeight,
    int dpi = defaultDpi,
  })  : outputWidth = outputWidth ??
            _calculateOutputWidth(dpi),
        outputHeight = outputHeight ??
            _calculateOutputHeight(dpi);

  static int _calculateOutputWidth(int dpi) {
    // Convert mm to inches, then to pixels
    final widthInches = cardWidthMM / 25.4;
    return (widthInches * dpi).round();
  }

  static int _calculateOutputHeight(int dpi) {
    // Convert mm to inches, then to pixels
    final heightInches = cardHeightMM / 25.4;
    return (heightInches * dpi).round();
  }

  /// Extract and warp card to rectangular image
  /// Returns: Warped image bytes or null if transformation fails
  Future<Uint8List?> warpCard(
    Uint8List imageBytes,
    List<math.Point<int>> cardCorners,
  ) async {
    try {
      if (cardCorners.length != 4) {
        return null;
      }

      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return null;
      }

      // Order corners: top-left, top-right, bottom-right, bottom-left
      final orderedCorners = _orderCorners(cardCorners);

      // Define destination points for rectangular output
      final dstPoints = [
        math.Point(0.0, 0.0), // top-left
        math.Point((outputWidth - 1).toDouble(), 0.0), // top-right
        math.Point((outputWidth - 1).toDouble(), (outputHeight - 1).toDouble()), // bottom-right
        math.Point(0.0, (outputHeight - 1).toDouble()), // bottom-left
      ];

      // Convert source corners to double points
      final srcPointsDouble = orderedCorners.map((p) => math.Point(p.x.toDouble(), p.y.toDouble())).toList();

      // Calculate perspective transform matrix
      final transformMatrix = _calculatePerspectiveTransform(
        srcPointsDouble,
        dstPoints,
      );

      // Apply perspective transformation
      final warped = _applyPerspectiveTransform(
        image,
        transformMatrix,
        outputWidth,
        outputHeight,
      );

      // Encode to JPEG
      return Uint8List.fromList(img.encodeJpg(warped, quality: 95));
    } catch (e) {
      // Error handled silently
      return null;
    }
  }

  /// Order corners: top-left, top-right, bottom-right, bottom-left
  List<math.Point<int>> _orderCorners(List<math.Point<int>> corners) {
    // Calculate sum and difference
    final sums = corners.map((p) => p.x + p.y).toList();
    final diffs = corners.map((p) => p.x - p.y).toList();

    final topLeft = corners[sums.indexOf(sums.reduce(math.min))];
    final bottomRight = corners[sums.indexOf(sums.reduce(math.max))];
    final topRight = corners[diffs.indexOf(diffs.reduce(math.min))];
    final bottomLeft = corners[diffs.indexOf(diffs.reduce(math.max))];

    return [topLeft, topRight, bottomRight, bottomLeft];
  }

  /// Calculate perspective transform matrix using 4 point pairs
  /// Returns: 3x3 transformation matrix
  List<List<double>> _calculatePerspectiveTransform(
    List<math.Point<double>> srcPoints,
    List<math.Point<double>> dstPoints,
  ) {
    // Build system of equations: Ax = b
    // Using direct linear transformation (DLT) algorithm
    
    final A = List.generate(8, (_) => List.filled(8, 0.0));
    final b = List.filled(8, 0.0);

    for (var i = 0; i < 4; i++) {
      final srcX = srcPoints[i].x.toDouble();
      final srcY = srcPoints[i].y.toDouble();
      final dstX = dstPoints[i].x;
      final dstY = dstPoints[i].y;

      // Two equations per point
      final row1 = i * 2;
      final row2 = i * 2 + 1;

      A[row1] = [srcX, srcY, 1, 0, 0, 0, -dstX * srcX, -dstX * srcY];
      b[row1] = dstX;

      A[row2] = [0, 0, 0, srcX, srcY, 1, -dstY * srcX, -dstY * srcY];
      b[row2] = dstY;
    }

    // Solve system using Gaussian elimination
    final x = _solveLinearSystem(A, b);

    // Build transformation matrix
    return [
      [x[0], x[1], x[2]],
      [x[3], x[4], x[5]],
      [x[6], x[7], 1.0],
    ];
  }

  /// Solve linear system Ax = b using Gaussian elimination
  List<double> _solveLinearSystem(List<List<double>> A, List<double> b) {
    final n = A.length;
    final augmented = List.generate(n, (i) => [...A[i], b[i]]);

    // Forward elimination
    for (var i = 0; i < n; i++) {
      // Find pivot
      var maxRow = i;
      for (var k = i + 1; k < n; k++) {
        if (augmented[k][i].abs() > augmented[maxRow][i].abs()) {
          maxRow = k;
        }
      }

      // Swap rows
      final temp = augmented[i];
      augmented[i] = augmented[maxRow];
      augmented[maxRow] = temp;

      // Make all rows below this one zero in current column
      for (var k = i + 1; k < n; k++) {
        final factor = augmented[k][i] / augmented[i][i];
        for (var j = i; j < n + 1; j++) {
          augmented[k][j] -= factor * augmented[i][j];
        }
      }
    }

    // Back substitution
    final x = List.filled(n, 0.0);
    for (var i = n - 1; i >= 0; i--) {
      x[i] = augmented[i][n];
      for (var j = i + 1; j < n; j++) {
        x[i] -= augmented[i][j] * x[j];
      }
      x[i] /= augmented[i][i];
    }

    return x;
  }

  /// Apply perspective transformation to image
  img.Image _applyPerspectiveTransform(
    img.Image image,
    List<List<double>> transformMatrix,
    int outputWidth,
    int outputHeight,
  ) {
    final output = img.Image(width: outputWidth, height: outputHeight);

    // Inverse transform: map destination pixels to source
    final invMatrix = _inverseMatrix(transformMatrix);

    for (var y = 0; y < outputHeight; y++) {
      for (var x = 0; x < outputWidth; x++) {
        // Transform destination point to source
        final srcX = invMatrix[0][0] * x +
            invMatrix[0][1] * y +
            invMatrix[0][2];
        final srcY = invMatrix[1][0] * x +
            invMatrix[1][1] * y +
            invMatrix[1][2];
        final w = invMatrix[2][0] * x +
            invMatrix[2][1] * y +
            invMatrix[2][2];

        if (w.abs() < 1e-6) continue;

        final srcXNorm = srcX / w;
        final srcYNorm = srcY / w;

        // Bilinear interpolation
        final pixel = _bilinearInterpolate(image, srcXNorm, srcYNorm);
        output.setPixel(x, y, pixel);
      }
    }

    return output;
  }

  /// Calculate inverse of 3x3 matrix
  List<List<double>> _inverseMatrix(List<List<double>> matrix) {
    final det = matrix[0][0] *
            (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) -
        matrix[0][1] *
            (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0]) +
        matrix[0][2] *
            (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]);

    if (det.abs() < 1e-6) {
      // Return identity if singular
      return [
        [1.0, 0.0, 0.0],
        [0.0, 1.0, 0.0],
        [0.0, 0.0, 1.0],
      ];
    }

    final invDet = 1.0 / det;

    return [
      [
        (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1]) * invDet,
        (matrix[0][2] * matrix[2][1] - matrix[0][1] * matrix[2][2]) * invDet,
        (matrix[0][1] * matrix[1][2] - matrix[0][2] * matrix[1][1]) * invDet,
      ],
      [
        (matrix[1][2] * matrix[2][0] - matrix[1][0] * matrix[2][2]) * invDet,
        (matrix[0][0] * matrix[2][2] - matrix[0][2] * matrix[2][0]) * invDet,
        (matrix[0][2] * matrix[1][0] - matrix[0][0] * matrix[1][2]) * invDet,
      ],
      [
        (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]) * invDet,
        (matrix[0][1] * matrix[2][0] - matrix[0][0] * matrix[2][1]) * invDet,
        (matrix[0][0] * matrix[1][1] - matrix[0][1] * matrix[1][0]) * invDet,
      ],
    ];
  }

  /// Bilinear interpolation
  img.Color _bilinearInterpolate(img.Image image, double x, double y) {
    final x1 = x.floor();
    final y1 = y.floor();
    final x2 = x1 + 1;
    final y2 = y1 + 1;

    // Check bounds
    if (x1 < 0 || y1 < 0 || x2 >= image.width || y2 >= image.height) {
      return img.ColorRgb8(0, 0, 0);
    }

    final dx = x - x1;
    final dy = y - y1;

    final p11 = image.getPixel(x1, y1);
    final p21 = image.getPixel(x2, y1);
    final p12 = image.getPixel(x1, y2);
    final p22 = image.getPixel(x2, y2);

    // Interpolate
    final r = ((p11.r * (1 - dx) + p21.r * dx) * (1 - dy) +
            (p12.r * (1 - dx) + p22.r * dx) * dy)
        .round()
        .clamp(0, 255);
    final g = ((p11.g * (1 - dx) + p21.g * dx) * (1 - dy) +
            (p12.g * (1 - dx) + p22.g * dx) * dy)
        .round()
        .clamp(0, 255);
    final b = ((p11.b * (1 - dx) + p21.b * dx) * (1 - dy) +
            (p12.b * (1 - dx) + p22.b * dx) * dy)
        .round()
        .clamp(0, 255);

    return img.ColorRgb8(r, g, b);
  }
}

