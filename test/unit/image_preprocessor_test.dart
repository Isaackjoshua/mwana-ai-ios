import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mwana_ai/services/image_preprocessor.dart';

void main() {
  group('ImagePreprocessor', () {
    late ImagePreprocessor preprocessor;

    setUp(() => preprocessor = ImagePreprocessor());

    test('output tensor has 196608 elements (1 × 3 × 256 × 256)', () {
      final image = img.Image(width: 300, height: 200);
      img.fill(image, color: img.ColorRgb8(128, 64, 32));
      final tensor = preprocessor.imageToTensor(image);
      expect(tensor.length, equals(196608));
    });

    test('normalisation: pure-white pixel R channel ≈ 2.2489', () {
      final image = img.Image(width: 10, height: 10);
      img.fill(image, color: img.ColorRgb8(255, 255, 255));
      final tensor = preprocessor.imageToTensor(image);
      expect(tensor[0], closeTo((1.0 - 0.485) / 0.229, 0.01));
    });

    test('normalisation: pure-black pixel R channel ≈ -2.1179', () {
      final image = img.Image(width: 10, height: 10);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));
      final tensor = preprocessor.imageToTensor(image);
      expect(tensor[0], closeTo((0.0 - 0.485) / 0.229, 0.01));
    });

    test('horizontalFlip reverses pixel order per row', () {
      final image = img.Image(width: 4, height: 2);
      image.setPixelRgb(0, 0, 255, 0, 0);
      image.setPixelRgb(3, 0, 0, 0, 255);
      final flipped = preprocessor.horizontalFlip(image);
      final p00 = flipped.getPixel(0, 0);
      final p30 = flipped.getPixel(3, 0);
      expect(p00.r.toInt(), closeTo(0, 2));
      expect(p00.b.toInt(), closeTo(255, 2));
      expect(p30.r.toInt(), closeTo(255, 2));
      expect(p30.b.toInt(), closeTo(0, 2));
    });

    test('preprocessForInference returns both original and flipped tensors', () async {
      // Use a non-uniform PNG (lossless) so original and flipped tensors differ.
      final testImage = img.Image(width: 100, height: 80);
      // Left half red, right half blue — clearly asymmetric.
      for (int y = 0; y < 80; y++) {
        for (int x = 0; x < 100; x++) {
          if (x < 50) {
            testImage.setPixelRgb(x, y, 255, 0, 0);
          } else {
            testImage.setPixelRgb(x, y, 0, 0, 255);
          }
        }
      }
      final pngBytes = img.encodePng(testImage);
      final dir = await Directory.systemTemp.createTemp('bai_test_');
      addTearDown(() async => dir.delete(recursive: true));
      final file = File('${dir.path}/preprocess_test.png');
      await file.writeAsBytes(pngBytes);

      final result = await preprocessor.preprocessForInference(file.path);
      expect(result.original.length, equals(196608));
      expect(result.flipped.length, equals(196608));
      expect(result.original, isNot(equals(result.flipped)));
    });
  });
}
