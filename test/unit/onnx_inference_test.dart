import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/services/onnx_inference_service.dart';

void main() {
  group('OnnxInferenceService postprocessing', () {
    late OnnxInferenceService service;
    setUp(() => service = OnnxInferenceService());

    test('softmax sums to 1.0', () {
      final logits = Float32List.fromList([2.0, 1.0, 0.5]);
      final probs = service.softmax(logits);
      final sum = probs.reduce((a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-6));
    });

    test('softmax largest logit gets highest probability', () {
      final logits = Float32List.fromList([3.0, 1.0, 0.5]);
      final probs = service.softmax(logits);
      expect(probs[0], greaterThan(probs[1]));
      expect(probs[1], greaterThan(probs[2]));
    });

    test('sigmoid of 0.0 is 0.5', () {
      expect(service.sigmoid(0.0), closeTo(0.5, 1e-6));
    });

    test('sigmoid of large positive is close to 1.0', () {
      expect(service.sigmoid(10.0), closeTo(1.0, 1e-3));
    });

    test('malignant threshold override: if malignant prob >= 0.35 → class 1', () {
      final probs = [0.50, 0.40, 0.10];
      final predicted = service.applyMalignantThreshold(probs);
      expect(predicted, equals(1));
    });

    test('malignant threshold: below threshold uses argmax', () {
      final probs = [0.60, 0.30, 0.10];
      final predicted = service.applyMalignantThreshold(probs);
      expect(predicted, equals(0));
    });

    test('averageProbabilities returns element-wise mean', () {
      final a = [0.6, 0.3, 0.1];
      final b = [0.4, 0.5, 0.1];
      final avg = service.averageProbabilities(a, b);
      expect(avg[0], closeTo(0.5, 1e-9));
      expect(avg[1], closeTo(0.4, 1e-9));
      expect(avg[2], closeTo(0.1, 1e-9));
    });

    test('applySegThreshold converts 0.276 to 1.0 and 0.274 to 0.0', () {
      final mask = Float32List.fromList([0.274, 0.275, 0.276, 0.5, 0.0]);
      final binary = service.applySegThreshold(mask);
      expect(binary[0], equals(0.0));
      expect(binary[1], equals(1.0)); // exactly at threshold → include
      expect(binary[2], equals(1.0));
      expect(binary[3], equals(1.0));
      expect(binary[4], equals(0.0));
    });

    test('softmax is numerically stable with large logits', () {
      final logits = Float32List.fromList([1000.0, 999.0, 0.0]);
      final probs = service.softmax(logits);
      expect(probs.any((p) => p.isNaN), isFalse);
      expect(probs.reduce((a, b) => a + b), closeTo(1.0, 1e-6));
    });
  });
}
