import 'package:flutter/material.dart';
import '../models/probe_state.dart';
import '../services/butterfly_probe_service.dart';

/// Shows probe connection status and lets the user begin imaging.
///
/// The Butterfly iQ probe connects via USB-C (not BLE). Once plugged in,
/// the SDK detects it automatically and the state stream transitions to
/// [ProbeConnectionState.connected].
class ProbeConnectScreen extends StatefulWidget {
  const ProbeConnectScreen({super.key});

  @override
  State<ProbeConnectScreen> createState() => _ProbeConnectScreenState();
}

class _ProbeConnectScreenState extends State<ProbeConnectScreen> {
  final _service = ButterflyProbeService();
  ProbeState _state = const ProbeState(connection: ProbeConnectionState.disconnected);
  bool _initializing = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _service.stateStream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _service.initialize();
    } catch (e) {
      if (mounted) setState(() => _initError = e.toString());
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Butterfly iQ Probe')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing Butterfly SDK...'),
          ],
        ),
      );
    }

    if (_initError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            const Text('SDK initialization failed',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_initError!,
                style: const TextStyle(color: Colors.red, fontSize: 13),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text(
              'Ensure your Client Key is set in\nios/Runner/ButterflyConfig.xcconfig',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return switch (_state.connection) {
      ProbeConnectionState.disconnected => _buildDisconnected(),
      ProbeConnectionState.connected => _buildConnected(),
      ProbeConnectionState.imaging => _buildConnected(),
      ProbeConnectionState.firmwareIncompatible => _buildFirmwareError(),
      ProbeConnectionState.hardwareIncompatible => _buildHardwareError(),
      ProbeConnectionState.error => _buildGenericError(),
    };
  }

  Widget _buildDisconnected() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.usb, size: 72, color: Colors.grey),
          SizedBox(height: 24),
          Text(
            'Connect your Butterfly iQ probe',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 12),
          Text(
            'Plug the probe into your iPhone via the USB-C port.\n'
            'The app will detect it automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          SizedBox(height: 32),
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Waiting for probe...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildConnected() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 72, color: Colors.green),
          const SizedBox(height: 16),
          const Text(
            'Probe Connected',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pushNamed(
                context,
                '/probe-imaging',
                arguments: _service,
              ),
              icon: const Icon(Icons.videocam),
              label: const Text('Start Imaging', style: TextStyle(fontSize: 18)),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'AI-ASSISTED — Not a clinical diagnosis.\nRequires radiologist review.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.deepOrange),
          ),
        ],
      ),
    );
  }

  Widget _buildFirmwareError() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.system_update, size: 64, color: Colors.orange),
          SizedBox(height: 16),
          Text(
            'Firmware Update Required',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'Your Butterfly iQ probe firmware is out of date.\n'
            'Please update it using the official Butterfly iQ app before using Mwana-AI.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareError() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hardware, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(
            'Probe Not Supported',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'This Butterfly iQ probe model is not compatible with this app.\n'
            'Check the Butterfly Network documentation for supported devices.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildGenericError() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(
            'Probe Error',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            'An error occurred communicating with the probe.\n'
            'Disconnect and reconnect the probe to try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
