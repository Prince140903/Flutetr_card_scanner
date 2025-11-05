import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import '../models/scan_result.dart';
import '../widgets/image_editor.dart';

/// Result screen displaying the captured and warped card image
class ResultScreen extends StatefulWidget {
  final ScanResult scanResult;

  const ResultScreen({
    Key? key,
    required this.scanResult,
  }) : super(key: key);

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _showOriginal = false;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final displayedImage = _showOriginal
        ? widget.scanResult.originalImage
        : widget.scanResult.warpedImage;

    if (displayedImage == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Result')),
        body: const Center(
          child: Text('No image available'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Captured Card'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Retake',
          ),
        ],
      ),
      body: Column(
        children: [
          // Image display
          Expanded(
            child: Center(
              child: InteractiveViewer(
                child: Image.memory(
                  displayedImage,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // Controls
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Toggle button
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: widget.scanResult.originalImage != null
                          ? () {
                              setState(() {
                                _showOriginal = !_showOriginal;
                              });
                            }
                          : null,
                      icon: Icon(
                        _showOriginal ? Icons.crop : Icons.image,
                      ),
                      label: Text(
                        _showOriginal ? 'Show Warped' : 'Show Original',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Edit button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _editImage(),
                        icon: const Icon(Icons.edit),
                        label: const Text('Edit'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Retake button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retake'),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Save button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveImage,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editImage() {
    final imageToEdit =
        widget.scanResult.warpedImage ?? widget.scanResult.originalImage;
    if (imageToEdit == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageEditor(
          imageBytes: imageToEdit,
          onSave: (editedImage) {
            setState(() {
              // Update the warped image with edited version
              widget.scanResult.warpedImage = editedImage;
              _showOriginal = false;
            });
          },
          onCancel: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _saveImage() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final imageToSave =
          widget.scanResult.warpedImage ?? widget.scanResult.originalImage;
      if (imageToSave == null) {
        throw Exception('No image to save');
      }

      // Request permission first
      if (!await Gal.hasAccess()) {
        await Gal.requestAccess();
      }

      // Generate filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'id_card_$timestamp.jpg';

      // Save image bytes directly to gallery
      await Gal.putImageBytes(imageToSave, name: filename);

      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image saved to gallery'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
