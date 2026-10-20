import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/trip_photo.dart';

/// Where trip photos are kept. Photos are copied into the app's private
/// storage, so they survive the picker's cache being cleared.
abstract class TripPhotoStore {
  /// Newest first. Empty when the trip has no photos.
  Future<List<TripPhoto>> list(String tripId);

  /// Copies [sourcePath] into the trip's folder.
  Future<TripPhoto> add(String tripId, String sourcePath);

  /// Deletes the stored copy. Already-missing files are not an error.
  Future<void> remove(TripPhoto photo);
}

/// Stores photos as `<documents>/trip_photos/<tripId>/<microseconds>.<ext>`.
/// The file name is the timestamp, so no separate index is needed.
class FileTripPhotoStore implements TripPhotoStore {
  static const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.heic'};

  // Trip ids are GUIDs. Anything else could escape the photos folder.
  static final _safeId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

  final Future<Directory> Function() _rootProvider;

  FileTripPhotoStore({Future<Directory> Function()? rootProvider})
      : _rootProvider = rootProvider ?? _defaultRoot;

  static Future<Directory> _defaultRoot() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'trip_photos'));
  }

  Future<Directory> _tripDir(String tripId) async {
    if (!_safeId.hasMatch(tripId)) {
      throw ArgumentError.value(tripId, 'tripId', 'not a valid trip id');
    }
    final root = await _rootProvider();
    return Directory(p.join(root.path, tripId));
  }

  @override
  Future<List<TripPhoto>> list(String tripId) async {
    final dir = await _tripDir(tripId);
    if (!await dir.exists()) return const [];

    final photos = <TripPhoto>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!_imageExtensions.contains(p.extension(entity.path).toLowerCase())) {
        continue;
      }
      final micros = int.tryParse(p.basenameWithoutExtension(entity.path));
      photos.add(TripPhoto(
        tripId: tripId,
        path: entity.path,
        takenAt: micros == null
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMicrosecondsSinceEpoch(micros),
      ));
    }
    photos.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return photos;
  }

  @override
  Future<TripPhoto> add(String tripId, String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException('The picked photo is no longer available', sourcePath);
    }
    final dir = await _tripDir(tripId);
    await dir.create(recursive: true);

    var ext = p.extension(sourcePath).toLowerCase();
    if (!_imageExtensions.contains(ext)) ext = '.jpg';

    // The timestamp is the name; step forward on the (unlikely) clash.
    var micros = DateTime.now().microsecondsSinceEpoch;
    var target = File(p.join(dir.path, '$micros$ext'));
    while (await target.exists()) {
      micros++;
      target = File(p.join(dir.path, '$micros$ext'));
    }
    await source.copy(target.path);

    return TripPhoto(
      tripId: tripId,
      path: target.path,
      takenAt: DateTime.fromMicrosecondsSinceEpoch(micros),
    );
  }

  @override
  Future<void> remove(TripPhoto photo) async {
    final dir = await _tripDir(photo.tripId);
    // Only ever delete inside this trip's own folder.
    if (!p.isWithin(dir.path, photo.path)) {
      throw ArgumentError.value(
          photo.path, 'photo', 'is not inside the trip photo folder');
    }
    final file = File(photo.path);
    if (await file.exists()) await file.delete();
  }
}
