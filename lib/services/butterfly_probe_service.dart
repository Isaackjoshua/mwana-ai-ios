import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/probe_state.dart';

/// Dart wrapper around the native ButterflyProbePlugin.
///
/// One instance should be created when the probe screens open and disposed
/// when the user exits the probe flow. The client key is read from
/// Info.plist (injected at build time from ButterflyConfig.xcconfig).
class ButterflyProbeService {
  static const _method = MethodChannel('com.mwana_ai/butterfly_probe');
  static const _events = EventChannel('com.mwana_ai/butterfly_probe_events');

  StreamSubscription<dynamic>? _eventSubscription;
  final _stateController = StreamController<ProbeState>.broadcast();
  final _frameController = StreamController<Uint8List>.broadcast();

  /// Emits full [ProbeState] on every probe state change.
  Stream<ProbeState> get stateStream => _stateController.stream;

  /// Emits JPEG preview frames (~320 px wide) while imaging.
  Stream<Uint8List> get frameStream => _frameController.stream;

  ProbeState _current = const ProbeState(connection: ProbeConnectionState.disconnected);
  ProbeState get currentState => _current;

  /// Initializes the Butterfly SDK and begins streaming events.
  ///
  /// The client key is read by the native plugin from Info.plist
  /// (expanded from BUTTERFLY_CLIENT_KEY in ButterflyConfig.xcconfig).
  Future<void> initialize() async {
    await _method.invokeMethod<void>('initialize');
    _startListening();
  }

  void _startListening() {
    _eventSubscription?.cancel();
    _eventSubscription = _events.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object e) {
        _stateController.addError(e);
      },
    );
  }

  void _handleEvent(dynamic raw) {
    final event = Map<String, dynamic>.from(raw as Map);
    final type = event['type'] as String?;

    switch (type) {
      case 'state':
        final stateStr = event['state'] as String? ?? 'disconnected';
        _current = ProbeState(
          connection: _parseConnection(stateStr),
          depthCm: (event['depthCm'] as num?)?.toDouble() ?? _current.depthCm,
          depthMin: (event['depthMin'] as num?)?.toDouble() ?? _current.depthMin,
          depthMax: (event['depthMax'] as num?)?.toDouble() ?? _current.depthMax,
          gain: (event['gain'] as num?)?.toInt() ?? _current.gain,
        );
        _stateController.add(_current);

      case 'frame':
        final b64 = event['data'] as String?;
        if (b64 != null) {
          _frameController.add(base64Decode(b64));
        }

      case 'error':
        _stateController.addError(PlatformException(
          code: event['code'] as String? ?? 'PROBE_ERROR',
          message: event['message'] as String?,
        ));
    }
  }

  ProbeConnectionState _parseConnection(String s) => switch (s) {
        'connected' => ProbeConnectionState.connected,
        'imaging' => ProbeConnectionState.imaging,
        'firmwareIncompatible' => ProbeConnectionState.firmwareIncompatible,
        'hardwareIncompatible' => ProbeConnectionState.hardwareIncompatible,
        'error' => ProbeConnectionState.error,
        _ => ProbeConnectionState.disconnected,
      };

  /// Starts the imaging session. [preset] is an optional case-insensitive
  /// substring match against available probe presets (e.g. "breast", "msk").
  Future<void> startImaging({String? preset}) async {
    await _method.invokeMethod<void>('startImaging', {'preset': preset});
  }

  /// Captures the current full-resolution frame as JPEG bytes.
  Future<Uint8List> captureFrame() async {
    final result = await _method.invokeMethod<Uint8List>('captureFrame');
    if (result == null) throw PlatformException(code: 'NO_FRAME', message: 'No frame available');
    return result;
  }

  Future<void> stopImaging() async {
    await _method.invokeMethod<void>('stopImaging');
  }

  Future<void> setDepth(double cm) async {
    await _method.invokeMethod<void>('setDepth', {'cm': cm});
  }

  Future<void> setGain(int gain) async {
    await _method.invokeMethod<void>('setGain', {'gain': gain});
  }

  Future<List<String>> getAvailablePresets() async {
    final result = await _method.invokeListMethod<String>('getAvailablePresets');
    return result ?? [];
  }

  void dispose() {
    _eventSubscription?.cancel();
    _stateController.close();
    _frameController.close();
  }
}
