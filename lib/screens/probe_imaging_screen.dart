import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:path_provider/path_provider.dart';
import '../models/probe_state.dart';
import '../services/butterfly_probe_service.dart';

/// Live ultrasound preview from the Butterfly iQ probe.
///
/// Supports multi-section capture: the examiner presses "Capture Section"
/// for each breast quadrant, sees thumbnails accumulate in the strip, then
/// presses "Analyse All" to run inference on every captured section and
/// produce a cumulative report.
class ProbeImagingScreen extends StatefulWidget {
  final ButterflyProbeService service;
  const ProbeImagingScreen({super.key, required this.service});

  @override
  State<ProbeImagingScreen> createState() => _ProbeImagingScreenState();
}

class _ProbeImagingScreenState extends State<ProbeImagingScreen> {
  ProbeState _state = const ProbeState(connection: ProbeConnectionState.imaging);
  Uint8List? _latestFrame;
  bool _starting = true;
  bool _capturingSection = false;
  String? _probeError;

  late double _depthCm;
  late double _gainLevel;

  final List<String> _capturedPaths = [];
  final List<Uint8List> _capturedThumbs = [];

  @override
  void initState() {
    super.initState();
    _depthCm = widget.service.currentState.depthCm;
    _gainLevel = widget.service.currentState.gain.toDouble();

    widget.service.stateStream.listen((s) {
      if (!mounted) return;
      setState(() {
        _state = s;
        _depthCm = s.depthCm;
        _gainLevel = s.gain.toDouble();
        if (s.connection == ProbeConnectionState.disconnected) {
          _probeError = 'Probe disconnected. Please reconnect and try again.';
        }
      });
    });

    widget.service.frameStream.listen((frame) {
      if (mounted) setState(() => _latestFrame = frame);
    });

    _startImaging();
  }

  Future<void> _startImaging() async {
    try {
      await widget.service.startImaging();
    } catch (e) {
      if (mounted) setState(() => _probeError = 'Failed to start imaging: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _captureSection() async {
    setState(() => _capturingSection = true);
    try {
      final bytes = await widget.service.captureFrame();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/probe_section_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes);
      setState(() {
        _capturedPaths.add(path);
        _capturedThumbs.add(bytes);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturingSection = false);
    }
  }

  void _removeSection(int index) {
    final path = _capturedPaths[index];
    setState(() {
      _capturedPaths.removeAt(index);
      _capturedThumbs.removeAt(index);
    });
    File(path).delete().ignore();
  }

  Future<void> _finishAndAnalyse() async {
    if (_capturedPaths.isEmpty) return;
    await widget.service.stopImaging();
    if (!mounted) return;
    Navigator.pushNamed(
      context,
      '/multi-analysis',
      arguments: List<String>.from(_capturedPaths),
    );
  }

  Future<void> _stop() async {
    if (_capturedPaths.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard captures?'),
          content: Text(
            'You have ${_capturedPaths.length} captured section(s). '
            'Stopping now will discard them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep imaging'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Discard & stop',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    await widget.service.stopImaging();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final count = _capturedPaths.length;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          count == 0
              ? 'Butterfly iQ — Live Imaging'
              : 'Butterfly iQ — $count section${count == 1 ? '' : 's'} captured',
        ),
        actions: [
          TextButton(
            onPressed: _stop,
            child: const Text('Stop', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildPreview()),
          if (_capturedPaths.isNotEmpty) _buildThumbnailStrip(),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_probeError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_probeError!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_starting || _latestFrame == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpinKitPulse(color: Colors.white.withValues(alpha: 0.7), size: 60),
            const SizedBox(height: 16),
            const Text('Starting imaging...',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Image.memory(
      _latestFrame!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
  }

  Widget _buildThumbnailStrip() {
    return Container(
      height: 84,
      color: Colors.grey.shade900,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        itemCount: _capturedPaths.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  _capturedThumbs[i],
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
              Positioned(
                top: 2,
                left: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    'S${i + 1}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () => _removeSection(i),
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 12, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    final bool canCapture = !_capturingSection &&
        !_starting &&
        _probeError == null &&
        _latestFrame != null;

    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Depth slider
          Row(
            children: [
              const SizedBox(
                width: 56,
                child: Text('Depth',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              Expanded(
                child: Slider(
                  value: _depthCm.clamp(_state.depthMin, _state.depthMax),
                  min: _state.depthMin,
                  max: _state.depthMax,
                  divisions: ((_state.depthMax - _state.depthMin) * 2)
                      .round()
                      .clamp(1, 100),
                  onChanged: (v) => setState(() => _depthCm = v),
                  onChangeEnd: (v) => widget.service.setDepth(v),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${_depthCm.toStringAsFixed(1)} cm',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          // Gain slider
          Row(
            children: [
              const SizedBox(
                width: 56,
                child: Text('Gain',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
              Expanded(
                child: Slider(
                  value: _gainLevel.clamp(0, 100),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  onChanged: (v) => setState(() => _gainLevel = v),
                  onChangeEnd: (v) => widget.service.setGain(v.round()),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  _gainLevel.round().toString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Capture Section
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade700,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade800,
                    ),
                    onPressed: canCapture ? _captureSection : null,
                    icon: _capturingSection
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.camera, size: 18),
                    label: Text(
                        _capturingSection ? 'Saving...' : 'Capture Section'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Analyse All
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _capturedPaths.isNotEmpty
                          ? theme.colorScheme.primary
                          : Colors.grey.shade800,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white38,
                    ),
                    onPressed:
                        _capturedPaths.isNotEmpty ? _finishAndAnalyse : null,
                    icon: const Icon(Icons.analytics, size: 18),
                    label: Text(
                      _capturedPaths.isEmpty
                          ? 'Analyse All'
                          : 'Analyse ${_capturedPaths.length}',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'AI-ASSISTED — Not a clinical diagnosis. Requires radiologist review.',
            style: TextStyle(color: Colors.deepOrange, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
