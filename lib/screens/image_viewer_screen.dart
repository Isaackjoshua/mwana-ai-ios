import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Full-screen pinch-to-zoom viewer for a segmentation overlay image.
///
/// Entry point for examining the AI-annotated image, tumour boundary,
/// and (in a future update) attention heatmap.
class ImageViewerScreen extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;

  const ImageViewerScreen({
    super.key,
    required this.imageBytes,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontSize: 15)),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 8.0,
              child: Center(
                child: Image.memory(imageBytes, fit: BoxFit.contain),
              ),
            ),
          ),
          Container(
            color: Colors.grey.shade900,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.pinch, size: 14, color: Colors.white54),
                SizedBox(width: 6),
                Text(
                  'Pinch to zoom  ·  Drag to pan',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
