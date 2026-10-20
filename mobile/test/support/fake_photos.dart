import 'package:mobile/models/trip_photo.dart';
import 'package:mobile/services/photo_picker.dart';
import 'package:mobile/services/trip_photo_store.dart';

/// In-memory trip photo store. The real one uses platform channels and file
/// I/O, which never complete inside widget tests.
class FakeTripPhotoStore implements TripPhotoStore {
  final Map<String, List<TripPhoto>> photos;
  Object? failList;
  Object? failAdd;
  Object? failRemove;
  final List<String> addedSources = [];
  int _counter = 0;

  FakeTripPhotoStore([Map<String, List<TripPhoto>>? initial])
    : photos = {
        for (final e in (initial ?? {}).entries) e.key: [...e.value],
      };

  @override
  Future<List<TripPhoto>> list(String tripId) async {
    if (failList != null) throw failList!;
    return [...(photos[tripId] ?? const [])];
  }

  @override
  Future<TripPhoto> add(String tripId, String sourcePath) async {
    if (failAdd != null) throw failAdd!;
    addedSources.add(sourcePath);
    final photo = TripPhoto(
      tripId: tripId,
      path: '/fake/$tripId/${++_counter}.jpg',
      takenAt: DateTime(2026, 10, 20, 12, 0, _counter),
    );
    photos[tripId] = [photo, ...(photos[tripId] ?? const [])];
    return photo;
  }

  @override
  Future<void> remove(TripPhoto photo) async {
    if (failRemove != null) throw failRemove!;
    photos[photo.tripId] = [
      for (final p in photos[photo.tripId] ?? const <TripPhoto>[])
        if (p != photo) p,
    ];
  }
}

/// A picker that returns a canned result (or fails) instead of opening the camera.
class FakePhotoPicker implements PhotoPicker {
  /// What the next pick returns; null means "the user cancelled".
  String? result = '/picked/photo.jpg';
  Object? failure;
  final List<PhotoSource> requested = [];

  @override
  Future<String?> pick(PhotoSource source) async {
    requested.add(source);
    if (failure != null) throw failure!;
    return result;
  }
}

TripPhoto photo(String tripId, int n) => TripPhoto(
  tripId: tripId,
  path: '/fake/$tripId/$n.jpg',
  takenAt: DateTime(2026, 10, 20, 12, 0, n),
);
