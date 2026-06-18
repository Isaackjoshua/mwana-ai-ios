import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/services/pdf_export_service.dart';
import 'package:mwana_ai/models/classification_result.dart';
import 'package:mwana_ai/models/segmentation_result.dart';
import 'package:mwana_ai/models/inference_result.dart';
import 'package:mwana_ai/models/report_result.dart';

void main() {
  group('PdfExportService', () {
    test('exported PDF bytes are non-empty', () async {
      final service = PdfExportService();
      final pdfBytes = await service.generatePdf(
        inferenceResult: _mockInference(),
        reportResult: _mockReport(),
        patient: null,
        overlayImageBytes: Uint8List(0),
      );
      expect(pdfBytes.length, greaterThan(0));
    });

    test('PDF bytes start with %PDF magic bytes', () async {
      final service = PdfExportService();
      final pdfBytes = await service.generatePdf(
        inferenceResult: _mockInference(),
        reportResult: _mockReport(),
        patient: null,
        overlayImageBytes: Uint8List(0),
      );
      final header = String.fromCharCodes(pdfBytes.sublist(0, 4));
      expect(header, equals('%PDF'));
    });
  });
}

InferenceResult _mockInference() => InferenceResult(
  classification: const ClassificationResult(
    predictedIndex: 0,
    probabilities: [0.85, 0.10, 0.05],
    biRads: BiRadsCategory.birads2,
  ),
  segmentation: SegmentationResult(
    binaryMask: Float32List(256 * 256),
    diceScore: 0.0,
  ),
  originalImageBytes: Uint8List(0),
  latencyMs: 500,
);

ReportResult _mockReport() => ReportResult(
  clinicalIndication: 'Test.',
  findings: 'Benign. Oval, parallel orientation, circumscribed margin, hypoechoic echo pattern, no posterior features.',
  biRadsAssessment: 'BI-RADS 2',
  impression: 'Benign.',
  recommendation: 'Annual screening.',
  isAiGenerated: false,
);
