import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

class ModelManagerService {
  static const _modelType = ModelType.gemma4;

  /// Optional override for [FlutterGemma.listInstalledModels]; injected in
  /// tests to avoid the native-assets platform channel.
  final Future<List<String>> Function()? _listModelsOverride;
  final Future<void> Function(String path, void Function(int)? onProgress)? _installFromFileOverride;
  final Future<void> Function(String url, String? token, void Function(int)? onProgress)? _installFromUrlOverride;

  ModelManagerService({
    Future<List<String>> Function()? listModelsOverride,
    Future<void> Function(String, void Function(int)?)? installFromFileOverride,
    Future<void> Function(String, String?, void Function(int)?)? installFromUrlOverride,
  })  : _listModelsOverride = listModelsOverride,
        _installFromFileOverride = installFromFileOverride,
        _installFromUrlOverride = installFromUrlOverride;

  /// Returns true if any model is installed and ready.
  Future<bool> isInstalled() async {
    try {
      final override = _listModelsOverride;
      final models = override != null
          ? await override()
          : await FlutterGemma.listInstalledModels();
      return models.isNotEmpty;
    } catch (e) {
      // Covers Exception and Error (e.g. StateError when plugin not yet
      // initialized) — treat as not installed so the caller routes to setup.
      debugPrint('[ModelManagerService] isInstalled check failed: $e');
      return false;
    }
  }

  /// Installs the model from a file already on the device.
  /// [onProgress] receives values 0–100.
  Future<void> installFromFile(
    String filePath, {
    void Function(int progress)? onProgress,
  }) async {
    if (_installFromFileOverride != null) {
      await _installFromFileOverride(filePath, onProgress);
      return;
    }
    await FlutterGemma.installModel(modelType: _modelType)
        .fromFile(filePath)
        .withProgress(onProgress ?? (_) {})
        .install();
  }

  /// Downloads and installs the model from [url].
  /// [onProgress] receives values 0–100.
  Future<void> installFromUrl(
    String url, {
    String? token,
    void Function(int progress)? onProgress,
  }) async {
    if (_installFromUrlOverride != null) {
      await _installFromUrlOverride(url, token, onProgress);
      return;
    }
    await FlutterGemma.installModel(modelType: _modelType)
        .fromNetwork(url, token: token)
        .withProgress(onProgress ?? (_) {})
        .install();
  }
}
