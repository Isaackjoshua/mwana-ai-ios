import 'package:flutter/material.dart';
import '../models/classification_result.dart';
import '../models/report_result.dart';
import '../models/section_analysis.dart';
import '../services/local_gemma_report_service.dart';
import '../widgets/confidence_bar_widget.dart';
import '../widgets/loading_overlay_widget.dart';
import 'image_viewer_screen.dart';

/// Shows per-section findings from a multi-section probe examination,
/// an overall worst-case BI-RADS assessment, and an editable cumulative report.
class CumulativeReportScreen extends StatefulWidget {
  final List<SectionAnalysis> sections;
  const CumulativeReportScreen({super.key, required this.sections});

  @override
  State<CumulativeReportScreen> createState() => _CumulativeReportScreenState();
}

class _CumulativeReportScreenState extends State<CumulativeReportScreen> {
  final _reportService = LocalGemmaReportService();

  ReportResult? _report;
  ReportResult? _originalReport;
  bool _loading = true;

  late final SectionAnalysis _worstSection;
  late final bool _allSectionsSameCategory;

  late TextEditingController _indicationCtrl;
  late TextEditingController _findingsCtrl;
  late TextEditingController _biRadsCtrl;
  late TextEditingController _impressionCtrl;
  late TextEditingController _recommendationCtrl;

  @override
  void initState() {
    super.initState();
    _worstSection = _findWorstSection();
    _allSectionsSameCategory = _checkAllSameCategory();
    _indicationCtrl = TextEditingController();
    _findingsCtrl = TextEditingController();
    _biRadsCtrl = TextEditingController();
    _impressionCtrl = TextEditingController();
    _recommendationCtrl = TextEditingController();
    _generateReport();
  }

  SectionAnalysis _findWorstSection() {
    return widget.sections.reduce((a, b) {
      final aOrd = a.result.classification.biRads.ordinal;
      final bOrd = b.result.classification.biRads.ordinal;
      if (aOrd != bOrd) return aOrd > bOrd ? a : b;
      // Tiebreak on malignant probability — higher value is more concerning.
      return a.result.classification.malignantProb >=
              b.result.classification.malignantProb
          ? a
          : b;
    });
  }

  /// True when every section shares the same BI-RADS category — in this
  /// case there is no meaningful "most concerning" section to highlight.
  bool _checkAllSameCategory() {
    if (widget.sections.length <= 1) return true;
    final firstOrd =
        widget.sections.first.result.classification.biRads.ordinal;
    return widget.sections
        .every((s) => s.result.classification.biRads.ordinal == firstOrd);
  }

  Future<void> _generateReport() async {
    final result = await _reportService.generateCumulativeReport(
        widget.sections.map((s) => s.result).toList());
    if (!mounted) return;
    _originalReport = result;
    _setReport(result);
    setState(() => _loading = false);
  }

  void _setReport(ReportResult r) {
    _indicationCtrl.dispose();
    _findingsCtrl.dispose();
    _biRadsCtrl.dispose();
    _impressionCtrl.dispose();
    _recommendationCtrl.dispose();
    _report = r;
    _indicationCtrl = TextEditingController(text: r.clinicalIndication);
    _findingsCtrl = TextEditingController(text: r.findings);
    _biRadsCtrl = TextEditingController(text: r.biRadsAssessment);
    _impressionCtrl = TextEditingController(text: r.impression);
    _recommendationCtrl = TextEditingController(text: r.recommendation);
  }

  ReportResult _currentReport() => ReportResult(
        clinicalIndication: _indicationCtrl.text,
        findings: _findingsCtrl.text,
        biRadsAssessment: _biRadsCtrl.text,
        impression: _impressionCtrl.text,
        recommendation: _recommendationCtrl.text,
        isAiGenerated: _report?.isAiGenerated ?? false,
      );

