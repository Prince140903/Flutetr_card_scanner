import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/scan_guidance.dart';
import '../models/scan_result.dart';

/// WebSocket service for communicating with the Python backend
///
/// Configuration:
/// - Android Emulator: ws://10.0.2.2:8000/ws
/// - iOS Simulator: ws://localhost:8000/ws
/// - Physical Device: ws://<YOUR_COMPUTER_IP>:8000/ws
///
/// To find your computer's IP address:
///   Windows: ipconfig (look for IPv4 Address)
///   Mac/Linux: ifconfig or ip addr
///
/// IMPORTANT: Make sure your Python backend is running with:
///   python main.py  (runs on 0.0.0.0:8000, accessible from network)
///
/// For physical devices, update the IP below to your computer's local IP
class WebSocketService {
  // TODO: Update this IP address for physical device testing
  // For Android Emulator, use: ws://10.0.2.2:8000/ws
  // For Physical Device, use: ws://YOUR_COMPUTER_IP:8000/ws
  // Example: ws://192.168.0.109:8000/ws
  static const String _defaultUrl =
      'ws://192.168.0.109:8000/ws'; // Physical device - UPDATE THIS IP!

  WebSocketChannel? _channel;
  String _url;
  bool _isConnected = false;
  StreamSubscription<dynamic>? _connectionSubscription;
  Completer<bool>? _connectionCompleter;

  WebSocketService({String? url}) : _url = url ?? _defaultUrl;

  /// Connect to the WebSocket server
  Future<bool> connect({Duration timeout = const Duration(seconds: 5)}) async {
    // If already connected, return true
    if (_isConnected && _channel != null) {
      print('WebSocket already connected');
      return true;
    }

    // Clean up any existing connection
    disconnect();

    try {
      // Create WebSocket channel - this will attempt connection
      _channel = WebSocketChannel.connect(Uri.parse(_url));

      // Wait a short time to allow connection to establish or fail
      await Future.delayed(const Duration(milliseconds: 1000));

      // Check if channel is still valid (basic connection check)
      // The actual error handling will be done by the stream listener
      _isConnected = true;

      return true;
    } catch (e) {
      print('WebSocket connection exception: $e');
      _isConnected = false;
      disconnect();
      print('Make sure the Python backend is running at $_url');
      return false;
    }
  }

  /// Disconnect from the WebSocket server
  void disconnect() {
    _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    if (_connectionCompleter != null && !_connectionCompleter!.isCompleted) {
      _connectionCompleter!.complete(false);
    }
    _connectionCompleter = null;
  }

  /// Check if connected
  bool get isConnected => _isConnected && _channel != null;

  /// Send a frame for processing
  void sendFrame(Uint8List imageBytes, {String mode = 'auto'}) {
    if (!isConnected) {
      return;
    }

    try {
      // Convert image bytes to base64
      final base64Image = base64Encode(imageBytes);
      final imageSizeKB = (imageBytes.length / 1024).toStringAsFixed(1);

      // Create JSON message
      final message = jsonEncode({
        'type': 'frame',
        'image': base64Image,
        'mode': mode,
      });

      _channel?.sink.add(message);
    } catch (e) {
      print('WebSocketService: Error sending frame: $e');
      // Connection might be lost
      if (e.toString().contains('closed') || e.toString().contains('error')) {
        _isConnected = false;
      }
    }
  }

  /// Send a manual capture request
  void sendCaptureRequest(Uint8List imageBytes) {
    if (!isConnected) {
      print('WebSocket not connected - cannot send capture request');
      return;
    }

    try {
      // Convert image bytes to base64
      final base64Image = base64Encode(imageBytes);

      // Create JSON message
      final message = jsonEncode({
        'type': 'capture',
        'image': base64Image,
      });

      _channel?.sink.add(message);
    } catch (e) {
      print('Error sending capture request: $e');
      // Connection might be lost
      if (e.toString().contains('closed') || e.toString().contains('error')) {
        _isConnected = false;
      }
    }
  }

  /// Listen to incoming messages
  Stream<dynamic> get messageStream {
    if (_channel == null) {
      return const Stream.empty();
    }
    return _channel!.stream.map((dynamic message) {
      try {
        if (message is String) {
          return jsonDecode(message);
        }
        return message;
      } catch (e) {
        print('Error parsing message: $e');
        return null;
      }
    }).where((message) => message != null);
  }

  /// Parse guidance response
  ScanGuidance? parseGuidance(Map<String, dynamic> data) {
    if (data['type'] == 'guidance') {
      try {
        return ScanGuidance.fromJson(data);
      } catch (e) {
        print('Error parsing guidance: $e');
        return null;
      }
    }
    return null;
  }

  /// Parse capture response
  ScanResult? parseCapture(Map<String, dynamic> data,
      {Uint8List? originalImage}) {
    if (data['type'] == 'capture') {
      try {
        return ScanResult.fromJson(data, originalImage: originalImage);
      } catch (e) {
        print('Error parsing capture: $e');
        return null;
      }
    }
    return null;
  }

  /// Check if message is an error
  bool isError(Map<String, dynamic> data) {
    return data['type'] == 'error';
  }

  /// Get error message
  String? getErrorMessage(Map<String, dynamic> data) {
    if (isError(data)) {
      return data['message'] as String?;
    }
    return null;
  }
}
