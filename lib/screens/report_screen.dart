import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/inference_result.dart';
import '../models/report_result.dart';
import '../services/local_gemma_report_service.dart';
import '../widgets/loading_overlay_widget.dart';

class ReportScreen extends StatefulWidget {
  final InferenceResult inferenceResult;
  final Uint8List? overlayBytes;
  const ReportScreen({
    super.key,
    required this.inferenceResult,
    this.overlayBytes,
  });

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  final _reportService = LocalGemmaReportService();

  ReportResult? _report;
  ReportResult? _originalReport;
  bool _loading = true;

  late TextEditingController _indicationCtrl;
  late TextEditingController _findingsCtrl;
  late TextEditingController _biRadsCtrl;
  late TextEditingController _impressionCtrl;
  late TextEditingController _recommendationCtrl;

  @override
  void initState() {
    super.initState();
    _indicationCtrl     = TextEditingController();
    _findingsCtrl       = TextEditingController();
    _biRadsCtrl         = TextEditingController();
    _impressionCtrl     = TextEditingController();
    _recommendationCtrl = TextEditingController();
    _generateReport();
  }

  Future<void> _generateReport() async {
    final result = await _reportService.generateReport(
      result: widget.inferenceResult,
    );
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
    _indicationCtrl     = TextEditingController(text: r.clinicalIndication);
    _findingsCtrl       = TextEditingController(text: r.findings);
    _biRadsCtrl         = TextEditingController(text: r.biRadsAssessment);
    _impressionCtrl     = TextEditingController(text: r.impression);
    _recommendationCtrl = TextEditingController(text: r.recommendation);
  }

  ReportResult _currentReport() => ReportResult(
    clinicalIndication: _indicationCtrl.text,
    findings:           _findingsCtrl.text,
    biRadsAssessment:   _biRadsCtrl.text,
    impression:         _impressionCtrl.text,
    recommendation:     _recommendationCtrl.text,
    isAiGenerated:      _report?.isAiGenerated ?? false,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Report'),
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
          if (_report != null)
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange.shade100,
                  child: const Text(
                    '[!] AI-ASSISTED - Not a clinical diagnosis. Requires radiologist review.',
                    style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
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
                      'inferenceResult': widget.inferenceResult,
                      'reportResult': _currentReport(),
                      'overlayBytes': widget.overlayBytes,
                    },
                  ),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                ),
              ],
            ),
          if (_loading)
            const LoadingOverlayWidget(message: 'Generating report...'),
        ],
      ),
    );
  }

  Widget _editableSection(String title, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
