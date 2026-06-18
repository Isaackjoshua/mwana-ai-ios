import 'package:flutter_gemma/flutter_gemma.dart';
import '../models/classification_result.dart';
import '../models/inference_result.dart';
import '../models/patient_context.dart';
import '../models/report_result.dart';

/// Generates BI-RADS clinical reports using the locally installed Gemma 4 model.
///
/// Falls back to a deterministic template if the model is unavailable.
class LocalGemmaReportService {
  static const int _maxTokens = 2048;

  static const String _systemInstruction =
      'You are a clinical AI assistant generating ACR BI-RADS structured '
      'ultrasound reports. Use only ACR BI-RADS 5th Edition lexicon. Do not '
      'speculate beyond the provided AI findings. Always end with a DISCLAIMER '
      'section stating: AI-ASSISTED REPORT - Not a clinical diagnosis. '
      'Requires review by a qualified radiologist.';

  /// Generates a structured BI-RADS report from [result] using on-device Gemma 4.
  ///
  /// Falls back to a template report on any model or inference error.
  Future<ReportResult> generateReport({
    required InferenceResult result,
    PatientContext? patient,
  }) async {
    try {
      final prompt = buildPrompt(result, patient);
      final model = await FlutterGemma.getActiveModel(maxTokens: _maxTokens);
      try {
        final chat = await model.createChat(
          systemInstruction: _systemInstruction,
        );
        await chat.addQueryChunk(Message.text(text: prompt, isUser: true));
        final response = await chat.generateChatResponse();
        final text = response is TextResponse ? response.token : '';
        return parseResponse(text);
      } finally {
        await model.close();
      }
    } catch (_) {
      return _templateReport(result);
    }
  }

  /// Builds the text-only structured findings prompt.
  ///
  /// All findings are expressed numerically — no image bytes required.
  String buildPrompt(InferenceResult result, PatientContext? patient) {
    final cls = result.classification;
    final benignPct  = (cls.benignProb    * 100).toStringAsFixed(1);
    final malignPct  = (cls.malignantProb * 100).toStringAsFixed(1);
    final normalPct  = (cls.normalProb    * 100).toStringAsFixed(1);

    final patientSection = (patient != null && patient.hasData)
        ? 'Patient: ${patient.patientName ?? "Not provided"}\n'
          'DOB: ${patient.dateOfBirth ?? "Not provided"}\n'
          'Exam Date: ${patient.examDate ?? "Not provided"}\n'
          'Side: ${patient.side ?? "Not specified"}\n'
          'Referring: ${patient.referringClinician ?? "Not provided"}\n'
        : 'Patient: Anonymous (no metadata provided)\n';

    return '$patientSection\n'
        'AI Model Findings (ResNet50 U-Net v10, ONNX FP32):\n'
        '- Classification: ${cls.predictedClass}\n'
        '- Confidence: Benign $benignPct%, Malignant $malignPct%, Normal $normalPct%\n'
        '- ${cls.biRads.label}\n'
        '- Segmentation: Lesion region identified and outlined by AI model.\n\n'
        'Generate a complete structured BI-RADS report with EXACTLY these section '
        'headers on their own lines:\n'
        'CLINICAL INDICATION:\n'
        'FINDINGS:\n'
        'For the FINDINGS section provide a comprehensive ACR BI-RADS 5th Edition '
        'description covering ALL of the following where applicable: '
        '(1) lesion shape (oval/round/irregular), '
        '(2) orientation (parallel/not parallel to skin), '
        '(3) margin (circumscribed, indistinct, angular, microlobulated, or spiculated), '
        '(4) echo pattern (anechoic, hyperechoic, complex cystic and solid, hypoechoic, '
        'isoechoic, or heterogeneous), '
        '(5) posterior acoustic features (no features, enhancement, shadowing, or combined), '
        '(6) calcifications if present, '
        '(7) associated features (architectural distortion, duct changes, skin thickening '
        'or retraction, edema, vascularity), '
        '(8) AI-model probability scores for context. '
        'Write in formal radiology prose.\n'
        'BI-RADS ASSESSMENT:\n'
        'IMPRESSION:\n'
        'RECOMMENDATION:\n'
        'DISCLAIMER:\n';
  }

  /// Parses the raw Gemma response into a [ReportResult].
  ReportResult parseResponse(String raw) {
    String extract(String sectionKey, String nextKey) {
      final pattern = RegExp(
        '$sectionKey:\\s*(.+?)(?=$nextKey:|\$)',
        dotAll: true,
        caseSensitive: false,
      );
      final match = pattern.firstMatch(raw);
      return match?.group(1)?.trim() ?? _fallbackSection(sectionKey);
    }

    return ReportResult(
      clinicalIndication: extract('CLINICAL INDICATION', 'FINDINGS'),
      findings:           extract('FINDINGS',            'BI-RADS ASSESSMENT'),
      biRadsAssessment:   extract('BI-RADS ASSESSMENT',  'IMPRESSION'),
      impression:         extract('IMPRESSION',          'RECOMMENDATION'),
      recommendation:     extract('RECOMMENDATION',      'DISCLAIMER'),
      isAiGenerated:      true,
    );
  }

  String _fallbackSection(String section) =>
      'Section not available. Please consult the referring radiologist.';

  ReportResult _templateReport(InferenceResult result) {
    final cls = result.classification;
    final conf = (cls.probabilities[cls.predictedIndex] * 100).toStringAsFixed(1);
    final benignPct   = (cls.benignProb    * 100).toStringAsFixed(1);
    final malignPct   = (cls.malignantProb * 100).toStringAsFixed(1);
    final normalPct   = (cls.normalProb    * 100).toStringAsFixed(1);
    return ReportResult(
      clinicalIndication: 'Breast ultrasound evaluation for AI-detected lesion. '
          'AI-assisted screening using ResNet50 U-Net v10 (ONNX FP32).',
      findings: 'AI analysis of the submitted breast ultrasound image identified '
          'a ${cls.predictedClass.toLowerCase()} lesion with $conf% model confidence '
          '(Benign: $benignPct%, Malignant: $malignPct%, Normal: $normalPct%). '
          'Segmentation overlay delineates the lesion boundary. '
          'Lesion morphology, margin characterisation, echo pattern, posterior acoustic '
          'features, and associated findings require formal evaluation by a qualified '
          'radiologist using ACR BI-RADS 5th Edition lexicon. '
          'No calcifications, skin thickening, or architectural distortion are inferred '
          'from the AI output alone.',
      biRadsAssessment: cls.biRads.label,
      impression: '${cls.biRads.label} — ${cls.predictedClass} finding detected by AI '
          'with $conf% confidence. Clinical correlation and radiologist review required.',
      recommendation: cls.biRads.recommendation,
      isAiGenerated: false,
    );
  }
}
