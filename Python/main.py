"""
FastAPI WebSocket Server for ID Card Scanner
Handles real-time frame processing and provides guidance feedback.
"""
import base64
import json
import cv2
import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
import uvicorn

from card_detector import CardDetector
from blur_detector import BlurDetector
from glare_detector import GlareDetector
from distance_guide import DistanceGuide
from centering_guide import CenteringGuide
from warp_transformer import WarpTransformer
from quality_validator import QualityValidator


app = FastAPI(title="ID Card Scanner Backend")

# Enable CORS for Flutter app
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app's origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ScannerSession:
    """Manages state for a single scanning session."""
    
    def __init__(self):
        self.card_detector = CardDetector()
        self.blur_detector = BlurDetector()
        self.glare_detector = GlareDetector()
        self.distance_guide = DistanceGuide()
        self.centering_guide = CenteringGuide()
        self.warp_transformer = WarpTransformer()
        self.quality_validator = QualityValidator()
        
        # Auto-capture state
        self.good_frames_count = 0
        self.auto_capture_threshold = 30  # Number of consecutive good frames for auto-capture
        
        # Tracking state for stability
        self.last_detected_corners = None
        self.detection_history = []  # Keep last N detection results
        self.history_size = 5  # Number of frames to keep in history
        self.detection_threshold = 3  # Need N detections in history to confirm
    
    def reset_auto_capture(self):
        """Reset auto-capture counter."""
        self.good_frames_count = 0
    
    def process_frame(self, frame, mode="auto"):
        """
        Process a single frame and return guidance.
        
        Args:
            frame: BGR image frame (numpy array)
            mode: "auto" or "manual"
        
        Returns:
            dict: Guidance response
        """
        # Detect card
        card_found, card_corners = self.card_detector.detect_card(frame)
        
        # Update detection history for stability
        self.detection_history.append(bool(card_found))
        if len(self.detection_history) > self.history_size:
            self.detection_history.pop(0)
        
        # Use hysteresis: need multiple detections to confirm, but keep tracking if recently detected
        recent_detections = sum(self.detection_history)
        stable_detection = recent_detections >= self.detection_threshold
        
        # If we had a detection recently but current frame doesn't detect, use last known corners
        if not card_found and self.last_detected_corners is not None and recent_detections > 0:
            # Use last known corners for stability (temporal tracking)
            card_found = True
            card_corners = self.last_detected_corners
        elif card_found:
            # Update last known good corners
            self.last_detected_corners = card_corners.copy()
        
        if not stable_detection and not card_found:
            self.reset_auto_capture()
            # Clear history if no detection for a while
            if recent_detections == 0:
                self.last_detected_corners = None
                # Reset size tracking if no detection for several frames
                if len(self.detection_history) == 0 or sum(self.detection_history[-3:]) == 0:
                    self.card_detector.reset_size_tracking()
            return {
                "type": "guidance",
                "card_detected": False,
                "message": "Place document in frame",
                "distance": "unknown",
                "centering": "unknown",
                "blur": "unknown",
                "glare": "unknown",
                "ready_to_capture": False,
                "card_corners": None
            }
        
        # Analyze distance
        distance_result = self.distance_guide.analyze_distance(frame, card_corners)
        
        # Analyze centering
        centering_result = self.centering_guide.analyze_centering(frame, card_corners)
        
        # Check blur
        is_blurry, blur_variance = self.blur_detector.detect_blur(frame, card_corners)
        
        # Check glare
        glare_result = self.glare_detector.detect_glare(frame, card_corners)
        
        # Ensure all boolean values are Python bools (not numpy bools) for JSON serialization
        is_blurry = bool(is_blurry)
        glare_acceptable = bool(glare_result['is_acceptable'])
        is_centered = bool(centering_result['is_centered'])
        
        # Determine primary message (priority order)
        if distance_result['status'] != 'optimal':
            primary_message = distance_result['message']
        elif not is_centered:
            primary_message = centering_result['message']
        elif is_blurry:
            primary_message = "Too blurry"
        elif not glare_acceptable:
            primary_message = glare_result['message']
        else:
            primary_message = "Hold still..."
        
        # Check if ready for capture
        quality_result = self.quality_validator.validate(frame)
        ready_to_capture = bool(quality_result['is_valid'])
        
        # Update auto-capture counter
        if ready_to_capture and mode == "auto":
            self.good_frames_count += 1
        else:
            self.reset_auto_capture()
        
        # Convert card corners to list for JSON serialization
        card_corners_list = None
        if card_corners is not None:
            # Ensure it's a Python list and convert numpy types to Python types
            card_corners_list = [[float(c[0]), float(c[1])] for c in card_corners.tolist()]
        
        # Ensure all values are JSON serializable (convert numpy types to Python types)
        return {
            "type": "guidance",
            "card_detected": bool(stable_detection),
            "message": str(primary_message),
            "distance": str(distance_result['status']),
            "centering": str(centering_result['status']),
            "blur": "blurry" if is_blurry else "sharp",
            "glare": "excessive" if not glare_acceptable else "acceptable",
            "ready_to_capture": ready_to_capture,
            "card_corners": card_corners_list
        }
    
    def capture_card(self, frame):
        """
        Capture and warp the card from the frame.
        
        Args:
            frame: BGR image frame
        
        Returns:
            dict: Capture response with warped image
        """
        # Validate quality first
        quality_result = self.quality_validator.validate(frame)
        
        if not bool(quality_result['is_valid']):
            return {
                "type": "capture",
                "success": False,
                "warped_image": None,
                "message": "Image does not meet quality requirements: " + ", ".join(quality_result['messages'])
            }
        
        # Extract card
        card_corners = quality_result['card_corners']
        warped_image = self.warp_transformer.warp_card(frame, card_corners)
        
        if warped_image is None:
            return {
                "type": "capture",
                "success": False,
                "warped_image": None,
                "message": "Failed to extract card image"
            }
        
        # Encode warped image to base64
        # Convert BGR to RGB for JPEG encoding
        warped_rgb = cv2.cvtColor(warped_image, cv2.COLOR_BGR2RGB)
        
        # Encode to JPEG
        _, buffer = cv2.imencode('.jpg', warped_rgb, [cv2.IMWRITE_JPEG_QUALITY, 95])
        warped_base64 = base64.b64encode(buffer).decode('utf-8')
        
        return {
            "type": "capture",
            "success": True,
            "warped_image": warped_base64,
            "message": "Card captured successfully"
        }
    
    def reset_tracking(self):
        """Reset all tracking state."""
        self.last_detected_corners = None
        self.detection_history = []
        self.reset_auto_capture()
        self.card_detector.reset_size_tracking()


