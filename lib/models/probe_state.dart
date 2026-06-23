enum ProbeConnectionState {
  disconnected,
  connected,
  imaging,
  firmwareIncompatible,
  hardwareIncompatible,
  error,
}

class ProbeState {
  final ProbeConnectionState connection;
  final double depthCm;
  final double depthMin;
  final double depthMax;
  final int gain;

  const ProbeState({
    required this.connection,
    this.depthCm = 7.0,
    this.depthMin = 2.0,
    this.depthMax = 15.0,
    this.gain = 50,
  });

  ProbeState copyWith({
    ProbeConnectionState? connection,
    double? depthCm,
    double? depthMin,
    double? depthMax,
    int? gain,
  }) {
    return ProbeState(
      connection: connection ?? this.connection,
      depthCm: depthCm ?? this.depthCm,
      depthMin: depthMin ?? this.depthMin,
      depthMax: depthMax ?? this.depthMax,
      gain: gain ?? this.gain,
    );
  }
}
