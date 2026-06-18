import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'onnx_session_runner.dart';

class DefaultOrtSessionRunner implements OrtSessionRunner {
  static const String _modelAssetPath = 'assets/models/model_simplified.onnx';
  static const String _inputNode = 'image';
  static const String _clsOutput = 'cls_logits';
  static const String _segOutput = 'seg_logits';

  final OnnxRuntime _onnxRuntime;
  OrtSession? _session;

  DefaultOrtSessionRunner({OnnxRuntime? onnxRuntime})
      : _onnxRuntime = onnxRuntime ?? OnnxRuntime();

  Future<void> _ensureLoaded() async {
    if (_session != null) return;
    _session = await _onnxRuntime.createSessionFromAsset(
      _modelAssetPath,
      options: OrtSessionOptions(),
    );
  }

  @override
  Future<({List<double> clsLogits, Float32List segProbs})> runPass(Float32List tensor) async {
    await _ensureLoaded();
    final inputTensor = await OrtValue.fromList(tensor, [1, 3, 256, 256]);
    try {
      final outputs = await _session!.run({_inputNode: inputTensor});
      final clsValue = outputs[_clsOutput];
      final segValue = outputs[_segOutput];
      if (clsValue == null || segValue == null) {
        throw StateError(
          'ONNX model missing expected outputs. '
          'Expected "$_clsOutput" and "$_segOutput".',
        );
      }
      try {
        final clsRaw = await clsValue.asFlattenedList();
        final segRaw = await segValue.asFlattenedList();
        final clsLogits = Float32List.fromList(
          clsRaw.map((e) => (e as num).toDouble()).toList(),
        );
        final segProbs = Float32List.fromList(
          segRaw.map((e) => (e as num).toDouble()).toList(),
        );
        return (clsLogits: clsLogits.toList(), segProbs: segProbs);
      } finally {
        await clsValue.dispose();
        await segValue.dispose();
      }
    } finally {
      await inputTensor.dispose();
    }
  }

  @override
  Future<void> close() async {
    await _session?.close();
    _session = null;
  }
}
