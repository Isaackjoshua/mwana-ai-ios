/// BI-RADS category assigned from model output per PRD FR-09.
enum BiRadsCategory {
  birads1,   // Normal — Negative
  birads2,   // Benign — Benign Finding (≥80%)
  birads3,   // Benign — Probably Benign (50–80%)
  birads4a,  // Malignant — Low Suspicion (50–70%)
  birads4b,  // Malignant — Intermediate Suspicion (70–85%)
  birads4c5, // Malignant — High Suspicion (≥85%)
}

extension BiRadsCategoryExt on BiRadsCategory {
  /// Severity ordinal: higher = more suspicious (birads1=0 … birads4c5=5).
  int get ordinal {
    const order = [
      BiRadsCategory.birads1,
      BiRadsCategory.birads2,
      BiRadsCategory.birads3,
      BiRadsCategory.birads4a,
      BiRadsCategory.birads4b,
      BiRadsCategory.birads4c5,
    ];
    return order.indexOf(this);
  }

  String get label {
    switch (this) {
      case BiRadsCategory.birads1:   return 'BI-RADS 1 — Negative';
      case BiRadsCategory.birads2:   return 'BI-RADS 2 — Benign';
      case BiRadsCategory.birads3:   return 'BI-RADS 3 — Probably Benign';
      case BiRadsCategory.birads4a:  return 'BI-RADS 4A — Low Suspicion';
      case BiRadsCategory.birads4b:  return 'BI-RADS 4B — Intermediate Suspicion';
      case BiRadsCategory.birads4c5: return 'BI-RADS 4C–5 — High Suspicion';
    }
  }

  String get recommendation {
    switch (this) {
      case BiRadsCategory.birads1:   return 'Routine annual screening.';
      case BiRadsCategory.birads2:   return 'Routine annual screening.';
      case BiRadsCategory.birads3:   return 'Short-interval (6-month) follow-up.';
      case BiRadsCategory.birads4a:  return 'Tissue sampling should be considered.';
      case BiRadsCategory.birads4b:  return 'Tissue sampling recommended.';
      case BiRadsCategory.birads4c5: return 'Biopsy strongly recommended.';
    }
  }
}

/// Classification output from the ONNX model after postprocessing.
class ClassificationResult {
  /// Index of the predicted class: 0=benign, 1=malignant, 2=normal.
  final int predictedIndex;

  /// Softmax probabilities in order [benign, malignant, normal].
  final List<double> probabilities;

  /// BI-RADS category assigned by BiRadsService.
  final BiRadsCategory biRads;

  const ClassificationResult({
    required this.predictedIndex,
    required this.probabilities,
    required this.biRads,
  });

  String get predictedClass {
    const labels = ['Benign', 'Malignant', 'Normal'];
    if (predictedIndex < 0 || predictedIndex >= labels.length) return 'Unknown';
    return labels[predictedIndex];
  }

  double get benignProb    => probabilities[0];
  double get malignantProb => probabilities[1];
  double get normalProb    => probabilities[2];
}
