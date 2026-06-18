import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../services/ultrasound_validator.dart';

class ImageConfirmScreen extends StatefulWidget {
  final String imagePath;
  const ImageConfirmScreen({super.key, required this.imagePath});

  @override
  State<ImageConfirmScreen> createState() => _ImageConfirmScreenState();
}

class _ImageConfirmScreenState extends State<ImageConfirmScreen> {
  bool _validating = true;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _validate();
  }

  Future<void> _validate() async {
    String? error;
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        error = 'Could not read image file. Please try another image.';
      } else {
        final result = UltrasoundValidator.validateImage(decoded);
        if (!result.isValid) error = result.reason;
      }
    } catch (_) {
      error = 'Could not validate image. Please try another image.';
    }
    if (!mounted) return;
    setState(() {
      _validating = false;
      _validationError = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Image')),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Image.file(File(widget.imagePath), fit: BoxFit.contain),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_validating)
                  const LinearProgressIndicator()
                else if (_validationError != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline,
                            color: Colors.red.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: TextStyle(
                                color: Colors.red.shade700, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: Colors.orange.shade100,
                    child: const Text(
                      '[!] AI-ASSISTED — Not a clinical diagnosis. '
                      'Requires radiologist review.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.deepOrange),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_validating || _validationError != null)
                        ? null
                        : () => Navigator.pushNamed(
                              context,
                              '/analysis',
                              arguments: widget.imagePath,
                            ),
                    icon: const Icon(Icons.analytics),
                    label: const Text('Run Analysis'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
