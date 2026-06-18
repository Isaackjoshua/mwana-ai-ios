import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Converts a raw image file into a Float32List tensor for the ONNX model.
///
/// Pipeline (matches validate_mobile.py exactly):
///   1. Decode JPEG/PNG → RGB image
///   2. Resize to 256×256 (bilinear)
///   3. Normalise: (pixel/255 - mean) / std per channel
///   4. Reorder to CHW layout: [R-plane 256×256, G-plane, B-plane]
class ImagePreprocessor {
  static const int inputSize = 256;

  // ImageNet normalisation — do not change without model revalidation.
  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std  = [0.229, 0.224, 0.225];

  /// Loads and decodes image from [filePath].
  /// Throws [ArgumentError] if the file cannot be decoded.
  Future<img.Image> loadImage(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw ArgumentError('Cannot decode image: $filePath');
    return decoded;
  }

  /// Resizes [source] to 256×256 using bilinear interpolation.
  img.Image resizeImage(img.Image source) {
    return img.copyResize(
      source,
      width: inputSize,
      height: inputSize,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Returns a horizontal mirror of [source] without modifying [source].
  img.Image horizontalFlip(img.Image source) {
    return img.flipHorizontal(img.Image.from(source));
  }

  /// Converts [image] (any size) to a Float32List tensor with CHW layout.
  /// Total elements: 3 × 256 × 256 = 196 608.
  Float32List imageToTensor(img.Image image) {
    final resized = (image.width == inputSize && image.height == inputSize)
        ? image
        : resizeImage(image);

    final tensor = Float32List(3 * inputSize * inputSize);
    const rOffset = 0;
    const gOffset = inputSize * inputSize;
    const bOffset = 2 * inputSize * inputSize;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final idx = y * inputSize + x;
        tensor[rOffset + idx] = (pixel.r / 255.0 - _mean[0]) / _std[0];
        tensor[gOffset + idx] = (pixel.g / 255.0 - _mean[1]) / _std[1];
        tensor[bOffset + idx] = (pixel.b / 255.0 - _mean[2]) / _std[2];
      }
    }
    return tensor;
  }

  /// Full preprocessing for inference: load → resize → tensor + H-flip tensor.
  ///
  /// Returns a record with [original] tensor, [flipped] tensor, and the
  /// decoded [image] (for overlay rendering).
  Future<({Float32List original, Float32List flipped, img.Image image})>
      preprocessForInference(String filePath) async {
    final raw = await loadImage(filePath);
    final resized = resizeImage(raw);
    final flippedImg = horizontalFlip(resized);
    return (
      original: imageToTensor(resized),
      flipped:  imageToTensor(flippedImg),
      image:    resized,
    );
  }
}
