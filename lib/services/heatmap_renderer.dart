import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Renders a continuous segmentation probability map as a jet-colourmap
/// heatmap blended over the original image.
///
/// The probability map is the raw sigmoid output from the U-Net decoder
/// (values 0.0–1.0 per pixel, 256×256) before the binary threshold is
/// applied. Rendering it with a thermal colourmap gives the examiner a
/// spatial "AI attention" view analogous to Grad-CAM.
///
/// Jet colourmap: blue (cold/low) → cyan → yellow → red (hot/high).
class HeatmapRenderer {
  /// Blends [probabilityMap] (256×256 Float32List) onto [originalImage]
  /// using bilinear upsampling and a jet colourmap.
  ///
  /// Pixels with probability < 0.08 are left unchanged (original shows
  /// through cleanly in areas the model ignores).
  /// Overlay opacity is capped at 0.78 so the original is always visible.
  ///
  /// Returns PNG-encoded bytes.
  Uint8List renderHeatmap({
    required img.Image originalImage,
    required Float32List probabilityMap,
  }) {
    const maskSize = 256;
    final w = originalImage.width;
    final h = originalImage.height;

    final upsampled = _bilinearUpsample(probabilityMap, maskSize, w, h);

    final output = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final v = upsampled[y * w + x].clamp(0.0, 1.0);
        final orig = originalImage.getPixel(x, y);

        if (v < 0.08) {
          output.setPixel(x, y, orig);
        } else {
          final heat = _jetColor(v);
          final alpha = (v * 0.78).clamp(0.0, 0.78);
          output.setPixel(
            x,
            y,
            img.ColorRgba8(
              _lerp(orig.r, heat.r, alpha).round().clamp(0, 255),
              _lerp(orig.g, heat.g, alpha).round().clamp(0, 255),
              _lerp(orig.b, heat.b, alpha).round().clamp(0, 255),
              255,
            ),
          );
        }
      }
    }

    return Uint8List.fromList(img.encodePng(output));
  }

  /// Bilinear upsampling from [srcSize]×[srcSize] → [dstW]×[dstH].
  Float32List _bilinearUpsample(
      Float32List src, int srcSize, int dstW, int dstH) {
    final out = Float32List(dstW * dstH);
    final sx = srcSize / dstW;
    final sy = srcSize / dstH;

    for (int y = 0; y < dstH; y++) {
      for (int x = 0; x < dstW; x++) {
        final fx = (x * sx).clamp(0, srcSize - 1.0);
        final fy = (y * sy).clamp(0, srcSize - 1.0);
        final x0 = fx.floor().clamp(0, srcSize - 1);
        final y0 = fy.floor().clamp(0, srcSize - 1);
        final x1 = (x0 + 1).clamp(0, srcSize - 1);
        final y1 = (y0 + 1).clamp(0, srcSize - 1);
        final dx = fx - x0;
        final dy = fy - y0;

        out[y * dstW + x] = src[y0 * srcSize + x0] * (1 - dx) * (1 - dy) +
            src[y0 * srcSize + x1] * dx * (1 - dy) +
            src[y1 * srcSize + x0] * (1 - dx) * dy +
            src[y1 * srcSize + x1] * dx * dy;
      }
    }
    return out;
  }

  /// Jet colourmap: blue → cyan → yellow → red.
  img.ColorRgba8 _jetColor(double v) {
    int r, g, b;
    if (v < 0.25) {
      r = 0;
      g = (v * 4 * 255).round();
      b = 255;
    } else if (v < 0.5) {
      r = 0;
      g = 255;
      b = ((1 - (v - 0.25) * 4) * 255).round();
    } else if (v < 0.75) {
      r = ((v - 0.5) * 4 * 255).round();
      g = 255;
      b = 0;
    } else {
      r = 255;
      g = ((1 - (v - 0.75) * 4) * 255).round();
      b = 0;
    }
    return img.ColorRgba8(
      r.clamp(0, 255),
      g.clamp(0, 255),
      b.clamp(0, 255),
      255,
    );
  }

  double _lerp(num a, num b, double t) => a + (b - a) * t;
}
