import 'dart:typed_data';
import 'dart:convert';

/// Model representing a captured and processed card image
class ScanResult {
  final bool success;
  final String message;
  Uint8List? warpedImage;
  final Uint8List? originalImage;

  ScanResult({
    required this.success,
    required this.message,
    this.warpedImage,
    this.originalImage,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json, {Uint8List? originalImage}) {
    Uint8List? warpedImageBytes;
    
    if (json['warped_image'] != null) {
      try {
        // Decode base64 string to bytes
        final base64String = json['warped_image'] as String;
        // Remove data URL prefix if present
        String base64Data = base64String;
        if (base64String.contains(',')) {
          base64Data = base64String.split(',')[1];
        }
        warpedImageBytes = base64Decode(base64Data);
      } catch (e) {
        print('Error decoding warped image: $e');
      }
    }

    return ScanResult(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      warpedImage: warpedImageBytes,
      originalImage: originalImage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
    };
  }
}