def decode_base64_image(base64_string):
    """
    Decode base64 image string to OpenCV BGR format.
    
    Args:
        base64_string: Base64 encoded image string
    
    Returns:
        np.ndarray: BGR image array
    """
    try:
        # Remove data URL prefix if present
        if ',' in base64_string:
            base64_string = base64_string.split(',')[1]
        
        # Decode base64
        image_data = base64.b64decode(base64_string)
        
        # Convert to numpy array
        nparr = np.frombuffer(image_data, np.uint8)
        
        # Decode image
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            print("Warning: Failed to decode image - imdecode returned None")
            return None
        
        if len(image.shape) != 3 or image.shape[2] != 3:
            print(f"Warning: Unexpected image shape: {image.shape}")
            return None
            
        return image
    except Exception as e:
        print(f"Error decoding image: {e}")
        import traceback
        traceback.print_exc()
        return None


@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    WebSocket endpoint for real-time frame processing.
    """
    await websocket.accept()
    print("WebSocket client connected")
    
    session = ScannerSession()
    
    try:
        while True:
            # Receive message from client
            data = await websocket.receive_text()
            print(f"Received message from client: {len(data)} bytes")
            
            try:
                message = json.loads(data)
            except json.JSONDecodeError as e:
                print(f"JSON decode error: {e}, Data preview: {data[:100]}")
                await websocket.send_json({
                    "type": "error",
                    "message": "Invalid JSON format"
                })
                continue
            
            # Handle different message types
            msg_type = message.get("type")
            print(f"Message type: {msg_type}")
            
            if msg_type == "frame":
                # Process frame
                image_base64 = message.get("image")
                mode = message.get("mode", "auto")
                
                if not image_base64:
                    print("Warning: Missing image data in frame message")
                    await websocket.send_json({
                        "type": "error",
                        "message": "Missing image data"
                    })
                    continue
                
                # Decode image
                frame = decode_base64_image(image_base64)
                
                if frame is None:
                    print("Warning: Failed to decode image frame")
                    await websocket.send_json({
                        "type": "error",
                        "message": "Failed to decode image"
                    })
                    continue
                
                # Process frame
                try:
                    print(f"Processing frame: shape={frame.shape}, mode={mode}")
                    guidance = session.process_frame(frame, mode)
                    print(f"Sending guidance response: type={guidance.get('type')}, card_detected={guidance.get('card_detected')}")
                    
                    # Send guidance response
                    await websocket.send_json(guidance)
                    print("Guidance response sent successfully")
                    
                    # Auto-capture if threshold reached
                    if mode == "auto" and session.good_frames_count >= session.auto_capture_threshold:
                        print(f"Auto-capture triggered: good_frames_count={session.good_frames_count}")
                        capture_result = session.capture_card(frame)
                        await websocket.send_json(capture_result)
                        session.reset_auto_capture()
                except Exception as e:
                    print(f"Error processing frame: {e}")
                    import traceback
                    traceback.print_exc()
                    await websocket.send_json({
                        "type": "error",
                        "message": f"Processing error: {str(e)}"
                    })
            
            elif msg_type == "capture":
                # Manual capture request
                image_base64 = message.get("image")
                
                if not image_base64:
                    print("Warning: Missing image data for capture")
                    await websocket.send_json({
                        "type": "error",
                        "message": "Missing image data for capture"
                    })
                    continue
                
                # Decode image
                frame = decode_base64_image(image_base64)
                
                if frame is None:
                    print("Warning: Failed to decode image for capture")
                    await websocket.send_json({
                        "type": "error",
                        "message": "Failed to decode image"
                    })
                    continue
                
                # Capture card
                try:
                    capture_result = session.capture_card(frame)
                    await websocket.send_json(capture_result)
                except Exception as e:
                    print(f"Error capturing card: {e}")
                    import traceback
                    traceback.print_exc()
                    await websocket.send_json({
                        "type": "error",
                        "message": f"Capture error: {str(e)}"
                    })
            
            elif msg_type == "reset":
                # Reset session state
                session.reset_tracking()
                await websocket.send_json({
                    "type": "reset",
                    "message": "Session reset"
                })
            
            else:
                await websocket.send_json({
                    "type": "error",
                    "message": f"Unknown message type: {msg_type}"
                })
    
    except WebSocketDisconnect:
        print("Client disconnected")
    except Exception as e:
        print(f"WebSocket error: {e}")
        try:
            await websocket.send_json({
                "type": "error",
                "message": f"Server error: {str(e)}"
            })
        except:
            pass


@app.get("/")
async def root():
    """Health check endpoint."""
    return {
        "status": "running",
        "service": "ID Card Scanner Backend",
        "version": "1.0.0"
    }


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/test", response_class=HTMLResponse)
async def test_page():
    """Serve test HTML page for camera access."""
    html_content = """
