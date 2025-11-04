# ID Card Scanner Backend

A Python WebSocket backend server for real-time ID card scanning with guidance features. Compatible with Flutter mobile applications for Android and iOS.

## Features

- **Real-time Card Detection**: Detects standard ID card sizes (credit/debit card dimensions)
- **Live Guidance**: Provides real-time feedback for:
  - Distance adjustment (move closer/farther)
  - Centering assistance (move left/right/up/down)
  - Blur detection and notification
  - Glare/hotspot detection
- **Auto-capture**: Automatically captures when all quality checks pass
- **Manual Capture**: Process images on explicit user request
- **Perspective Correction**: Extracts and warps card to rectangular format

## Requirements

- Python 3.9, 3.10, or 3.11 (recommended for stability)
- All dependencies listed in `requirements.txt`

## Installation

1. Navigate to the Python3 directory:
```bash
cd Python3
```

2. Create a virtual environment (recommended):
```bash
python -m venv venv
```

3. Activate the virtual environment:
   - On Windows:
     ```bash
     venv\Scripts\activate
     ```
   - On macOS/Linux:
     ```bash
     source venv/bin/activate
     ```

4. Install dependencies:
```bash
pip install -r requirements.txt
```

## Usage

### Starting the Server

Run the server:
```bash
python main.py
```

The server will start on `http://0.0.0.0:8000` (accessible from all network interfaces).

For localhost only:
```bash
uvicorn main:app --host 127.0.0.1 --port 8000
```

### WebSocket Endpoint

Connect to: `ws://localhost:8000/ws` (or your server IP/domain)

### Message Protocol

#### Client → Server (Flutter → Python)

**Frame Processing:**
```json
{
  "type": "frame",
  "image": "base64_encoded_jpeg_string",
  "mode": "auto" | "manual"
}
```

**Manual Capture:**
```json
{
  "type": "capture",
  "image": "base64_encoded_jpeg_string"
}
```

**Reset Session:**
```json
{
  "type": "reset"
}
```

#### Server → Client (Python → Flutter)

**Guidance Response:**
```json
{
  "type": "guidance",
  "card_detected": true,
  "message": "Center document",
  "distance": "optimal" | "too_close" | "too_far",
  "centering": "centered" | "off_center",
  "blur": "sharp" | "blurry",
  "glare": "acceptable" | "excessive",
  "ready_to_capture": true,
  "card_corners": [[x1,y1], [x2,y2], [x3,y3], [x4,y4]]
}
```

**Capture Response:**
```json
{
  "type": "capture",
  "success": true,
  "warped_image": "base64_encoded_jpeg_string",
  "message": "Card captured successfully"
}
```

**Error Response:**
```json
{
  "type": "error",
  "message": "Error description"
}
```

## Integration with Flutter

### WebSocket Connection

```dart
import 'package:web_socket_channel/web_socket_channel.dart';

final channel = WebSocketChannel.connect(
  Uri.parse('ws://your-server-ip:8000/ws'),
);
```

### Sending Frames

```dart
import 'dart:convert';
import 'package:image/image.dart' as img;

// Convert camera frame to base64
Uint8List imageBytes = // ... get from camera
String base64Image = base64Encode(imageBytes);

// Send frame
channel.sink.add(jsonEncode({
  'type': 'frame',
  'image': base64Image,
  'mode': 'auto'  // or 'manual'
}));
```

### Receiving Guidance

```dart
channel.stream.listen((message) {
  Map<String, dynamic> response = jsonDecode(message);
  
  if (response['type'] == 'guidance') {
    String messageText = response['message'];
    bool readyToCapture = response['ready_to_capture'];
    // Update UI with guidance
  } else if (response['type'] == 'capture') {
    if (response['success']) {
      String warpedImageBase64 = response['warped_image'];
      // Decode and display warped image
    }
  }
});
```

## Configuration

### Auto-capture Threshold

The number of consecutive good frames required for auto-capture can be adjusted in `main.py`:

```python
self.auto_capture_threshold = 30  # Default: 30 frames
```

### Detection Parameters

Adjust detection parameters in individual modules:
- `card_detector.py`: Aspect ratio ranges, area thresholds
- `blur_detector.py`: Blur threshold (Laplacian variance)
- `glare_detector.py`: Glare intensity threshold, max glare percentage
- `distance_guide.py`: Optimal distance area ratios
- `centering_guide.py`: Center threshold ratio

## Deployment

### Local Development

For local testing with Flutter app on same device or emulator:
```bash
python main.py
```
Connect to: `ws://127.0.0.1:8000/ws`

### Network Deployment

For accessing from other devices on the same network:
```bash
python main.py
```
Connect to: `ws://<your-computer-ip>:8000/ws`

### Production Deployment

For production, use a proper ASGI server with process management:

```bash
uvicorn main:app --host 0.0.0.0 --port 8000 --workers 4
```

Or use Gunicorn with Uvicorn workers:
```bash
gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

## API Endpoints

- `GET /`: Health check
- `GET /health`: Health check endpoint
- `WebSocket /ws`: Main WebSocket endpoint for frame processing

## Troubleshooting

### Connection Issues

- Ensure firewall allows port 8000
- Check that server is running on correct host/port
- Verify WebSocket URL format: `ws://` not `http://`

### Image Processing Issues

- Ensure images are sent as base64-encoded JPEG/PNG
- Check image resolution (recommended: 640x480 or higher)
- Verify OpenCV is installed correctly: `python -c "import cv2; print(cv2.__version__)"`

### Detection Issues

- Ensure good lighting conditions
- Use contrasting background (not same color as card)
- Make sure card is fully visible in frame
- Adjust detection parameters if needed

## File Structure

```
Python3/
├── main.py                 # FastAPI WebSocket server
├── card_detector.py        # ID card detection
├── distance_guide.py       # Distance analysis
├── centering_guide.py      # Centering analysis
├── blur_detector.py        # Blur detection
├── glare_detector.py       # Glare/hotspot detection
├── quality_validator.py    # Quality aggregation
├── warp_transformer.py     # Perspective transformation
├── requirements.txt        # Python dependencies
└── README.md              # This file
```

## License

This project is provided as-is for ID card scanning purposes.

