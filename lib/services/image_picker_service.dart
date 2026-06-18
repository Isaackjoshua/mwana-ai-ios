import 'dart:io';
import 'package:image_picker/image_picker.dart';

enum ImageInputMode { gallery, camera, file }

/// Provides image selection via gallery, camera, or file picker.
class ImagePickerService {
  final ImagePicker _picker;

  ImagePickerService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  /// Picks an image using [mode].
  /// Returns the local file path, or null if user cancelled.
  Future<String?> pickImage(ImageInputMode mode) async {
    XFile? file;
    switch (mode) {
      case ImageInputMode.gallery:
        file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 100,
        );
        break;
      case ImageInputMode.file:
        // Falls back to gallery picker. Full file-system browsing (Documents,
        // Downloads) requires the file_picker package — add in a future phase.
        file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 100,
        );
        break;
      case ImageInputMode.camera:
        file = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 100,
        );
        break;
    }
    return file?.path;
  }

  /// Validates that [path] is a supported image file and not too large.
  /// Returns an error message string, or null if valid.
  Future<String?> validateImage(String path) async {
    final file = File(path);
    if (!await file.exists()) return 'File not found.';

    // Check format before size so callers get the most actionable error first.
    final ext = path.toLowerCase();
    if (!ext.endsWith('.jpg') &&
        !ext.endsWith('.jpeg') &&
        !ext.endsWith('.png')) {
      return 'Unsupported format. Use JPEG or PNG.';
    }

    final sizeBytes = await file.length();
    if (sizeBytes > 10 * 1024 * 1024) return 'Image too large (max 10 MB).';

    return null;
  }
}
