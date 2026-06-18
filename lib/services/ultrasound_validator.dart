import 'dart:math' as math;
import 'package:image/image.dart' as img;

class UltrasoundValidationResult {
  final bool isValid;
  final String? reason;

  const UltrasoundValidationResult._valid()
      : isValid = true,
        reason = null;

  const UltrasoundValidationResult._invalid(this.reason) : isValid = false;

  static const UltrasoundValidationResult valid =
      UltrasoundValidationResult._valid();

  static UltrasoundValidationResult invalid(String reason) =>
      UltrasoundValidationResult._invalid(reason);
}

/// Validates that an image is a breast ultrasound scan using pixel-level
/// heuristics:
///
/// 1. **Low colour saturation** — ultrasound images are greyscale (B-mode).
///    Average HSV saturation must be below [_maxAvgSaturation] (0.25 allows
///    for JPEG artefacts, colour Doppler overlays, and scanner annotations).
///
/// 2. **Dark background** — the scanner frame/background is dark.
///    At least [_minDarkPixelRatio] of pixels must have luminance below
///    [_darkLuminanceThreshold] (0.20 captures grey as well as black borders
///    and handles tightly-cropped scans with little visible frame).
///
/// Both checks operate on a 128×128 thumbnail for speed.
class UltrasoundValidator {
  static const double _maxAvgSaturation = 0.25;
  static const double _minDarkPixelRatio = 0.08;
  static const double _darkLuminanceThreshold = 0.20;
  static const int _thumbSize = 128;

  static UltrasoundValidationResult validateImage(img.Image source) {
    final thumb = img.copyResize(
      source,
      width: _thumbSize,
      height: _thumbSize,
      interpolation: img.Interpolation.average,
    );

    double totalSaturation = 0.0;
    int darkCount = 0;
    const total = _thumbSize * _thumbSize;

    for (int y = 0; y < _thumbSize; y++) {
      for (int x = 0; x < _thumbSize; x++) {
        final p = thumb.getPixel(x, y);
        final r = p.r / 255.0;
        final g = p.g / 255.0;
        final b = p.b / 255.0;

        final maxC = math.max(r, math.max(g, b));
        final minC = math.min(r, math.min(g, b));
        totalSaturation += maxC > 0 ? (maxC - minC) / maxC : 0.0;

        final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
        if (luminance < _darkLuminanceThreshold) darkCount++;
      }
    }

    final avgSaturation = totalSaturation / total;
    final darkRatio = darkCount / total;

    if (avgSaturation > _maxAvgSaturation) {
      return UltrasoundValidationResult.invalid(
        'This does not look like an ultrasound image. '
        'Please select a greyscale breast ultrasound scan '
        '(colour photographs are not accepted).',
      );
    }

    if (darkRatio < _minDarkPixelRatio) {
      return UltrasoundValidationResult.invalid(
        'This does not look like an ultrasound image. '
        'Ultrasound scans have a dark background — '
        'please select a valid breast ultrasound scan.',
      );
    }

    return UltrasoundValidationResult.valid;
  }
}
