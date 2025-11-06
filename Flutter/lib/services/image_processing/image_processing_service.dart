import 'dart:typed_data';
import 'dart:math' as math;
import '../../models/scan_guidance.dart';
import '../../models/scan_result.dart';
import 'card_detector.dart';
import 'simple_card_detector.dart';
import 'blur_detector.dart';
import 'glare_detector.dart';
import 'distance_guide.dart';
import 'centering_guide.dart';
import 'warp_transformer.dart';
import 'quality_validator.dart';
import 'package:image/image.dart' as img;

/// Image Processing Service
/// Main service that replaces WebSocket service for local image processing.
class ImageProcessingService {
  final CardDetector cardDetector;
  final SimpleCardDetector simpleCardDetector;
  final BlurDetector blurDetector;
  final GlareDetector glareDetector;
  final DistanceGuide distanceGuide;
  final CenteringGuide centeringGuide;
  final WarpTransformer warpTransformer;
  final QualityValidator qualityValidator;

  // Auto-capture state
  int _goodFramesCount = 0;
  static const int autoCaptureThreshold = 30; // Number of consecutive good frames for auto-capture

  // Tracking state for stability
  List<math.Point<int>>? _lastDetectedCorners;
  final List<bool> _detectionHistory = [];
  static const int historySize = 5;
  static const int detectionThreshold = 3;

  ImageProcessingService({
    CardDetector? cardDetector,
    BlurDetector? blurDetector,
    GlareDetector? glareDetector,
    DistanceGuide? distanceGuide,
    CenteringGuide? centeringGuide,
    WarpTransformer? warpTransformer,
    QualityValidator? qualityValidator,
  })  : cardDetector = cardDetector ?? CardDetector(),
        simpleCardDetector = SimpleCardDetector(),
        blurDetector = blurDetector ?? BlurDetector(),
        glareDetector = glareDetector ?? GlareDetector(),
        distanceGuide = distanceGuide ?? DistanceGuide(),
        centeringGuide = centeringGuide ?? CenteringGuide(),
        warpTransformer = warpTransformer ?? WarpTransformer(),
        qualityValidator = qualityValidator ??
            QualityValidator(
              cardDetector: cardDetector ?? CardDetector(),
              blurDetector: blurDetector ?? BlurDetector(),
              glareDetector: glareDetector ?? GlareDetector(),
              distanceGuide: distanceGuide ?? DistanceGuide(),
              centeringGuide: centeringGuide ?? CenteringGuide(),
            );

