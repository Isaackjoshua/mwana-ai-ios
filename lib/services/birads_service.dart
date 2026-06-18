import '../models/classification_result.dart';

/// Maps ONNX model output to an ACR BI-RADS category per PRD FR-09.
///
/// Class indices: 0 = benign, 1 = malignant, 2 = normal.
class BiRadsService {
  /// Returns the BI-RADS category for [predictedIndex] and [probabilities].
  /// [probabilities] order: [benign, malignant, normal].
  BiRadsCategory assignBiRads({
    required int predictedIndex,
    required List<double> probabilities,
  }) {
    if (predictedIndex == 2) {
      return BiRadsCategory.birads1; // Normal
    }

    if (predictedIndex == 0) {
      // Benign
      return probabilities[0] >= 0.80
          ? BiRadsCategory.birads2
          : BiRadsCategory.birads3;
    }

    // Malignant (predictedIndex == 1)
    final malignantProb = probabilities[1];
    if (malignantProb >= 0.85) return BiRadsCategory.birads4c5;
    if (malignantProb >= 0.70) return BiRadsCategory.birads4b;
    return BiRadsCategory.birads4a;
  }
}
