import 'package:flutter/foundation.dart';

import '../models/trip_photo.dart';
import '../services/photo_picker.dart';
import '../services/trip_photo_store.dart';

/// Photos per trip, read from and written to on-device storage.
class TripPhotosProvider extends ChangeNotifier {
  static const maxPerTrip = 30;

  final TripPhotoStore _store;
  final PhotoPicker _picker;
  TripPhotosProvider(this._store, this._picker);

  final Map<String, List<TripPhoto>> _photos = {};
  final Set<String> _loaded = {};
  final Set<String> _busy = {};

  // Bumped by clear() so a request that finishes after sign-out is dropped.
  int _epoch = 0;

  List<TripPhoto> photosFor(String tripId) => _photos[tripId] ?? const [];
  bool hasLoaded(String tripId) => _loaded.contains(tripId);
  bool isBusy(String tripId) => _busy.contains(tripId);

  Future<void> load(String tripId) async {
    final epoch = _epoch;
    List<TripPhoto> photos;
    try {
      photos = await _store.list(tripId);
    } catch (_) {
      // Unreadable storage just means "no photos to show".
      photos = const [];
    }
    if (epoch != _epoch) return;
    _photos[tripId] = photos;
    _loaded.add(tripId);
    notifyListeners();
  }

  /// Picks a photo and attaches it. Returns null on success or when the user
  /// cancelled, otherwise a message to show.
  Future<String?> add(String tripId, PhotoSource source) async {
    if (_busy.contains(tripId)) return null;
    if (photosFor(tripId).length >= maxPerTrip) {
      return 'You can keep up to $maxPerTrip photos per trip.';
    }
    final epoch = _epoch;
    _busy.add(tripId);
    notifyListeners();
    try {
      final path = await _picker.pick(source);
      if (path == null) return null; // cancelled
      final photo = await _store.add(tripId, path);
      if (epoch == _epoch) {
        _photos[tripId] = [photo, ...photosFor(tripId)];
        _loaded.add(tripId);
      }
      return null;
    } on PhotoPickerException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not save the photo. Check your free storage and try again.';
    } finally {
      if (epoch == _epoch) _busy.remove(tripId);
      notifyListeners();
    }
  }

  /// Returns null on success, otherwise a message to show.
  Future<String?> remove(TripPhoto photo) async {
    final epoch = _epoch;
    try {
      await _store.remove(photo);
      if (epoch == _epoch) {
        _photos[photo.tripId] = [
          for (final p in photosFor(photo.tripId))
            if (p != photo) p
        ];
        notifyListeners();
      }
      return null;
    } catch (_) {
      return 'Could not delete the photo. Please try again.';
    }
  }

  /// Drops in-memory state on sign-out (photos stay on the device). Silent:
  /// it runs from a provider update during build.
  void clear() {
    _epoch++;
    _photos.clear();
    _loaded.clear();
    _busy.clear();
  }
}