  /// Process a frame and return guidance
  Future<ScanGuidance> processFrame(
    Uint8List imageBytes, {
    String mode = 'auto',
  }) async {
    try {
      // Detect card using simplified detector
      final detection = await simpleCardDetector.detectCard(imageBytes);

      // Update detection history for stability
      _detectionHistory.add(detection.found);
      if (_detectionHistory.length > historySize) {
        _detectionHistory.removeAt(0);
      }

      // Use hysteresis: need multiple detections to confirm
      final recentDetections = _detectionHistory.where((d) => d).length;
      final stableDetection = recentDetections >= detectionThreshold;

      // If we had a detection recently but current frame doesn't detect, use last known corners
      List<math.Point<int>>? cardCorners;
      if (!detection.found && _lastDetectedCorners != null && recentDetections > 0) {
        // Use last known corners for stability (temporal tracking)
        cardCorners = _lastDetectedCorners;
      } else if (detection.found && detection.corners != null) {
        // Update last known good corners
        cardCorners = detection.corners;
        _lastDetectedCorners = List<math.Point<int>>.from(cardCorners!);
      }

      if (!stableDetection && !detection.found) {
        resetAutoCapture();
        // Clear history if no detection for a while
        if (recentDetections == 0) {
          _lastDetectedCorners = null;
          // Reset size tracking if no detection for several frames
          if (_detectionHistory.length == 0 ||
              _detectionHistory.sublist(math.max(0, _detectionHistory.length - 3))
                  .where((d) => d)
                  .isEmpty) {
            simpleCardDetector.resetSizeTracking();
          }
        }
        return ScanGuidance(
          cardDetected: false,
          message: 'Place document in frame',
          distance: 'unknown',
          centering: 'unknown',
          blur: 'unknown',
          glare: 'unknown',
          readyToCapture: false,
          cardCorners: null,
        );
      }

      if (cardCorners == null || cardCorners.length != 4) {
        return ScanGuidance(
          cardDetected: false,
          message: 'Place document in frame',
          distance: 'unknown',
          centering: 'unknown',
          blur: 'unknown',
          glare: 'unknown',
          readyToCapture: false,
          cardCorners: null,
        );
      }

      // Decode image once and reuse
      final image = img.decodeImage(imageBytes);
      if (image == null) {
        return ScanGuidance(
          cardDetected: false,
          message: 'Place document in frame',
          distance: 'unknown',
          centering: 'unknown',
          blur: 'unknown',
          glare: 'unknown',
          readyToCapture: false,
          cardCorners: null,
        );
      }

      // Analyze distance (lightweight, geometric only)
      final distanceResult = distanceGuide.analyzeDistance(imageBytes, cardCorners);

      // Analyze centering (lightweight, geometric only)
      final centeringResult = centeringGuide.analyzeCentering(imageBytes, cardCorners);

      // Skip heavy blur/glare detection for guidance frames - only show basic status
      // These are too expensive to run every frame (O(width*height) operations)
      String primaryMessage;
      if (distanceResult.status != 'optimal') {
        primaryMessage = distanceResult.message;
      } else if (!centeringResult.isCentered) {
        primaryMessage = centeringResult.message;
      } else {
        primaryMessage = 'Hold still...';
      }

      // Check if ready for capture
      final cardHasGoodEdges = stableDetection &&
          detection.found &&
          cardCorners.length == 4;

      // Ready to capture if card detected with good edges
      final readyToCapture = cardHasGoodEdges;

      // Update auto-capture counter (simplified - don't run full quality check every frame)
      // Only increment if card is detected and centered
      if (mode == 'auto' && stableDetection && distanceResult.status == 'optimal' && centeringResult.isCentered) {
        _goodFramesCount++;
      } else {
        _goodFramesCount = math.max(0, _goodFramesCount - 1);
      }

      // Convert card corners to list for JSON serialization
      final cardCornersList = <List<double>>[
        for (final c in cardCorners) [c.x.toDouble(), c.y.toDouble()],
      ];

      return ScanGuidance(
        cardDetected: stableDetection,
        message: primaryMessage,
        distance: distanceResult.status,
        centering: centeringResult.status,
        blur: 'unknown', // Skip blur check for guidance frames (too expensive)
        glare: 'unknown', // Skip glare check for guidance frames (too expensive)
        readyToCapture: readyToCapture,
        cardCorners: cardCornersList,
      );
    } catch (e) {
      // Error handled silently
      return ScanGuidance(
        cardDetected: false,
        message: 'Processing error',
        distance: 'unknown',
        centering: 'unknown',
        blur: 'unknown',
        glare: 'unknown',
        readyToCapture: false,
        cardCorners: null,
      );
    }
  }

  /// Capture and process card from frame
  Future<ScanResult> captureCard(Uint8List imageBytes) async {
    try {
      // Detect card using simplified detector
      final detection = await simpleCardDetector.detectCard(imageBytes);

      if (!detection.found || detection.corners == null || detection.corners!.length != 4) {
        return ScanResult(
          success: false,
          message: 'Card not detected in frame',
          warpedImage: null,
          originalImage: imageBytes,
        );
      }

      // For capture, run quality check (blur) since this is one-time operation
      final blurCheck = await blurDetector.detectBlur(imageBytes, cardCorners: detection.corners);
      if (blurCheck.isBlurry) {
        return ScanResult(
          success: false,
          message: 'Image is too blurry. Please try again.',
          warpedImage: null,
          originalImage: imageBytes,
        );
      }

      // Warp/crop the card
      final warped = await warpTransformer.warpCard(imageBytes, detection.corners!);

      if (warped == null) {
        return ScanResult(
          success: false,
          message: 'Failed to warp card image',
          warpedImage: null,
          originalImage: imageBytes,
        );
      }

      return ScanResult(
        success: true,
        message: 'Card captured successfully',
        warpedImage: warped,
        originalImage: imageBytes,
      );
    } catch (e) {
      return ScanResult(
        success: false,
        message: 'Error processing card: $e',
        warpedImage: null,
        originalImage: imageBytes,
      );
    }
  }

  /// Check if auto-capture should trigger
  bool shouldAutoCapture() {
    return _goodFramesCount >= autoCaptureThreshold;
  }

  /// Reset auto-capture counter
  void resetAutoCapture() {
    _goodFramesCount = 0;
  }

  /// Reset all tracking state
  void resetTracking() {
    _lastDetectedCorners = null;
    _detectionHistory.clear();
    resetAutoCapture();
    simpleCardDetector.resetSizeTracking();
  }
}

