import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Renders a coloured segmentation overlay on the original image.
class OverlayRenderer {
  /// Renders [binaryMask] (256×256 Float32List, values 0.0 or 1.0) as a
  /// semi-transparent coloured overlay on [originalImage].
  ///
  /// [maskColor]: RGBA colour for positive mask pixels.
  /// [opacity]: 0.0–1.0 overlay opacity (default 0.5).
  ///
  /// Returns PNG-encoded bytes of the annotated image.
  Uint8List renderOverlay({
    required img.Image originalImage,
    required Float32List binaryMask,
    required img.Color maskColor,
    double opacity = 0.5,
  }) {
    const maskSize = 256;
    final w = originalImage.width;
    final h = originalImage.height;

    final upsampled = img.copyResize(
      _maskToImage(binaryMask, maskSize),
      width: w,
      height: h,
      interpolation: img.Interpolation.nearest,
    );

    final output = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final orig = originalImage.getPixel(x, y);
        final mask = upsampled.getPixel(x, y);
        final isMask = mask.r > 127;

        if (isMask) {
          final blended = img.ColorRgba8(
            (_lerp(orig.r, maskColor.r, opacity)).round(),
            (_lerp(orig.g, maskColor.g, opacity)).round(),
            (_lerp(orig.b, maskColor.b, opacity)).round(),
            255,
          );
          output.setPixel(x, y, blended);
        } else {
          output.setPixel(x, y, orig);
        }
      }
    }

    final bbox = _computeBoundingBox(binaryMask, maskSize, w, h);
    if (bbox != null) {
      img.drawRect(
        output,
        x1: bbox.$1, y1: bbox.$2, x2: bbox.$3, y2: bbox.$4,
        color: maskColor,
        thickness: 2,
      );
    }

    return Uint8List.fromList(img.encodePng(output));
  }

  /// Converts a [Float32List] binary mask to a grayscale [img.Image].
  img.Image _maskToImage(Float32List mask, int size) {
    final image = img.Image(width: size, height: size, numChannels: 1);
    for (int i = 0; i < mask.length; i++) {
      final x = i % size;
      final y = i ~/ size;
      final v = (mask[i] * 255).round();
      image.setPixelR(x, y, v);
    }
    return image;
  }

  double _lerp(num a, num b, double t) => a + (b - a) * t;

  /// Computes the bounding box of the positive mask pixels, scaled to
  /// the output image dimensions [outW] × [outH].
  /// Returns (x1, y1, x2, y2) or null if no positive pixels.
  (int, int, int, int)? _computeBoundingBox(
    Float32List mask, int maskSize, int outW, int outH,
  ) {
    int minX = maskSize, minY = maskSize, maxX = 0, maxY = 0;
    bool found = false;

    for (int i = 0; i < mask.length; i++) {
      if (mask[i] > 0.5) {
        final x = i % maskSize;
        final y = i ~/ maskSize;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
        found = true;
      }
    }

    if (!found) return null;

    final scaleX = outW / maskSize;
    final scaleY = outH / maskSize;
    return (
      (minX * scaleX).round().clamp(0, outW - 1),
      (minY * scaleY).round().clamp(0, outH - 1),
      (maxX * scaleX).round().clamp(0, outW - 1),
      (maxY * scaleY).round().clamp(0, outH - 1),
    );
  }
}
