// ignore_for_file: avoid_print
/// Standalone visual test for HeatmapRenderer and OverlayRenderer.
///
/// Run with:  dart run tool/test_heatmap.dart
///
/// Outputs three PNG files to /tmp/:
///   mwana_original.png    — synthetic ultrasound image
///   mwana_bbox.png        — segmentation overlay with bounding box
///   mwana_heatmap.png     — jet-colourmap heatmap
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:mwana_ai/services/overlay_renderer.dart';
import 'package:mwana_ai/services/heatmap_renderer.dart';

void main() async {
  print('Building synthetic ultrasound image...');
  final original = _buildUltrasoundImage(width: 480, height: 360);

  print('Building probability map (Gaussian hotspot)...');
  final probMap = _buildProbabilityMap();

  print('Rendering bounding-box overlay...');
  final overlayRenderer = OverlayRenderer();
  final binaryMask = _threshold(probMap, 0.275);
  final bboxBytes = overlayRenderer.renderOverlay(
    originalImage: original,
    binaryMask: binaryMask,
    maskColor: img.ColorRgba8(220, 38, 38, 255), // red (malignant)
    opacity: 0.5,
  );

  print('Rendering heatmap...');
  final heatmapRenderer = HeatmapRenderer();
  final heatmapBytes = heatmapRenderer.renderHeatmap(
    originalImage: original,
    probabilityMap: probMap,
  );

  final originalBytes = Uint8List.fromList(img.encodePng(original));

  final outDir = '/tmp';
  File('$outDir/mwana_original.png').writeAsBytesSync(originalBytes);
  File('$outDir/mwana_bbox.png').writeAsBytesSync(bboxBytes);
  File('$outDir/mwana_heatmap.png').writeAsBytesSync(heatmapBytes);

  print('');
  print('Output files:');
  print('  /tmp/mwana_original.png   (${_kb(originalBytes)} KB)');
  print('  /tmp/mwana_bbox.png       (${_kb(bboxBytes)} KB)');
  print('  /tmp/mwana_heatmap.png    (${_kb(heatmapBytes)} KB)');
  print('');
  print('Done.');
}

// ── Synthetic ultrasound image ────────────────────────────────────────────────

img.Image _buildUltrasoundImage({required int width, required int height}) {
  final rng = math.Random(42);
  final image = img.Image(width: width, height: height);

  // Dark background with ultrasound speckle noise
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      // Base tissue brightness gradient (top darker → bottom slightly lighter)
      final base = 18 + (y / height * 20).round();
      // Speckle: random high-frequency noise characteristic of ultrasound
      final speckle = (rng.nextDouble() * 35).round();
      int v = (base + speckle).clamp(0, 255);

      // Simulate a brighter tissue region (fibroglandular) in the centre-left
      final cx = width * 0.4;
      final cy = height * 0.5;
      final dist = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
      if (dist < width * 0.28) {
        v = (v + 25 + (rng.nextDouble() * 20).round()).clamp(0, 255);
      }

      // Simulate a hypoechoic (dark) lesion in the upper-right area
      // This is where the probability map hotspot will sit.
      final lx = width * 0.67;
      final ly = height * 0.38;
      final ldist = math.sqrt(math.pow(x - lx, 2) + math.pow(y - ly, 2));
      if (ldist < width * 0.09) {
        v = (v * 0.45).round().clamp(0, 255); // significantly darker
      }

      image.setPixel(x, y, img.ColorRgb8(v, v, v));
    }
  }

  return image;
}

// ── Probability map: Gaussian hotspot matching the lesion location ────────────

Float32List _buildProbabilityMap() {
  const size = 256;
  // Centre of hotspot in 256×256 mask space — aligns with the dark lesion
  // in the synthetic image (upper-right, ~67% x, ~38% y).
  const cx = 0.67 * size;
  const cy = 0.38 * size;
  const sigma = 22.0; // spread

  final map = Float32List(size * size);
  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final d2 = math.pow(x - cx, 2) + math.pow(y - cy, 2);
      // Primary hotspot
      double v = math.exp(-d2 / (2 * sigma * sigma));
      // A secondary weaker hotspot nearby (realistic — model often sees
      // multiple suspicious sub-regions)
      final d2b =
          math.pow(x - cx - 18, 2) + math.pow(y - cy + 14, 2);
      v = math.max(v, 0.45 * math.exp(-d2b / (2 * 14.0 * 14.0)));
      map[y * size + x] = v.clamp(0.0, 1.0);
    }
  }
  return map;
}

// ── Threshold probability map → binary mask ──────────────────────────────────

Float32List _threshold(Float32List map, double thresh) {
  final out = Float32List(map.length);
  for (int i = 0; i < map.length; i++) {
    out[i] = map[i] >= thresh ? 1.0 : 0.0;
  }
  return out;
}

String _kb(List<int> bytes) => (bytes.length / 1024).toStringAsFixed(1);
