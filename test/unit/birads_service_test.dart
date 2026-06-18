import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/services/birads_service.dart';
import 'package:mwana_ai/models/classification_result.dart';

void main() {
  group('BiRadsService.assignBiRads', () {
    late BiRadsService service;
    setUp(() => service = BiRadsService());

    test('normal (index 2) → BI-RADS 1', () {
      expect(
        service.assignBiRads(predictedIndex: 2, probabilities: [0.10, 0.10, 0.80]),
        equals(BiRadsCategory.birads1),
      );
    });

    test('benign ≥ 80% → BI-RADS 2', () {
      expect(
        service.assignBiRads(predictedIndex: 0, probabilities: [0.85, 0.10, 0.05]),
        equals(BiRadsCategory.birads2),
      );
    });

    test('benign exactly 80% → BI-RADS 2 (boundary)', () {
      expect(
        service.assignBiRads(predictedIndex: 0, probabilities: [0.80, 0.15, 0.05]),
        equals(BiRadsCategory.birads2),
      );
    });

    test('benign < 80% → BI-RADS 3', () {
      expect(
        service.assignBiRads(predictedIndex: 0, probabilities: [0.65, 0.20, 0.15]),
        equals(BiRadsCategory.birads3),
      );
    });

    test('malignant 50–70% → BI-RADS 4A', () {
      expect(
        service.assignBiRads(predictedIndex: 1, probabilities: [0.15, 0.60, 0.25]),
        equals(BiRadsCategory.birads4a),
      );
    });

    test('malignant 70–85% → BI-RADS 4B', () {
      expect(
        service.assignBiRads(predictedIndex: 1, probabilities: [0.10, 0.75, 0.15]),
        equals(BiRadsCategory.birads4b),
      );
    });

    test('malignant ≥ 85% → BI-RADS 4C–5', () {
      expect(
        service.assignBiRads(predictedIndex: 1, probabilities: [0.05, 0.90, 0.05]),
        equals(BiRadsCategory.birads4c5),
      );
    });

    test('malignant exactly 85% → BI-RADS 4C–5 (boundary)', () {
      expect(
        service.assignBiRads(predictedIndex: 1, probabilities: [0.08, 0.85, 0.07]),
        equals(BiRadsCategory.birads4c5),
      );
    });
  });
}
