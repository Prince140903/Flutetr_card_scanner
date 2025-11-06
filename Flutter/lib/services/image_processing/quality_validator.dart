import 'dart:typed_data';
import 'dart:math' as math;
import 'card_detector.dart';
import 'blur_detector.dart';
import 'glare_detector.dart';
import 'distance_guide.dart';
import 'centering_guide.dart';

/// Quality Validator Module
/// Validates that captured image meets all quality requirements.
class QualityValidator {
  final CardDetector cardDetector;
  final BlurDetector blurDetector;
  final GlareDetector glareDetector;
  final DistanceGuide distanceGuide;
  final CenteringGuide centeringGuide;

  QualityValidator({
    CardDetector? cardDetector,
    BlurDetector? blurDetector,
    GlareDetector? glareDetector,
    DistanceGuide? distanceGuide,
    CenteringGuide? centeringGuide,
  })  : cardDetector = cardDetector ?? CardDetector(),
        blurDetector = blurDetector ?? BlurDetector(),
        glareDetector = glareDetector ?? GlareDetector(),
        distanceGuide = distanceGuide ?? DistanceGuide(),
        centeringGuide = centeringGuide ?? CenteringGuide();

  /// Validate that frame meets all quality requirements
  Future<({
    bool isValid,
    bool cardDetected,
    bool isSharp,
    bool glareAcceptable,
    bool distanceOptimal,
    bool isCentered,
    List<String> messages,
    List<math.Point<int>>? cardCorners,
  })> validate(Uint8List imageBytes) async {
    try {
      // Check if card is detected
      final detection = await cardDetector.detectCard(imageBytes);

      if (!detection.found || detection.corners == null) {
        return (
          isValid: false,
          cardDetected: false,
          isSharp: false,
          glareAcceptable: false,
          distanceOptimal: false,
          isCentered: false,
          messages: ['Card not detected'],
          cardCorners: null,
        );
      }

      final corners = detection.corners!;

      // Check blur
      final blurResult = await blurDetector.detectBlur(imageBytes, cardCorners: corners);
      final isSharp = !blurResult.isBlurry;
      var messages = blurResult.isBlurry
          ? ['Image is blurry (variance: ${blurResult.variance.toStringAsFixed(1)})']
          : <String>[];

      // Check glare
      final glareResult = await glareDetector.detectGlare(imageBytes, corners);
      messages = glareResult.isAcceptable
          ? messages
          : [...messages, glareResult.message];

      // Check distance
      final distanceResult = distanceGuide.analyzeDistance(imageBytes, corners);
      messages = distanceResult.isOptimal
          ? messages
          : [...messages, distanceResult.message];

      // Check centering (less critical, but good to have)
      final centeringResult = centeringGuide.analyzeCentering(imageBytes, corners);

      // Determine overall validity
      final isValid = detection.found &&
          isSharp &&
          glareResult.isAcceptable &&
          distanceResult.isOptimal;

      if (isValid) {
        messages = [...messages, 'Quality check passed'];
      }

      return (
        isValid: isValid,
        cardDetected: detection.found,
        isSharp: isSharp,
        glareAcceptable: glareResult.isAcceptable,
        distanceOptimal: distanceResult.isOptimal,
        isCentered: centeringResult.isCentered,
        messages: messages,
        cardCorners: corners,
      );
    } catch (e) {
      // Error handled silently
      return (
        isValid: false,
        cardDetected: false,
        isSharp: false,
        glareAcceptable: false,
        distanceOptimal: false,
        isCentered: false,
        messages: ['Error validating quality: $e'],
        cardCorners: null,
      );
    }
  }

  /// Quick check if frame is valid (convenience method)
  Future<bool> isValid(Uint8List imageBytes) async {
    final result = await validate(imageBytes);
    return result.isValid;
  }
}

