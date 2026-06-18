import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/model_manager_service.dart';
import '../widgets/loading_overlay_widget.dart';

class ModelSetupScreen extends StatefulWidget {
  const ModelSetupScreen({super.key});
  @override
  State<ModelSetupScreen> createState() => _ModelSetupScreenState();
}

class _ModelSetupScreenState extends State<ModelSetupScreen>
    with SingleTickerProviderStateMixin {
  final _manager = ModelManagerService();
  late final TabController _tabs;

  final _urlCtrl   = TextEditingController();
  final _tokenCtrl = TextEditingController();

  bool _busy = false;
  int  _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _urlCtrl.text =
        'https://huggingface.co/litert-community/Gemma4-E2B-IT/resolve/main/'
        'gemma4-e2b-it-int4.litertlm';
  }

  @override
  void dispose() {
    _tabs.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _installFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    setState(() { _busy = true; _progress = 0; _error = null; });
    try {
      await _manager.installFromFile(
        path,
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/input');
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  Future<void> _installFromUrl() async {
    final url   = _urlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Please enter a model URL.');
      return;
    }
    setState(() { _busy = true; _progress = 0; _error = null; });
    try {
      await _manager.installFromUrl(
        url,
        token: token.isEmpty ? null : token,
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/input');
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Setup'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'From Device'),
            Tab(text: 'Download URL'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabs,
            children: [
              _fromDeviceTab(),
              _fromUrlTab(),
            ],
          ),
          if (_busy)
            LoadingOverlayWidget(
              message: _progress > 0
                  ? 'Installing model... $_progress%'
                  : 'Installing model...',
            ),
        ],
      ),
    );
  }

  Widget _fromDeviceTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.folder_open, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Pick a Gemma 4 model file (.litertlm or .task) '
              'you have downloaded to this device.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Recommended: Gemma 4 E2B (~2.4 GB)\n'
              'Download from: huggingface.co/litert-community',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _busy ? null : _installFromFile,
              icon: const Icon(Icons.file_open),
              label: const Text('Pick Model File'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fromUrlTab() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.download, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Enter a direct download URL for the model file. '
              'Provide a HuggingFace token for gated models.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Model URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _tokenCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'HuggingFace Token (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _busy ? null : _installFromUrl,
              icon: const Icon(Icons.download),
              label: const Text('Download & Install'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
