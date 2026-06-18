import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/classification_result.dart';
import '../models/inference_result.dart';
import '../models/report_result.dart';
import '../services/pdf_export_service.dart';
import '../widgets/loading_overlay_widget.dart';

class ExportScreen extends StatefulWidget {
  final InferenceResult inferenceResult;
  final ReportResult reportResult;
  final Uint8List? overlayBytes;

  const ExportScreen({
    super.key,
    required this.inferenceResult,
    required this.reportResult,
    this.overlayBytes,
  });

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _pdfService = PdfExportService();
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;

  // Used to get the share button's Rect for iPad popover positioning.
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  Future<void> _generatePdf() async {
    try {
      final bytes = await _pdfService.generatePdf(
        inferenceResult: widget.inferenceResult,
        reportResult: widget.reportResult,
        overlayImageBytes: widget.overlayBytes ?? Uint8List(0),
      );
      if (!mounted) return;
      setState(() {
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to generate PDF: $e';
        _loading = false;
      });
    }
  }

  Future<void> _sharePdf() async {
    if (_pdfBytes == null) return;
    final cls = widget.inferenceResult.classification;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final filename = 'mwana_ai_${cls.predictedClass.toLowerCase()}_$timestamp.pdf';

    Rect? rect;
    final renderBox = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final position = renderBox.localToGlobal(Offset.zero);
      rect = position & renderBox.size;
    }

    try {
      await _pdfService.sharePdf(_pdfBytes!, filename: filename, rect: rect);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export Report')),
      body: Stack(
        children: [
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            )
          else if (_pdfBytes != null)
            _buildShareView()
          else
            const SizedBox.shrink(),
          if (_loading)
            const LoadingOverlayWidget(message: 'Building PDF report...'),
        ],
      ),
    );
  }

  Widget _buildShareView() {
    final cls = widget.inferenceResult.classification;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.orange.shade100,
          child: const Text(
            '⚠️ AI-ASSISTED — Not a clinical diagnosis. Requires radiologist review.',
            style: TextStyle(fontSize: 12, color: Colors.deepOrange),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        const Icon(Icons.picture_as_pdf, size: 72, color: Colors.red),
        const SizedBox(height: 12),
        Text(
          'PDF Report Ready',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          '${(_pdfBytes!.length / 1024).toStringAsFixed(0)} KB  •  '
          '${cls.predictedClass}  •  ${cls.biRads.label}',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        ElevatedButton.icon(
          key: _shareButtonKey,
          onPressed: _sharePdf,
          icon: const Icon(Icons.ios_share),
          label: const Text('Share PDF'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.popUntil(context, ModalRoute.withName('/input')),
          child: const Text('Start New Analysis'),
        ),
      ],
    );
  }
}
