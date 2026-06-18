// ignore_for_file: prefer_const_constructors
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/services/local_gemma_report_service.dart';
import 'package:mwana_ai/models/classification_result.dart';
import 'package:mwana_ai/models/segmentation_result.dart';
import 'package:mwana_ai/models/inference_result.dart';

void main() {
  final inferenceResult = InferenceResult(
    classification: ClassificationResult(
      predictedIndex: 1,
      probabilities: [0.10, 0.80, 0.10],
      biRads: BiRadsCategory.birads4b,
    ),
    segmentation: SegmentationResult(
      binaryMask: Float32List(256 * 256),
      diceScore: 0.72,
    ),
    originalImageBytes: Uint8List(0),
    latencyMs: 1200,
  );

  group('LocalGemmaReportService.buildPrompt', () {
    final svc = LocalGemmaReportService();

    test('prompt contains predicted class', () {
      expect(svc.buildPrompt(inferenceResult, null), contains('Malignant'));
    });

    test('prompt contains BI-RADS category label', () {
      expect(svc.buildPrompt(inferenceResult, null), contains('4B'));
    });

    test('prompt contains malignant probability', () {
      expect(svc.buildPrompt(inferenceResult, null), contains('80'));
    });

    test('prompt instructs model to output all 6 section headers', () {
      final p = svc.buildPrompt(inferenceResult, null);
      for (final h in ['CLINICAL INDICATION', 'FINDINGS',
                        'BI-RADS ASSESSMENT', 'IMPRESSION', 'RECOMMENDATION', 'DISCLAIMER']) {
        expect(p, contains(h));
      }
    });

    test('prompt does NOT include TECHNIQUE section header', () {
      expect(svc.buildPrompt(inferenceResult, null), isNot(contains('TECHNIQUE:')));
    });

    test('prompt requests detailed ACR BI-RADS findings descriptor', () {
      final p = svc.buildPrompt(inferenceResult, null);
      expect(p, contains('echo pattern'));
      expect(p, contains('margin'));
      expect(p, contains('posterior acoustic'));
    });

    test('prompt does NOT reference an attached image', () {
      final p = svc.buildPrompt(inferenceResult, null);
      expect(p, isNot(contains('attached image')));
      expect(p, isNot(contains('attached overlay')));
    });
  });

  group('LocalGemmaReportService.parseResponse', () {
    final svc = LocalGemmaReportService();

    test('parses well-formed 5-section response', () {
      const raw = '''
CLINICAL INDICATION: Breast lump evaluation.
FINDINGS: A hypoechoic, irregular mass with spiculated margins and posterior shadowing is identified.
BI-RADS ASSESSMENT: Category 4B.
IMPRESSION: Suspicious lesion.
RECOMMENDATION: Tissue biopsy recommended.
DISCLAIMER: AI-assisted only.
''';
      final r = svc.parseResponse(raw);
      expect(r.clinicalIndication, contains('Breast lump'));
      expect(r.findings, contains('hypoechoic'));
      expect(r.biRadsAssessment, contains('4B'));
      expect(r.recommendation, contains('biopsy'));
    });

    test('handles missing sections gracefully', () {
      const raw = 'FINDINGS: Hypoechoic mass.';
      final r = svc.parseResponse(raw);
      expect(r.clinicalIndication, isNotEmpty);
      expect(r.findings, contains('Hypoechoic'));
    });
  });

  group('LocalGemmaReportService.generateReport fallback', () {
    test('returns template report when model is not installed', () async {
      final svc = LocalGemmaReportService();
      // No model in test env — getActiveModel() throws → template fallback
      final r = await svc.generateReport(result: inferenceResult);
      expect(r.clinicalIndication, isNotEmpty);
      expect(r.biRadsAssessment, isNotEmpty);
      expect(r.isAiGenerated, isFalse);
    });
  });
}
