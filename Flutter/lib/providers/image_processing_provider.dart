import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/scan_guidance.dart';
import '../models/scan_result.dart';
import '../services/image_processing/image_processing_service.dart';

/// Provider for managing local image processing and scan state
class ImageProcessingProvider with ChangeNotifier {
  final ImageProcessingService _imageProcessingService;

  // Processing state
  bool _isProcessing = false;
  String? _processingError;
  DateTime? _lastProcessTime;

  // Guidance state
  ScanGuidance? _currentGuidance;

  // Capture state
  ScanResult? _lastResult;
  bool _isCapturing = false;

  ImageProcessingProvider({
    ImageProcessingService? imageProcessingService,
  }) : _imageProcessingService =
            imageProcessingService ?? ImageProcessingService();

  // Getters
  bool get isConnected => true; // Always "connected" since it's local
  String? get connectionError => _processingError;
  ScanGuidance? get currentGuidance => _currentGuidance;
  ScanResult? get lastResult => _lastResult;
  bool get isCapturing => _isCapturing;
  bool get isProcessing => _isProcessing;

  /// Initialize (no-op for local processing, but kept for API compatibility)
  Future<bool> initialize() async {
    _processingError = null;
    notifyListeners();
    return true;
  }

  /// Disconnect (no-op for local processing, but kept for API compatibility)
  void disconnect() {
    _currentGuidance = null;
    _lastResult = null;
    _processingError = null;
    notifyListeners();
  }

  /// Send frame for processing (non-blocking)
  Future<void> sendFrame(Uint8List imageBytes, {String mode = 'auto'}) async {
    // Skip if already processing or processing too frequently
    if (_isProcessing) {
      return; // Skip if already processing
    }

    // Rate limiting - don't process if last processing was too recent
    final now = DateTime.now();
    if (_lastProcessTime != null) {
      final timeSinceLastProcess = now.difference(_lastProcessTime!);
      if (timeSinceLastProcess.inMilliseconds < 500) {
        return; // Skip if processing too frequently (max 2 FPS)
      }
    }

    _isProcessing = true;
    _processingError = null;
    _lastProcessTime = now;

    // Process asynchronously without blocking UI
    // Use scheduleMicrotask to yield control to UI
    Future(() async {
      try {
        final guidance = await _imageProcessingService.processFrame(
          imageBytes,
          mode: mode,
        );

        if (!_isProcessing) return; // Cancelled

        _currentGuidance = guidance;
        _isProcessing = false;

        // Check for auto-capture
        if (mode == 'auto' &&
            guidance.readyToCapture &&
            _imageProcessingService.shouldAutoCapture()) {
          // Trigger auto-capture in background
          _imageProcessingService.captureCard(imageBytes).then((result) {
            _lastResult = result;
            _imageProcessingService.resetAutoCapture();
            notifyListeners();
          });
        }

        notifyListeners();
      } catch (e) {
        _processingError = null; // Don't show errors to user
        _isProcessing = false;
        notifyListeners();
      }
    });
  }

  /// Send manual capture request
  Future<void> requestCapture(Uint8List imageBytes) async {
    if (_isCapturing) {
      return; // Already capturing
    }

    _isCapturing = true;
    _processingError = null;
    notifyListeners();

    try {
      final result = await _imageProcessingService.captureCard(imageBytes);
      _lastResult = result;
      _isCapturing = false;
      notifyListeners();
    } catch (e) {
      _processingError = 'Capture error: $e';
      _isCapturing = false;
      print('ImageProcessingProvider: Error capturing: $e');
      notifyListeners();
    }
  }

  /// Reset capture state
  void resetCapture() {
    _lastResult = null;
    _isCapturing = false;
    notifyListeners();
  }

  /// Reset tracking state
  void resetTracking() {
    _imageProcessingService.resetTracking();
    _currentGuidance = null;
    _lastResult = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

