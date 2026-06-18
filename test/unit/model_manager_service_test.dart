import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/services/model_manager_service.dart';

void main() {
  group('ModelManagerService', () {
    test('isInstalled returns false when no model is loaded', () async {
      // Inject an empty list to simulate no installed models without
      // requiring the flutter_gemma native-assets platform channel.
      final svc = ModelManagerService(
        listModelsOverride: () async => [],
      );
      // No model installed in test environment.
      final result = await svc.isInstalled();
      expect(result, isFalse);
    });

    test('isInstalled returns true when models are present', () async {
      final svc = ModelManagerService(
        listModelsOverride: () async => ['gemma4.litertlm'],
      );
      final result = await svc.isInstalled();
      expect(result, isTrue);
    });

    test('isInstalled returns false when listModels throws', () async {
      final svc = ModelManagerService(
        listModelsOverride: () async => throw Exception('plugin not ready'),
      );
      final result = await svc.isInstalled();
      expect(result, isFalse);
    });

    test('installFromFile calls override with correct path', () async {
      String? capturedPath;
      final svc = ModelManagerService(
        installFromFileOverride: (path, _) async { capturedPath = path; },
      );
      await svc.installFromFile('/data/model.litertlm');
      expect(capturedPath, '/data/model.litertlm');
    });

    test('installFromUrl calls override with correct url and token', () async {
      String? capturedUrl;
      String? capturedToken;
      final svc = ModelManagerService(
        installFromUrlOverride: (url, token, _) async {
          capturedUrl = url;
          capturedToken = token;
        },
      );
      await svc.installFromUrl('https://example.com/m.litertlm', token: 'hf_abc');
      expect(capturedUrl, 'https://example.com/m.litertlm');
      expect(capturedToken, 'hf_abc');
    });
  });
}