<!DOCTYPE html>
<html>
<head>
    <title>ID Card Scanner Test</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
            background: #f0f0f0;
        }
        .container {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .video-container {
            position: relative;
            width: 100%;
            max-width: 800px;
            margin: 20px auto;
            background: #000;
            border-radius: 10px;
            overflow: hidden;
        }
        #video {
            width: 100%;
            display: block;
        }
        #canvas {
            display: none;
        }
        .status {
            background: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
            border-left: 4px solid #007bff;
        }
        .status-item {
            margin: 10px 0;
            padding: 8px;
            background: white;
            border-radius: 3px;
        }
        .status-label {
            font-weight: bold;
            display: inline-block;
            width: 150px;
        }
        .status-value {
            padding: 3px 10px;
            border-radius: 3px;
            font-weight: bold;
        }
        .status-good {
            background: #d4edda;
            color: #155724;
        }
        .status-bad {
            background: #f8d7da;
            color: #721c24;
        }
        .status-unknown {
            background: #e2e3e5;
            color: #383d41;
        }
        .controls {
            text-align: center;
            margin: 20px 0;
        }
        button {
            padding: 12px 24px;
            margin: 5px;
            font-size: 16px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-weight: bold;
        }
        .btn-start {
            background: #28a745;
            color: white;
        }
        .btn-stop {
            background: #dc3545;
            color: white;
        }
        .btn-capture {
            background: #007bff;
            color: white;
        }
        button:hover {
            opacity: 0.9;
        }
        button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .message {
            text-align: center;
            font-size: 20px;
            font-weight: bold;
            padding: 15px;
            margin: 20px 0;
            border-radius: 5px;
        }
        .message-info {
            background: #d1ecf1;
            color: #0c5460;
        }
        .message-success {
            background: #d4edda;
            color: #155724;
        }
        .message-error {
            background: #f8d7da;
            color: #721c24;
        }
        .connection-status {
            text-align: center;
            padding: 10px;
            margin: 10px 0;
            border-radius: 5px;
            font-weight: bold;
        }
        .connected {
            background: #d4edda;
            color: #155724;
        }
        .disconnected {
            background: #f8d7da;
            color: #721c24;
        }
        #capturedImage {
            max-width: 100%;
            margin-top: 20px;
            border-radius: 5px;
            display: none;
        }
        .overlay {
            position: absolute;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            pointer-events: none;
        }
        .card-outline {
            position: absolute;
            border: 3px solid #00ff00;
            border-radius: 5px;
            display: none;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>ID Card Scanner - Test UI</h1>
        
        <div id="connectionStatus" class="connection-status disconnected">
            Disconnected
        </div>
        
        <div class="controls">
            <button id="startBtn" class="btn-start" onclick="startCamera()">Start Camera</button>
            <button id="stopBtn" class="btn-stop" onclick="stopCamera()" disabled>Stop Camera</button>
            <button id="captureBtn" class="btn-capture" onclick="manualCapture()" disabled>Manual Capture</button>
        </div>
        
        <div class="video-container">
            <video id="video" autoplay playsinline></video>
            <canvas id="canvas"></canvas>
            <div class="overlay">
                <div id="cardOutline" class="card-outline"></div>
            </div>
        </div>
        
        <div id="message" class="message message-info" style="display: none;"></div>
        
        <div class="status">
            <h3>Status</h3>
            <div class="status-item">
                <span class="status-label">Card Detected:</span>
                <span id="cardDetected" class="status-value status-unknown">Unknown</span>
            </div>
            <div class="status-item">
                <span class="status-label">Distance:</span>
                <span id="distance" class="status-value status-unknown">Unknown</span>
            </div>
            <div class="status-item">
                <span class="status-label">Centering:</span>
                <span id="centering" class="status-value status-unknown">Unknown</span>
            </div>
            <div class="status-item">
                <span class="status-label">Blur:</span>
                <span id="blur" class="status-value status-unknown">Unknown</span>
            </div>
            <div class="status-item">
                <span class="status-label">Glare:</span>
                <span id="glare" class="status-value status-unknown">Unknown</span>
            </div>
            <div class="status-item">
                <span class="status-label">Ready to Capture:</span>
                <span id="readyToCapture" class="status-value status-unknown">Unknown</span>
            </div>
        </div>
        
        <img id="capturedImage" alt="Captured ID Card">
    </div>
    
    <script>
        let ws = null;
        let video = null;
        let canvas = null;
        let ctx = null;
        let stream = null;
        let isProcessing = false;
        let captureMode = 'auto';
        
        window.onload = function() {
            video = document.getElementById('video');
            canvas = document.getElementById('canvas');
            ctx = canvas.getContext('2d');
        };
        
        function updateConnectionStatus(connected) {
            const statusEl = document.getElementById('connectionStatus');
            if (connected) {
                statusEl.textContent = 'Connected';
                statusEl.className = 'connection-status connected';
            } else {
                statusEl.textContent = 'Disconnected';
                statusEl.className = 'connection-status disconnected';
            }
        }
        
        function connectWebSocket() {
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${window.location.host}/ws`;
            
            ws = new WebSocket(wsUrl);
            
            ws.onopen = function() {
                console.log('WebSocket connected');
                updateConnectionStatus(true);
            };
            
            ws.onmessage = function(event) {
                try {
                    const response = JSON.parse(event.data);
                    console.log('Received response:', response.type);
                    handleResponse(response);
                } catch (error) {
                    console.error('Error parsing WebSocket message:', error);
                }
            };
            
            ws.onerror = function(error) {
                console.error('WebSocket error:', error);
                updateConnectionStatus(false);
            };
            
            ws.onclose = function(event) {
                console.log('WebSocket disconnected. Code:', event.code, 'Reason:', event.reason);
                updateConnectionStatus(false);
            };
        }
        
        function handleResponse(response) {
            if (response.type === 'guidance') {
                updateStatus(response);
                drawCardOutline(response.card_corners);
                updateMessage(response.message, 'info');
                
                if (response.ready_to_capture) {
                    document.getElementById('captureBtn').disabled = false;
                } else {
                    document.getElementById('captureBtn').disabled = true;
                }
            } else if (response.type === 'capture') {
                if (response.success) {
                    displayCapturedImage(response.warped_image);
                    updateMessage('Card captured successfully!', 'success');
                } else {
                    updateMessage('Capture failed: ' + response.message, 'error');
                }
            } else if (response.type === 'error') {
                updateMessage('Error: ' + response.message, 'error');
            }
        }
        
        function updateStatus(data) {
            const cardDetected = document.getElementById('cardDetected');
            cardDetected.textContent = data.card_detected ? 'Yes' : 'No';
            cardDetected.className = 'status-value ' + (data.card_detected ? 'status-good' : 'status-bad');
            
            const distance = document.getElementById('distance');
            distance.textContent = data.distance;
            distance.className = 'status-value ' + (data.distance === 'optimal' ? 'status-good' : 'status-bad');
            
            const centering = document.getElementById('centering');
            centering.textContent = data.centering;
            centering.className = 'status-value ' + (data.centering === 'centered' ? 'status-good' : 'status-bad');
            
            const blur = document.getElementById('blur');
            blur.textContent = data.blur;
            blur.className = 'status-value ' + (data.blur === 'sharp' ? 'status-good' : 'status-bad');
            
            const glare = document.getElementById('glare');
            glare.textContent = data.glare;
            glare.className = 'status-value ' + (data.glare === 'acceptable' ? 'status-good' : 'status-bad');
            
            const readyToCapture = document.getElementById('readyToCapture');
            readyToCapture.textContent = data.ready_to_capture ? 'Yes' : 'No';
            readyToCapture.className = 'status-value ' + (data.ready_to_capture ? 'status-good' : 'status-bad');
        }
        
        function drawCardOutline(corners) {
            const outline = document.getElementById('cardOutline');
            if (!corners || corners.length !== 4) {
                outline.style.display = 'none';
                return;
            }
            
            const videoRect = video.getBoundingClientRect();
            const videoWidth = video.videoWidth;
            const videoHeight = video.videoHeight;
            const displayWidth = videoRect.width;
            const displayHeight = videoRect.height;
            
            const scaleX = displayWidth / videoWidth;
            const scaleY = displayHeight / videoHeight;
            
            // Find bounding box
            let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
            corners.forEach(point => {
                minX = Math.min(minX, point[0]);
                minY = Math.min(minY, point[1]);
                maxX = Math.max(maxX, point[0]);
                maxY = Math.max(maxY, point[1]);
            });
            
            outline.style.display = 'block';
            outline.style.left = (minX * scaleX) + 'px';
            outline.style.top = (minY * scaleY) + 'px';
            outline.style.width = ((maxX - minX) * scaleX) + 'px';
            outline.style.height = ((maxY - minY) * scaleY) + 'px';
        }
        
        function updateMessage(text, type) {
            const messageEl = document.getElementById('message');
            messageEl.textContent = text;
            messageEl.className = 'message message-' + type;
            messageEl.style.display = 'block';
        }
        
        function displayCapturedImage(base64Image) {
            const img = document.getElementById('capturedImage');
            img.src = 'data:image/jpeg;base64,' + base64Image;
            img.style.display = 'block';
        }
        
        async function startCamera() {
            try {
                stream = await navigator.mediaDevices.getUserMedia({ 
                    video: { 
                        width: { ideal: 1280 },
                        height: { ideal: 720 },
                        facingMode: 'environment'
                    } 
                });
                video.srcObject = stream;
                
                video.onloadedmetadata = function() {
                    canvas.width = video.videoWidth;
                    canvas.height = video.videoHeight;
                };
                
                document.getElementById('startBtn').disabled = true;
                document.getElementById('stopBtn').disabled = false;
                document.getElementById('captureBtn').disabled = false;
                
                connectWebSocket();
                
                // Wait for WebSocket to connect
                function waitForConnection() {
                    if (ws && ws.readyState === WebSocket.OPEN) {
                        console.log('WebSocket connected, starting frame processing...');
                        startProcessing();
                    } else if (ws && ws.readyState === WebSocket.CONNECTING) {
                        console.log('WebSocket connecting, waiting...');
                        setTimeout(waitForConnection, 100);
                    } else {
                        console.log('WebSocket connection failed, retrying...');
                        setTimeout(waitForConnection, 500);
                    }
                }
                setTimeout(waitForConnection, 100);
                
            } catch (error) {
                console.error('Error accessing camera:', error);
                updateMessage('Error accessing camera: ' + error.message, 'error');
            }
        }
        
        function stopCamera() {
            if (stream) {
                stream.getTracks().forEach(track => track.stop());
                stream = null;
            }
            if (ws) {
                ws.close();
                ws = null;
            }
            isProcessing = false;
            video.srcObject = null;
            
            document.getElementById('startBtn').disabled = false;
            document.getElementById('stopBtn').disabled = true;
            document.getElementById('captureBtn').disabled = true;
            
            document.getElementById('cardOutline').style.display = 'none';
            updateMessage('Camera stopped', 'info');
        }
        
        function startProcessing() {
            if (isProcessing) return;
            isProcessing = true;
            
                            function processFrame() {
                if (!isProcessing || !stream) {
                    return;
                }
                
                if (!ws || ws.readyState !== WebSocket.OPEN) {
                    console.log('WebSocket not ready, retrying in 500ms...');
                    setTimeout(processFrame, 500);
                    return;
                }
                
                try {
                    if (video.readyState !== video.HAVE_ENOUGH_DATA) {
                        setTimeout(processFrame, 100);
                        return;
                    }
                    
                    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
                    const imageData = canvas.toDataURL('image/jpeg', 0.8);
                    const base64Data = imageData.split(',')[1];
                    
                    if (!base64Data) {
                        console.error('Failed to get base64 data from canvas');
                        setTimeout(processFrame, 100);
                        return;
                    }
                    
                    ws.send(JSON.stringify({
                        type: 'frame',
                        image: base64Data,
                        mode: captureMode
                    }));
                    
                    setTimeout(processFrame, 100); // ~10 FPS
                } catch (error) {
                    console.error('Error in processFrame:', error);
                    setTimeout(processFrame, 500);
                }
            }
            
            processFrame();
        }
        
        function manualCapture() {
            if (!ws || ws.readyState !== WebSocket.OPEN) {
                updateMessage('Not connected to server', 'error');
                return;
            }
            
            ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
            const imageData = canvas.toDataURL('image/jpeg', 0.9);
            const base64Data = imageData.split(',')[1];
            
            ws.send(JSON.stringify({
                type: 'capture',
                image: base64Data
            }));
        }
    </script>
</body>
</html>
    """
    return HTMLResponse(content=html_content)


if __name__ == "__main__":
    # Run server
    # Use 0.0.0.0 to allow connections from network
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=False,
        log_level="info"
    )