  @override
  Widget build(BuildContext context) {
    final n = widget.sections.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Cumulative Report — $n Section${n == 1 ? '' : 's'}'),
        actions: [
          if (_originalReport != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reset to AI version',
              onPressed: () => setState(() => _setReport(_originalReport!)),
            ),
        ],
      ),
      body: Stack(
        children: [
          if (_report != null) _buildContent(),
          if (_loading)
            const LoadingOverlayWidget(message: 'Generating cumulative report...'),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Disclaimer
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.orange.shade100,
          child: const Text(
            '⚠️ AI-ASSISTED — Not a clinical diagnosis. Requires radiologist review.',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),

        // Overall assessment
        _buildOverallBanner(),
        const SizedBox(height: 20),

        // Per-section cards
        Text('Section-by-Section Findings',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...widget.sections.asMap().entries.map(
              (e) => _buildSectionCard(e.key, e.value),
            ),
        const SizedBox(height: 20),

        // Editable cumulative report
        Text('Cumulative Clinical Report',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _editableSection('Clinical Indication', _indicationCtrl),
        _editableSection('Findings', _findingsCtrl),
        _editableSection('BI-RADS Assessment', _biRadsCtrl),
        _editableSection('Impression', _impressionCtrl),
        _editableSection('Recommendation', _recommendationCtrl),
        const SizedBox(height: 16),

        ElevatedButton.icon(
          onPressed: () => Navigator.pushNamed(
            context,
            '/export',
            arguments: {
              'inferenceResult': _worstSection.result,
              'reportResult': _currentReport(),
              'overlayBytes': _worstSection.overlayBytes,
            },
          ),
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Export PDF'),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildOverallBanner() {
    final cls = _worstSection.result.classification;
    final color = switch (cls.predictedIndex) {
      1 => Colors.red.shade700,
      0 => Colors.orange.shade700,
      _ => Colors.green.shade700,
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overall Assessment',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: color)),
          const SizedBox(height: 4),
          Text(cls.biRads.label,
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(
            _allSectionsSameCategory
                ? '${widget.sections.length} sections examined  ·  All sections similar'
                : '${widget.sections.length} sections examined  ·  '
                    'Most concerning: Section ${_worstSection.sectionIndex + 1}',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(int index, SectionAnalysis section) {
    final cls = section.result.classification;
    // Only highlight as "most concerning" when there's a genuine difference.
    final isWorst = section == _worstSection && !_allSectionsSameCategory;
    final color = switch (cls.predictedIndex) {
      1 => Colors.red,
      0 => Colors.orange,
      _ => Colors.green,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: isWorst
          ? RoundedRectangleBorder(
              side: BorderSide(color: color, width: 2),
              borderRadius: BorderRadius.circular(12),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Tappable thumbnail → full-screen overlay viewer
            GestureDetector(
              onTap: section.overlayBytes != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ImageViewerScreen(
                            imageBytes: section.overlayBytes!,
                            title:
                                'Section ${index + 1} — ${cls.predictedClass}',
                          ),
                        ),
                      )
                  : null,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: section.overlayBytes != null
                        ? Image.memory(section.overlayBytes!,
                            width: 64, height: 64, fit: BoxFit.cover)
                        : Container(
                            width: 64,
                            height: 64,
                            color: Colors.grey.shade200,
                            child:
                                const Icon(Icons.image, color: Colors.grey),
                          ),
                  ),
                  if (section.overlayBytes != null)
                    const Positioned(
                      bottom: 2,
                      right: 2,
                      child: Icon(Icons.zoom_in,
                          size: 14, color: Colors.white),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Section ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (isWorst) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Most Concerning',
                              style: TextStyle(
                                  color: Colors.white, fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(cls.predictedClass,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w600)),
                  Text(cls.biRads.label,
                      style: const TextStyle(
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  ...cls.sortedBars().map((b) => ConfidenceBarWidget(
                        label: b.label,
                        probability: b.probability,
                        isSelected: b.isPredicted,
                      )),
                  if (cls.isThresholdOverride)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 12, color: Colors.orange),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Malignant flagged via sensitivity threshold',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.orange),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editableSection(String title, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: null,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  void dispose() {
    _indicationCtrl.dispose();
    _findingsCtrl.dispose();
    _biRadsCtrl.dispose();
    _impressionCtrl.dispose();
    _recommendationCtrl.dispose();
    super.dispose();
  }
}
