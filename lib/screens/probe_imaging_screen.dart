import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:path_provider/path_provider.dart';
import '../models/probe_state.dart';
import '../services/butterfly_probe_service.dart';

/// Live ultrasound preview from the Butterfly iQ probe.
///
/// Starts imaging immediately on mount. The "Capture" button saves the
/// current full-resolution frame to a temp file and navigates directly
/// to /analysis (skipping the confirm screen since the user has already
/// reviewed the image on this screen).
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
  bool _capturing = false;
  String? _error;

  late double _depthCm;
  late double _gainLevel;

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
          _error = 'Probe disconnected. Please reconnect and try again.';
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
      if (mounted) setState(() => _error = 'Failed to start imaging: $e');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _capture() async {
    setState(() => _capturing = true);
    try {
      final bytes = await widget.service.captureFrame();
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/probe_capture_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      await widget.service.stopImaging();
      if (!mounted) return;
      Navigator.pushNamed(context, '/analysis', arguments: path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _stop() async {
    await widget.service.stopImaging();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Butterfly iQ — Live Imaging'),
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
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
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

  Widget _buildControls() {
    final theme = Theme.of(context);
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Depth slider
          Row(
            children: [
              const SizedBox(width: 56, child: Text('Depth', style: TextStyle(color: Colors.white70, fontSize: 12))),
              Expanded(
                child: Slider(
                  value: _depthCm.clamp(_state.depthMin, _state.depthMax),
                  min: _state.depthMin,
                  max: _state.depthMax,
                  divisions: ((_state.depthMax - _state.depthMin) * 2).round().clamp(1, 100),
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
              const SizedBox(width: 56, child: Text('Gain', style: TextStyle(color: Colors.white70, fontSize: 12))),
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
          // Capture button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade700,
              ),
              onPressed: (_capturing || _starting || _error != null || _latestFrame == null)
                  ? null
                  : _capture,
              icon: _capturing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.camera),
              label: Text(_capturing ? 'Saving...' : 'Capture & Analyse'),
            ),
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
