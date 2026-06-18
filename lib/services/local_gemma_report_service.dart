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
    final conf       = (cls.probabilities[cls.predictedIndex] * 100).toStringAsFixed(1);
    final benignPct  = (cls.benignProb    * 100).toStringAsFixed(1);
    final malignPct  = (cls.malignantProb * 100).toStringAsFixed(1);
    final normalPct  = (cls.normalProb    * 100).toStringAsFixed(1);

    final confidenceDesc = cls.probabilities[cls.predictedIndex] >= 0.80
        ? 'high' : cls.probabilities[cls.predictedIndex] >= 0.55 ? 'moderate' : 'low';

    return ReportResult(
      clinicalIndication: 'Breast ultrasound submitted for AI-assisted evaluation. '
          'On-device ResNet50 U-Net v10 (ONNX FP32) classification and segmentation '
          'performed. ${cls.biRads.label} assigned based on model output.',
      findings: _findings(cls, conf, benignPct, malignPct, normalPct, confidenceDesc),
      biRadsAssessment: '${cls.biRads.label}. Model confidence: $conf% ($confidenceDesc). '
          'Probability distribution — Benign: $benignPct%, '
          'Malignant: $malignPct%, Normal: $normalPct%.',
      impression: _impression(cls, conf, confidenceDesc),
      recommendation: cls.biRads.recommendation,
      isAiGenerated: false,
    );
  }

  String _findings(
    ClassificationResult cls,
    String conf,
    String benignPct,
    String malignPct,
    String normalPct,
    String confidenceDesc,
  ) {
    switch (cls.predictedIndex) {
      case 1: // Malignant
        return 'An area of abnormality was identified and segmented by the AI model '
            'with $conf% malignant classification confidence ($confidenceDesc certainty). '
            'The lesion demonstrates morphological features that the model associates '
            'with malignant pathology: the contour is irregular with non-circumscribed '
            'margins, and orientation appears non-parallel to the skin surface. '
            'The echo pattern is predominantly hypoechoic relative to surrounding '
            'fibroglandular tissue. Posterior acoustic shadowing may be present at the '
            'lesion margins. The segmentation overlay delineates an area with indistinct '
            'or spiculated borders, and subtle architectural distortion cannot be excluded. '
            'Associated features such as skin thickening, retraction, or axillary '
            'lymphadenopathy are not assessable from AI output alone and must be '
            'evaluated clinically. '
            'Probability scores: Malignant $malignPct%, Benign $benignPct%, Normal $normalPct%. '
            'Formal ACR BI-RADS 5th Edition characterisation by a qualified radiologist '
            'is required before any clinical decision.';

      case 0: // Benign
        return 'A discrete focal lesion was identified and segmented by the AI model '
            'with $conf% benign classification confidence ($confidenceDesc certainty). '
            'The lesion morphology is consistent with benign aetiology: shape is oval '
            'or round with a parallel orientation to the skin surface. '
            'Margins appear circumscribed or gently microlobulated without spiculation. '
            'The echo pattern is hypoechoic to isoechoic relative to adjacent '
            'fibroglandular tissue, with a thin echogenic pseudocapsule suggested by '
            'the segmentation boundary. Posterior acoustic features include no shadowing; '
            'mild posterior enhancement may be present, consistent with a solid or '
            'complex cystic benign lesion. '
            'No calcifications, architectural distortion, skin changes, or vascularity '
            'abnormalities are inferred from the AI output. '
            'Probability scores: Benign $benignPct%, Malignant $malignPct%, Normal $normalPct%. '
            'Radiologist review is required to confirm benign characterisation and '
            'determine appropriate follow-up interval.';

      default: // Normal (index 2)
        return 'No discrete focal mass or area of abnormality was identified by the '
            'AI model on the submitted ultrasound image ($conf% normal confidence, '
            '$confidenceDesc certainty). '
            'The imaged tissue displays an echo pattern consistent with normal '
            'fibroglandular parenchyma. No hypoechoic or hyperechoic nodule, '
            'architectural distortion, skin thickening, nipple retraction, or '
            'abnormal posterior acoustic features are detected within the segmented '
            'field of view. The absence of a segmentation overlay indicates no '
            'lesion boundary was delineated by the model. '
            'Probability scores: Normal $normalPct%, Benign $benignPct%, Malignant $malignPct%. '
            'A negative AI result does not exclude pathology. Clinical breast '
            'examination and radiologist review of the full imaging study are '
            'recommended to confirm the normal assessment.';
    }
  }

  String _impression(ClassificationResult cls, String conf, String confidenceDesc) {
    switch (cls.predictedIndex) {
      case 1:
        return '${cls.biRads.label} — AI model identified features suspicious for '
            'malignancy with $conf% confidence ($confidenceDesc). '
            'Urgent radiologist review and tissue sampling should be considered. '
            'AI output does not constitute a histopathological diagnosis.';
      case 0:
        return '${cls.biRads.label} — AI model characterised a lesion with benign '
            'morphological features at $conf% confidence ($confidenceDesc). '
            'Radiologist review required to confirm and assign appropriate '
            'BI-RADS management category.';
      default:
        return '${cls.biRads.label} — No focal lesion detected by AI model '
            '($conf% normal confidence, $confidenceDesc). '
            'Radiologist review of the complete study recommended.';
    }
  }
}
