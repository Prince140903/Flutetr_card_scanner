import 'package:flutter/material.dart';
import '../models/scan_guidance.dart';

/// Overlay widget displaying real-time guidance and status indicators
class GuidanceOverlay extends StatelessWidget {
  final ScanGuidance? guidance;
  final Size videoSize;

  const GuidanceOverlay({
    Key? key,
    required this.guidance,
    required this.videoSize,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (guidance == null || !guidance!.cardDetected) {
      return _buildNoCardMessage();
    }

    return Stack(
      children: [
        // Main guidance message
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: _buildMainMessage(context),
        ),
        
        // Status indicators
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: _buildStatusIndicators(context),
        ),
        
        // Ready indicator
        if (guidance!.readyToCapture)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: _buildReadyIndicator(context),
          ),
      ],
    );
  }

  Widget _buildNoCardMessage() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'Place document in frame',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMainMessage(BuildContext context) {
    final message = guidance?.message ?? '';
    final isGood = guidance?.readyToCapture ?? false;
    
    Color backgroundColor;
    if (isGood) {
      backgroundColor = Colors.green.withOpacity(0.8);
    } else if (message.toLowerCase().contains('blur') || 
               message.toLowerCase().contains('glare') ||
               message.toLowerCase().contains('reflection')) {
      backgroundColor = Colors.red.withOpacity(0.8);
    } else {
      backgroundColor = Colors.orange.withOpacity(0.8);
    }

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildStatusIndicators(BuildContext context) {
    if (guidance == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusRow('Distance', guidance!.distance, _getDistanceColor()),
          const SizedBox(height: 8),
          _buildStatusRow('Centering', guidance!.centering, _getCenteringColor()),
          const SizedBox(height: 8),
          _buildStatusRow('Blur', guidance!.blur, _getBlurColor()),
          const SizedBox(height: 8),
          _buildStatusRow('Glare', guidance!.glare, _getGlareColor()),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadyIndicator(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.white,
              size: 24,
            ),
            SizedBox(width: 8),
            Text(
              'Ready to Capture!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getDistanceColor() {
    switch (guidance?.distance) {
      case 'optimal':
        return Colors.green;
      case 'too_far':
      case 'too_close':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getCenteringColor() {
    switch (guidance?.centering) {
      case 'centered':
        return Colors.green;
      case 'off_center':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Color _getBlurColor() {
    switch (guidance?.blur) {
      case 'sharp':
        return Colors.green;
      case 'blurry':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getGlareColor() {
    switch (guidance?.glare) {
      case 'acceptable':
        return Colors.green;
      case 'excessive':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
