/// Model representing real-time guidance from the backend
class ScanGuidance {
  final bool cardDetected;
  final String message;
  final String distance;
  final String centering;
  final String blur;
  final String glare;
  final bool readyToCapture;
  final List<List<double>>? cardCorners;

  ScanGuidance({
    required this.cardDetected,
    required this.message,
    required this.distance,
    required this.centering,
    required this.blur,
    required this.glare,
    required this.readyToCapture,
    this.cardCorners,
  });

  factory ScanGuidance.fromJson(Map<String, dynamic> json) {
    return ScanGuidance(
      cardDetected: json['card_detected'] ?? false,
      message: json['message'] ?? '',
      distance: json['distance'] ?? 'unknown',
      centering: json['centering'] ?? 'unknown',
      blur: json['blur'] ?? 'unknown',
      glare: json['glare'] ?? 'unknown',
      readyToCapture: json['ready_to_capture'] ?? false,
      cardCorners: json['card_corners'] != null
          ? (json['card_corners'] as List)
              .map((e) => (e as List).map((x) => (x as num).toDouble()).toList())
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'card_detected': cardDetected,
      'message': message,
      'distance': distance,
      'centering': centering,
      'blur': blur,
      'glare': glare,
      'ready_to_capture': readyToCapture,
      'card_corners': cardCorners,
    };
  }
}
