import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mwana_ai/services/image_picker_service.dart';

void main() {
  group('ImagePickerService.validateImage', () {
    late ImagePickerService service;

    setUp(() => service = ImagePickerService());

    test('returns error for non-existent file', () async {
      final result = await service.validateImage('/tmp/nonexistent_brain_scan.jpg');
      expect(result, equals('File not found.'));
    });

    test('returns error for unsupported extension (.bmp)', () async {
      final tmp = await _createTempFile('test_scan.bmp', bytes: 100);
      final result = await service.validateImage(tmp);
      expect(result, equals('Unsupported format. Use JPEG or PNG.'));
      await File(tmp).delete();
    });

    test('accepts .jpg extension', () async {
      final tmp = await _createTempFile('test_scan.jpg', bytes: 100);
      final result = await service.validateImage(tmp);
      expect(result, isNull);
      await File(tmp).delete();
    });

    test('accepts .jpeg extension', () async {
      final tmp = await _createTempFile('test_scan.jpeg', bytes: 100);
      final result = await service.validateImage(tmp);
      expect(result, isNull);
      await File(tmp).delete();
    });

    test('accepts .png extension', () async {
      final tmp = await _createTempFile('test_scan.png', bytes: 100);
      final result = await service.validateImage(tmp);
      expect(result, isNull);
      await File(tmp).delete();
    });

    test('returns error for file over 10 MB', () async {
      final tmp = await _createTempFile(
        'large_scan.jpg',
        bytes: 11 * 1024 * 1024,
      );
      final result = await service.validateImage(tmp);
      expect(result, equals('Image too large (max 10 MB).'));
      await File(tmp).delete();
    });
  });
}

Future<String> _createTempFile(String name, {required int bytes}) async {
  final dir = await Directory.systemTemp.createTemp('bai_test_');
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(List.filled(bytes, 0));
  return file.path;
}
