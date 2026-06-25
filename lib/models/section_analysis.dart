import 'dart:typed_data';
import 'inference_result.dart';

/// Result of analysing one section (quadrant) of a breast ultrasound examination.
class SectionAnalysis {
  /// 0-based index in the capture sequence.
  final int sectionIndex;
  final InferenceResult result;

  /// PNG-encoded segmentation overlay with bounding box, or null if rendering failed.
  final Uint8List? overlayBytes;

  /// PNG-encoded jet-colourmap heatmap (Grad-CAM-style probability map).
  final Uint8List? heatmapBytes;

  const SectionAnalysis({
    required this.sectionIndex,
    required this.result,
    this.overlayBytes,
    this.heatmapBytes,
  });
}
