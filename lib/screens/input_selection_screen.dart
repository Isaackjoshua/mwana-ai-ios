import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/image_picker_service.dart';

class InputSelectionScreen extends StatefulWidget {
  const InputSelectionScreen({super.key});
  @override
  State<InputSelectionScreen> createState() => _InputSelectionScreenState();
}

class _InputSelectionScreenState extends State<InputSelectionScreen> {
  final _picker = ImagePickerService();
  bool _loading = false;

  Future<void> _pick(ImageInputMode mode) async {
    setState(() => _loading = true);
    final path = await _picker.pickImage(mode);
    if (!mounted) return;
    if (path == null) { setState(() => _loading = false); return; }

    final error = await _picker.validateImage(path);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = false);
    Navigator.pushNamed(context, '/confirm', arguments: path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Image')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const Text(
              'Select a breast ultrasound image to analyse.',
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _InputButton(
              icon: Icons.photo_library,
              label: 'Gallery',
              onTap: _loading ? null : () => _pick(ImageInputMode.gallery),
            ),
            const SizedBox(height: 16),
            _InputButton(
              icon: Icons.camera_alt,
              label: 'Camera',
              onTap: _loading ? null : () => _pick(ImageInputMode.camera),
            ),
            const SizedBox(height: 16),
            _InputButton(
              icon: Icons.folder_open,
              label: 'Files',
              onTap: _loading ? null : () => _pick(ImageInputMode.file),
            ),
            // Butterfly iQ probe: physical device only (not simulator)
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
              const SizedBox(height: 16),
              _InputButton(
                icon: Icons.sensors,
                label: 'Butterfly iQ Probe',
                onTap: _loading
                    ? null
                    : () => Navigator.pushNamed(context, '/probe-connect'),
              ),
            ],
            if (_loading) ...[
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _InputButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _InputButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
