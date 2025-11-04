import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image/image.dart' as img;

/// Widget for editing captured card images with crop and rotate functionality
class ImageEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final Function(Uint8List editedImage) onSave;
  final VoidCallback onCancel;

  const ImageEditor({
    Key? key,
    required this.imageBytes,
    required this.onSave,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<ImageEditor> createState() => _ImageEditorState();
}

class _ImageEditorState extends State<ImageEditor> {
  final CropController _cropController = CropController();
  late Uint8List _currentImageBytes;
  int _rotation = 0;
  Uint8List? _croppedImage;

  @override
  void initState() {
    super.initState();
    _currentImageBytes = widget.imageBytes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Image'),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right),
            onPressed: _rotateImage,
            tooltip: 'Rotate 90°',
          ),
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _saveEditedImage,
            tooltip: 'Save',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              image: _currentImageBytes,
              controller: _cropController,
              onCropped: (image) {
                // Store cropped image whenever crop changes
                setState(() {
                  _croppedImage = image;
                });
              },
              initialSize: 0.8,
              withCircleUi: false,
              baseColor: Colors.blue.shade900,
              radius: 20,
              aspectRatio: 856 / 540, // ID card aspect ratio
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.cancel),
                  label: const Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _saveEditedImage,
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _rotateImage() {
    setState(() {
      _rotation = (_rotation + 90) % 360;
      _currentImageBytes = _applyRotation(_currentImageBytes, 90);
      _croppedImage = null; // Reset crop after rotation
    });
  }

  Uint8List _applyRotation(Uint8List imageBytes, int degrees) {
    try {
      // Decode image
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) return imageBytes;

      // Rotate image
      img.Image rotated;
      switch (degrees) {
        case 90:
          rotated = img.copyRotate(image, angle: 90);
          break;
        case 180:
          rotated = img.copyRotate(image, angle: 180);
          break;
        case 270:
          rotated = img.copyRotate(image, angle: 270);
          break;
        default:
          rotated = image;
      }

      // Encode back to bytes
      return Uint8List.fromList(img.encodeJpg(rotated));
    } catch (e) {
      print('Error rotating image: $e');
      return imageBytes;
    }
  }

  void _saveEditedImage() async {
    try {
      Uint8List finalImage;

      // Get the current cropped image
      // The onCropped callback should have been called if user interacted with crop
      if (_croppedImage != null) {
        finalImage = _croppedImage!;
      } else {
        // Use original if no crop interaction happened
        // But try to get current crop state from controller if possible
        finalImage = _currentImageBytes;
      }

      // Apply rotation if needed
      if (_rotation != 0) {
        finalImage = _applyRotation(finalImage, _rotation);
      }

      widget.onSave(finalImage);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving image: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    // CropController doesn't need dispose in newer versions
    super.dispose();
  }
}
