import 'dart:typed_data';

abstract class OrtSessionRunner {
  Future<({List<double> clsLogits, Float32List segProbs})> runPass(Float32List tensor);
  Future<void> close();
}
