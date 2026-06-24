import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/section_analysis.dart';
import '../services/onnx_inference_service.dart';
import '../services/overlay_renderer.dart';

/// Runs ONNX inference sequentially on every captured probe section and
/// navigates to /cumulative-report when all sections are complete.
class MultiAnalysisScreen extends StatefulWidget {
  final List<String> imagePaths;
  const MultiAnalysisScreen({super.key, required this.imagePaths});

  @override
  State<MultiAnalysisScreen> createState() => _MultiAnalysisScreenState();
}

class _MultiAnalysisScreenState extends State<MultiAnalysisScreen> {
  final _inferenceService = OnnxInferenceService();
  final _overlayRenderer = OverlayRenderer();

  int _currentIndex = 0;
  final List<SectionAnalysis> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _runAll();
  }

  Future<void> _runAll() async {
    for (int i = 0; i < widget.imagePaths.length; i++) {
      if (!mounted) return;
      setState(() => _currentIndex = i);

      try {
        final path = widget.imagePaths[i];
        final result = await _inferenceService.runInference(path);

        final raw = await img.decodeImageFile(path);
        Uint8List? overlayBytes;
        if (raw != null) {
          final rendered = _overlayRenderer.renderOverlay(
            originalImage: raw,
            binaryMask: result.segmentation.binaryMask,
            maskColor: result.classification.predictedIndex == 1
                ? img.ColorRgba8(220, 38, 38, 255)
                : img.ColorRgba8(20, 184, 166, 255),
            opacity: 0.5,
          );
          if (rendered.isNotEmpty) overlayBytes = rendered;
        }

        if (!mounted) return;
        setState(() => _results.add(SectionAnalysis(
              sectionIndex: i,
              result: result,
              overlayBytes: overlayBytes,
            )));
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = 'Section ${i + 1} failed: $e');
        return;
      }
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/cumulative-report',
      arguments: _results,
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imagePaths.length;
    final done = _results.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Analysing Sections')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _error != null ? _buildError() : _buildProgress(done, total),
        ),
      ),
    );
  }

  Widget _buildProgress(int done, int total) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'Analysing section ${_currentIndex + 1} of $total...',
          style: const TextStyle(fontSize: 18),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: total > 0 ? done / total : 0),
        const SizedBox(height: 8),
        Text('$done of $total complete',
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 32),
        const Text(
          'AI-ASSISTED — Not a clinical diagnosis.\nRequires radiologist review.',
          style: TextStyle(color: Colors.deepOrange, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 48),
        const SizedBox(height: 16),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Go Back'),
        ),
      ],
    );
  }
}
