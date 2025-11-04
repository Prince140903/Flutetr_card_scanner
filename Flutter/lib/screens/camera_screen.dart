import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../models/scan_guidance.dart';
import '../models/scan_result.dart';
import '../providers/websocket_provider.dart';
import '../widgets/guidance_overlay.dart';
import '../widgets/card_outline.dart';
import 'result_screen.dart';

/// Camera screen for scanning ID cards with real-time guidance
class CameraScreen extends StatefulWidget {
  const CameraScreen({Key? key}) : super(key: key);

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _hasPermission = false;
  Timer? _frameTimer;
  Size? _cameraSize;
  bool _isCapturingFrame = false; // Prevent overlapping captures
  Timer? _captureResultTimer; // Timer to poll for capture results

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializeWebSocket();
  }

  Future<void> _initializeCamera() async {
    // Request camera permission
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _hasPermission = false;
      });
      return;
    }

    setState(() {
      _hasPermission = true;
    });

    // Get available cameras
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        print('No cameras available');
        return;
      }

      // Prefer back camera
      CameraDescription? selectedCamera;
      for (var camera in _cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      selectedCamera ??= _cameras[0];

      // Initialize camera controller
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _cameraSize = Size(
            _controller!.value.previewSize?.height ?? 0,
            _controller!.value.previewSize?.width ?? 0,
          );
        });

        // Start sending frames
        _startFrameStreaming();
      }
    } catch (e) {
      print('Error initializing camera: $e');
    }
  }

  Future<void> _initializeWebSocket() async {
    final provider = Provider.of<WebSocketProvider>(context, listen: false);
    if (!provider.isConnected) {
      await provider.initialize();
    }
  }

  void _startFrameStreaming() {
    _frameTimer?.cancel();

    // Listen for auto-capture when guidance shows ready
    final provider = Provider.of<WebSocketProvider>(context, listen: false);
    provider.addListener(_checkAutoCapture);

    // Send frames at ~5 FPS (200ms interval) to avoid overwhelming the camera
    _frameTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted ||
          _controller == null ||
          !_controller!.value.isInitialized) {
        return;
      }

      // Only capture if previous capture is done
      if (!_isCapturingFrame) {
        _captureAndSendFrame();
      }
    });
  }

  void _checkAutoCapture() {
    if (!mounted) return;

    final provider = Provider.of<WebSocketProvider>(context, listen: false);
    final guidance = provider.currentGuidance;

    // Check if ready and auto-capture should trigger
    if (guidance?.readyToCapture == true && !provider.isCapturing) {
      // The backend handles auto-capture
      // Check for result in the frame capture loop
      final result = provider.lastResult;
      if (result != null && result.success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ResultScreen(scanResult: result),
          ),
        );
        provider.resetCapture();
      }
    }
  }

  Future<void> _captureAndSendFrame() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturingFrame) return;

    _isCapturingFrame = true;
    try {
      final image = await _controller!.takePicture();
      final imageBytes = await image.readAsBytes();

      // Convert to JPEG format for backend
      final jpegBytes = await _convertToJpeg(imageBytes);

      // Send to backend
      final provider = Provider.of<WebSocketProvider>(context, listen: false);
      if (provider.isConnected) {
        provider.sendFrame(jpegBytes, mode: 'auto');
      }

      // Check if we got a capture result (auto-capture from backend)
      final result = provider.lastResult;
      if (result != null && result.success && mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ResultScreen(scanResult: result),
          ),
        );
        provider.resetCapture();
      }
    } catch (e) {
      print('Error capturing frame: $e');
    } finally {
      _isCapturingFrame = false;
    }
  }

  Future<Uint8List> _convertToJpeg(Uint8List imageBytes) async {
    // Camera package already provides JPEG, but we ensure it's the right format
    // If needed, we can convert using image package here
    return imageBytes;
  }

  void _handleManualCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      final provider = Provider.of<WebSocketProvider>(context, listen: false);

      final image = await _controller!.takePicture();
      final imageBytes = await image.readAsBytes();
      final jpegBytes = await _convertToJpeg(imageBytes);

      // Reset any previous result
      provider.resetCapture();

      // Send capture request
      provider.requestCapture(jpegBytes);

      print('Capture request sent, waiting for result...');

      // Poll for result with timeout (5 seconds)
      _captureResultTimer?.cancel();
      int attempts = 0;
      const maxAttempts = 50; // 50 * 100ms = 5 seconds

      _captureResultTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        attempts++;
        final result = provider.lastResult;

        if (result != null) {
          timer.cancel();
          _captureResultTimer = null;

          print('Capture result received: success=${result.success}');

          if (mounted) {
            if (result.success) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => ResultScreen(scanResult: result),
                ),
              );
              provider.resetCapture();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result.message)),
              );
              provider.resetCapture();
            }
          }
        } else if (attempts >= maxAttempts) {
          timer.cancel();
          _captureResultTimer = null;
          print('Capture timeout - no result received');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Capture timeout. Please try again.')),
            );
            provider.resetCapture();
          }
        }
      });
    } catch (e) {
      print('Error capturing image: $e');
      _captureResultTimer?.cancel();
      _captureResultTimer = null;
      final provider = Provider.of<WebSocketProvider>(context, listen: false);
      provider.resetCapture();
    }
  }

  void _onCaptureResult() {
    if (!mounted) return;

    final provider = Provider.of<WebSocketProvider>(context, listen: false);
    final result = provider.lastResult;

    if (result != null && result.success) {
      provider.removeListener(_onCaptureResult);

      // Navigate to result screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ResultScreen(
            scanResult: result,
          ),
        ),
      );
    } else if (result != null && !result.success) {
      provider.removeListener(_onCaptureResult);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.camera_alt, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Camera permission is required',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  await openAppSettings();
                  _initializeCamera();
                },
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized || _controller == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Initializing camera...'),
            ],
          ),
        ),
      );
    }

    final provider = Provider.of<WebSocketProvider>(context);
    final guidance = provider.currentGuidance;

    // Calculate 3:4 aspect ratio dimensions
    final screenSize = MediaQuery.of(context).size;
    final previewAspectRatio = 3.0 / 4.0;
    double previewWidth = screenSize.width;
    double previewHeight = previewWidth / previewAspectRatio;

    // If height exceeds screen, adjust width instead
    if (previewHeight > screenSize.height) {
      previewHeight = screenSize.height;
      previewWidth = previewHeight * previewAspectRatio;
    }

    final previewSize = Size(previewWidth, previewHeight);
    final previewOffset = Offset(
      (screenSize.width - previewWidth) / 2,
      (screenSize.height - previewHeight) / 2,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Center the camera preview with 3:4 aspect ratio
          Center(
            child: AspectRatio(
              aspectRatio: previewAspectRatio,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize?.height ??
                          previewWidth,
                      height: _controller!.value.previewSize?.width ??
                          previewHeight,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Static guide box overlay (always visible, scaled to preview)
          Positioned(
            left: previewOffset.dx,
            top: previewOffset.dy,
            child: SizedBox(
              width: previewSize.width,
              height: previewSize.height,
              child: CustomPaint(
                painter: GuideBoxPainter(
                  displaySize: previewSize,
                ),
              ),
            ),
          ),

          // Card outline overlay (when card is detected, scaled to preview)
          if (guidance?.cardCorners != null && _cameraSize != null)
            Positioned(
              left: previewOffset.dx,
              top: previewOffset.dy,
              child: SizedBox(
                width: previewSize.width,
                height: previewSize.height,
                child: CustomPaint(
                  painter: CardOutline(
                    corners: guidance!.cardCorners,
                    videoSize: _cameraSize!,
                    displaySize: previewSize,
                    isReady: guidance.readyToCapture,
                  ),
                ),
              ),
            ),

          // Guidance overlay (scaled to preview)
          Positioned(
            left: previewOffset.dx,
            top: previewOffset.dy,
            child: SizedBox(
              width: previewSize.width,
              height: previewSize.height,
              child: GuidanceOverlay(
                guidance: guidance,
                videoSize: _cameraSize ?? const Size(640, 480),
              ),
            ),
          ),

          // Connection status
          if (!provider.isConnected)
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red.withOpacity(0.8),
                child: const Text(
                  'Not connected to server',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          // Manual capture button
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.extended(
                onPressed: provider.isConnected &&
                        !provider.isCapturing &&
                        guidance?.cardCorners != null
                    ? _handleManualCapture
                    : null,
                backgroundColor: guidance?.cardCorners != null
                    ? (guidance?.readyToCapture == true
                        ? Colors.green
                        : Colors.orange)
                    : Colors.blue,
                icon: provider.isCapturing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(
                  provider.isCapturing ? 'Processing...' : 'Capture',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    _controller?.dispose();
    _captureResultTimer?.cancel();

    // Remove listeners if added
    if (mounted) {
      final provider = Provider.of<WebSocketProvider>(context, listen: false);
      provider.removeListener(_checkAutoCapture);
    }

    super.dispose();
  }
}

/// Painter for drawing a static guide box to help users align their card
class GuideBoxPainter extends CustomPainter {
  final Size displaySize;

  GuideBoxPainter({
    required this.displaySize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Card aspect ratio (standard ID card: 85.60mm × 53.98mm ≈ 1.586)
    const double cardAspectRatio = 1.586;

    // Calculate guide box dimensions (75% of screen width - increased for better visibility)
    final double boxWidth = displaySize.width * 0.75;
    final double boxHeight = boxWidth / cardAspectRatio;

    // Center the box
    final double left = (displaySize.width - boxWidth) / 2;
    final double top = (displaySize.height - boxHeight) / 2;
    final double right = left + boxWidth;
    final double bottom = top + boxHeight;

    // Draw outer border (white/dashed)
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Draw dashed border
    final path = Path()
      ..moveTo(left, top)
      ..lineTo(right, top)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..close();

    canvas.drawPath(path, borderPaint);

    // Draw corner markers
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;

    const double cornerLength = 30.0;

    // Top-left corner
    canvas.drawLine(
        Offset(left, top), Offset(left + cornerLength, top), cornerPaint);
    canvas.drawLine(
        Offset(left, top), Offset(left, top + cornerLength), cornerPaint);

    // Top-right corner
    canvas.drawLine(
        Offset(right, top), Offset(right - cornerLength, top), cornerPaint);
    canvas.drawLine(
        Offset(right, top), Offset(right, top + cornerLength), cornerPaint);

    // Bottom-right corner
    canvas.drawLine(Offset(right, bottom), Offset(right - cornerLength, bottom),
        cornerPaint);
    canvas.drawLine(Offset(right, bottom), Offset(right, bottom - cornerLength),
        cornerPaint);

    // Bottom-left corner
    canvas.drawLine(
        Offset(left, bottom), Offset(left + cornerLength, bottom), cornerPaint);
    canvas.drawLine(
        Offset(left, bottom), Offset(left, bottom - cornerLength), cornerPaint);

    // Draw semi-transparent overlay outside the guide box
    final overlayPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    // Top overlay
    canvas.drawRect(
      Rect.fromLTWH(0, 0, displaySize.width, top),
      overlayPaint,
    );
    // Bottom overlay
    canvas.drawRect(
      Rect.fromLTWH(0, bottom, displaySize.width, displaySize.height - bottom),
      overlayPaint,
    );
    // Left overlay
    canvas.drawRect(
      Rect.fromLTWH(0, top, left, boxHeight),
      overlayPaint,
    );
    // Right overlay
    canvas.drawRect(
      Rect.fromLTWH(right, top, displaySize.width - right, boxHeight),
      overlayPaint,
    );
  }

  @override
  bool shouldRepaint(GuideBoxPainter oldDelegate) {
    return displaySize != oldDelegate.displaySize;
  }
}
