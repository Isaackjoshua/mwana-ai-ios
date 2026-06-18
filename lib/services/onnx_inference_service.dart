import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import '../models/classification_result.dart';
import '../models/segmentation_result.dart';
import '../models/inference_result.dart';
import 'image_preprocessor.dart';
import 'birads_service.dart';
import 'onnx_session_runner.dart';
import 'default_ort_session_runner.dart' deferred as ort_impl;

class OnnxInferenceService {
  static const double malignantThreshold = 0.35;
  static const double segThreshold = 0.275;

  final ImagePreprocessor _preprocessor;
  final BiRadsService _biRads;
  Future<OrtSessionRunner>? _runnerFuture;

  OnnxInferenceService({
    ImagePreprocessor? preprocessor,
    BiRadsService? biRads,
    OrtSessionRunner? runner,
  })  : _preprocessor = preprocessor ?? ImagePreprocessor(),
        _biRads = biRads ?? BiRadsService() {
    if (runner != null) {
      _runnerFuture = Future.value(runner);
    }
  }

  /// Numerically stable softmax: subtracts max logit before exponentiation.
  List<double> softmax(Float32List logits) {
    double maxVal = logits.reduce(math.max);
    final exps = logits.map((v) => math.exp(v - maxVal)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  /// Applies the logistic sigmoid function.
  double sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  /// Element-wise mean of two equal-length probability lists.
  List<double> averageProbabilities(List<double> a, List<double> b) {
    return List.generate(a.length, (i) => (a[i] + b[i]) / 2.0);
  }

  /// Returns the predicted class index, overriding argmax if probs[1] (malignant) >= 0.35.
  int applyMalignantThreshold(List<double> probs) {
    if (probs[1] >= malignantThreshold) return 1;
    int argmax = 0;
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > probs[argmax]) argmax = i;
    }
    return argmax;
  }

  /// Converts sigmoid probabilities to a binary mask using [segThreshold] (0.275).
  Float32List applySegThreshold(Float32List sigProbs) {
    final binary = Float32List(sigProbs.length);
    for (int i = 0; i < sigProbs.length; i++) {
      binary[i] = sigProbs[i] >= segThreshold ? 1.0 : 0.0;
    }
    return binary;
  }

  Future<OrtSessionRunner> _ensureRunner() {
    return _runnerFuture ??= _buildRunner();
  }

  Future<OrtSessionRunner> _buildRunner() async {
    await ort_impl.loadLibrary();
    final runner = ort_impl.DefaultOrtSessionRunner();
    return runner;
  }

  /// Runs the full 2-way TTA inference pipeline on the image at [imagePath].
  Future<InferenceResult> runInference(String imagePath) async {
    final stopwatch = Stopwatch()..start();
    final runner = await _ensureRunner();
    final preprocessed = await _preprocessor.preprocessForInference(imagePath);
    final originalBytes = await io.File(imagePath).readAsBytes();

    final originalPass = await runner.runPass(preprocessed.original);
    final flippedPass = await runner.runPass(preprocessed.flipped);

    final avgClsProbs = averageProbabilities(
      softmax(Float32List.fromList(originalPass.clsLogits)),
      softmax(Float32List.fromList(flippedPass.clsLogits)),
    );
    final predictedIndex = applyMalignantThreshold(avgClsProbs);
    final biRads = _biRads.assignBiRads(
      predictedIndex: predictedIndex,
      probabilities: avgClsProbs,
    );

    final avgSegRaw = _averageSegMasks(originalPass.segProbs, flippedPass.segProbs);
    final sigSeg = Float32List.fromList(avgSegRaw.map(sigmoid).toList());
    final binaryMask = applySegThreshold(sigSeg);

    const diceScore = 0.0;
    stopwatch.stop();

    return InferenceResult(
      classification: ClassificationResult(
        predictedIndex: predictedIndex,
        probabilities: avgClsProbs,
        biRads: biRads,
      ),
      segmentation: SegmentationResult(
        binaryMask: binaryMask,
        diceScore: diceScore,
      ),
      originalImageBytes: originalBytes,
      latencyMs: stopwatch.elapsedMilliseconds,
    );
  }

  Float32List _averageSegMasks(Float32List original, Float32List flipped) {
    const size = SegmentationResult.maskSize;
    final averaged = Float32List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final origIdx = y * size + x;
        // Un-flip the flipped mask by mirroring x back to original orientation.
        final flipIdx = y * size + (size - 1 - x);
        averaged[origIdx] = (original[origIdx] + flipped[flipIdx]) / 2.0;
      }
    }
    return averaged;
  }

}
