import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// Widget that draws an outline around the detected card corners
class CardOutline extends CustomPainter {
  final List<List<double>>? corners;
  final Size videoSize;
  final Size displaySize;
  final bool isReady;

  CardOutline({
    required this.corners,
    required this.videoSize,
    required this.displaySize,
    this.isReady = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners == null || corners!.isEmpty) return;

    // Calculate scale factors
    final scaleX = displaySize.width / videoSize.width;
    final scaleY = displaySize.height / videoSize.height;

    // Create path from corners
    final path = Path();
    final points = corners!.map((corner) {
      return Offset(
        corner[0] * scaleX,
        corner[1] * scaleY,
      );
    }).toList();

    if (points.length < 4) return;

    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();

    // Choose color based on readiness
    final color = isReady ? Colors.green : Colors.yellow;

    // Draw border
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0; // Increased from 3.0 for better visibility

    canvas.drawPath(path, paint);

    // Draw corner markers
    final cornerPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 15, cornerPaint); // Increased from 8 to 15
    }
  }

  @override
  bool shouldRepaint(CardOutline oldDelegate) {
    return corners != oldDelegate.corners ||
        isReady != oldDelegate.isReady ||
        displaySize != oldDelegate.displaySize ||
        videoSize != oldDelegate.videoSize;
  }
}
