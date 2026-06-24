import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/classification_result.dart';
import '../models/inference_result.dart';
import '../services/onnx_inference_service.dart';
import '../services/overlay_renderer.dart';
import '../widgets/confidence_bar_widget.dart';
import '../widgets/loading_overlay_widget.dart';
import 'image_viewer_screen.dart';

class AnalysisScreen extends StatefulWidget {
  final String imagePath;
  const AnalysisScreen({super.key, required this.imagePath});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final _inferenceService = OnnxInferenceService();
  final _overlayRenderer = OverlayRenderer();

  InferenceResult? _result;
  Uint8List? _overlayBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runInference();
  }

  Future<void> _runInference() async {
    try {
      final result = await _inferenceService.runInference(widget.imagePath);

      final raw = await img.decodeImageFile(widget.imagePath);
      final overlayBytes = raw != null
          ? _overlayRenderer.renderOverlay(
              originalImage: raw,
              binaryMask: result.segmentation.binaryMask,
              maskColor: result.classification.predictedIndex == 1
                  ? img.ColorRgba8(220, 38, 38, 255)
                  : img.ColorRgba8(20, 184, 166, 255),
              opacity: 0.5,
            )
          : Uint8List(0);

      if (!mounted) return;
      setState(() {
        _result = result;
        _overlayBytes = overlayBytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Inference failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Results')),
      body: Stack(
        children: [
          if (_error != null)
            Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
          else if (_result != null)
            _buildResults()
          else
            const SizedBox.shrink(),
          if (_loading)
            const LoadingOverlayWidget(message: 'Running AI inference...'),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final cls = _result!.classification;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          color: Colors.orange.shade100,
          child: const Text(
            '⚠️ AI-ASSISTED — Not a clinical diagnosis. Requires radiologist review.',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        if (_overlayBytes != null && _overlayBytes!.isNotEmpty)
          _TappableImage(
            imageBytes: _overlayBytes!,
            title: 'Overlay — ${_result!.classification.predictedClass}',
          )
        else
          Image.file(File(widget.imagePath), height: 300, fit: BoxFit.contain),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cls.predictedClass,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(cls.biRads.label),
                const SizedBox(height: 16),
                ...cls.sortedBars().map((b) => ConfidenceBarWidget(
                      label: b.label,
                      probability: b.probability,
                      isSelected: b.isPredicted,
                    )),
                if (cls.isThresholdOverride) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: Colors.orange),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Malignant flagged via sensitivity threshold (≥35%). '
                            'Another class had higher raw probability — '
                            'always require radiologist review.',
                            style:
                                TextStyle(fontSize: 11, color: Colors.orange),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            '/report',
            arguments: {
              'inferenceResult': _result,
              'overlayBytes': _overlayBytes,
            },
          ),
          icon: const Icon(Icons.description),
          label: const Text('Generate Report'),
        ),
      ],
    );
  }
}

/// Overlay image that opens a full-screen viewer on tap.
class _TappableImage extends StatelessWidget {
  final Uint8List imageBytes;
  final String title;

  const _TappableImage({required this.imageBytes, required this.title});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ImageViewerScreen(imageBytes: imageBytes, title: title),
        ),
      ),
      child: Stack(
        alignment: Alignment.bottomRight,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(imageBytes, height: 300, fit: BoxFit.contain),
          ),
          Container(
            margin: const EdgeInsets.all(8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.zoom_in, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text('Tap to examine',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
