import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// A failure with a message that is safe to show to the user.
class PhotoPickerException implements Exception {
  final String message;
  const PhotoPickerException(this.message);

  @override
  String toString() => message;
}

/// Gets a photo from the device camera or gallery.
abstract class PhotoPicker {
  /// Returns the picked file's path, or null when the user cancelled.
  /// Throws [PhotoPickerException] when the camera/gallery cannot be used.
  Future<String?> pick(PhotoSource source);
}

class ImagePickerPhotoPicker implements PhotoPicker {
  final ImagePicker _picker;
  ImagePickerPhotoPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  @override
  Future<String?> pick(PhotoSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source == PhotoSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        // Phone photos are huge; a trip gallery does not need full resolution.
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      return file?.path;
    } on PlatformException catch (e) {
      throw messageFor(e, source);
    }
  }

  /// Turns the platform's error into a message the traveler can act on.
  static PhotoPickerException messageFor(
      PlatformException e, PhotoSource source) {
    final denied =
        e.code == 'camera_access_denied' || e.code == 'photo_access_denied';
    if (denied) {
      return PhotoPickerException(source == PhotoSource.camera
          ? 'Camera access is turned off. Allow it in Settings to take photos.'
          : 'Photo access is turned off. Allow it in Settings to choose photos.');
    }
    return PhotoPickerException(source == PhotoSource.camera
        ? 'Could not open the camera.'
        : 'Could not open your photos.');
  }
}
