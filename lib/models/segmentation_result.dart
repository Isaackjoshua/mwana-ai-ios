import 'dart:typed_data';

/// Segmentation output from the ONNX model after postprocessing.
class SegmentationResult {
  /// Binary mask as flat Float32List, row-major, 256×256.
  /// Values are 0.0 (background) or 1.0 (lesion) after the seg threshold.
  final Float32List binaryMask;

  /// Continuous sigmoid probability map (256×256) before thresholding.
  /// Values 0.0–1.0 represent the model's per-pixel lesion confidence.
  /// Used by HeatmapRenderer to produce the Grad-CAM-style heatmap view.
  final Float32List probabilityMap;

  /// RGBA PNG bytes of the coloured overlay rendered on the original image.
  final Uint8List? overlayImageBytes;

  /// Dice coefficient (0.0–1.0) from the averaged sigmoid outputs.
  final double diceScore;

  SegmentationResult({
    required this.binaryMask,
    Float32List? probabilityMap,
    this.overlayImageBytes,
    required this.diceScore,
  }) : probabilityMap = probabilityMap ?? Float32List(maskSize * maskSize);

  /// Width and height of the mask (always 256 from the ONNX model).
  static const int maskSize = 256;
}
