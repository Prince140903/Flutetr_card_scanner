import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/scan_guidance.dart';
import '../models/scan_result.dart';
import '../services/websocket_service.dart';

/// Provider for managing WebSocket connection and scan state
class WebSocketProvider with ChangeNotifier {
  final WebSocketService _webSocketService;

  StreamSubscription<dynamic>? _messageSubscription;

  // Connection state
  bool _isConnected = false;
  String? _connectionError;

  // Guidance state
  ScanGuidance? _currentGuidance;

  // Capture state
  ScanResult? _lastResult;
  bool _isCapturing = false;

  WebSocketProvider({WebSocketService? webSocketService})
      : _webSocketService = webSocketService ?? WebSocketService();

  // Getters
  bool get isConnected => _isConnected;
  String? get connectionError => _connectionError;
  ScanGuidance? get currentGuidance => _currentGuidance;
  ScanResult? get lastResult => _lastResult;
  bool get isCapturing => _isCapturing;

  /// Initialize and connect to WebSocket
  Future<bool> initialize() async {
    try {
      final connected = await _webSocketService.connect();
      if (connected) {
        _isConnected = true;
        _connectionError = null;

        // Listen to incoming messages
        _messageSubscription = _webSocketService.messageStream.listen(
          _handleMessage,
          onError: _handleError,
          onDone: _handleDisconnect,
          cancelOnError: false,
        );

        notifyListeners();
        return true;
      } else {
        _connectionError = 'Failed to connect to server';
        print('WebSocketProvider: Connection failed');
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionError = 'Connection error: $e';
      print('WebSocketProvider: Connection exception: $e');
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from WebSocket
  void disconnect() {
    _messageSubscription?.cancel();
    _webSocketService.disconnect();
    _isConnected = false;
    _currentGuidance = null;
    _lastResult = null;
    notifyListeners();
  }

  /// Send frame for processing
  void sendFrame(Uint8List imageBytes, {String mode = 'auto'}) {
    if (_isConnected) {
      _webSocketService.sendFrame(imageBytes, mode: mode);
    }
  }

  /// Send manual capture request
  void requestCapture(Uint8List imageBytes) {
    if (_isConnected && !_isCapturing) {
      _isCapturing = true;
      notifyListeners();

      // Store original image for later use
      _originalImageForCapture = imageBytes;

      _webSocketService.sendCaptureRequest(imageBytes);
    }
  }

  Uint8List? _originalImageForCapture;

  /// Handle incoming message
  void _handleMessage(dynamic message) {
    if (message is! Map<String, dynamic>) {
      return;
    }

    // Check for errors
    if (_webSocketService.isError(message)) {
      final errorMsg = _webSocketService.getErrorMessage(message);
      print('WebSocketProvider: Error: $errorMsg');
      _connectionError = errorMsg ?? 'Unknown error';
      _isCapturing = false;
      notifyListeners();
      return;
    }

    // Parse guidance response
    final guidance = _webSocketService.parseGuidance(message);
    if (guidance != null) {
      _currentGuidance = guidance;
      notifyListeners();
      return;
    }

    // Parse capture response (can be from manual or auto-capture)
    final result = _webSocketService.parseCapture(
      message,
      originalImage: _originalImageForCapture,
    );
    if (result != null) {
      print('WebSocketProvider: Capture result received - success: ${result.success}, type: ${_isCapturing ? "manual" : "auto"}');
      _lastResult = result;
      _isCapturing = false;
      _originalImageForCapture = null;
      // Notify listeners so camera screen can check for auto-capture result
      notifyListeners();
      return;
    }
  }

  /// Handle WebSocket error
  void _handleError(dynamic error) {
    _connectionError = 'WebSocket error: $error';
    _isConnected = false;
    _isCapturing = false;
    notifyListeners();
  }

  /// Handle WebSocket disconnect
  void _handleDisconnect() {
    _isConnected = false;
    _connectionError = 'Disconnected from server';
    _isCapturing = false;
    notifyListeners();
  }

  /// Reset capture state
  void resetCapture() {
    _lastResult = null;
    _isCapturing = false;
    _originalImageForCapture = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
