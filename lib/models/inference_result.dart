import 'dart:typed_data';
import 'classification_result.dart';
import 'segmentation_result.dart';

/// Combined result of one full ONNX inference pass (classification + segmentation).
class InferenceResult {
  final ClassificationResult classification;
  final SegmentationResult segmentation;

  /// Original image file bytes (JPEG/PNG) — preserved for display and PDF embedding.
  final Uint8List originalImageBytes;

  /// Wall-clock inference latency in milliseconds.
  final int latencyMs;

  const InferenceResult({
    required this.classification,
    required this.segmentation,
    required this.originalImageBytes,
    required this.latencyMs,
  });
}
