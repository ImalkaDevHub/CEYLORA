import 'package:flutter/foundation.dart';

import '../models/trip.dart';
import '../services/api_client.dart';
import '../services/trip_service.dart';

enum LoadState { idle, loading, loaded, failed }

class TripsProvider extends ChangeNotifier {
  final TripService _service;
  TripsProvider(this._service);

  List<Trip> _trips = const [];
  LoadState _state = LoadState.idle;
  String? _error;
  final Set<String> _submitting = {};

  List<Trip> get trips => _trips;
  LoadState get state => _state;
  String? get error => _error;
  bool isSubmitting(String id) => _submitting.contains(id);

  Future<void> load() async {
    _state = LoadState.loading;
    _error = null;
    notifyListeners();
    try {
      final trips = await _service.myTrips();
      // Newest start date first.
      _trips = [...trips]..sort((a, b) => b.startDate.compareTo(a.startDate));
      _state = LoadState.loaded;
    } on ApiException catch (e) {
      _error = e.message;
      _state = LoadState.failed;
    }
    notifyListeners();
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> create({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required double budget,
  }) async {
    try {
      final trip = await _service.create(
        title: title,
        startDate: startDate,
        endDate: endDate,
        budget: budget,
      );
      _trips = [trip, ..._trips];
      _state = LoadState.loaded;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Returns null on success, or a user-facing error message.
  Future<String?> submit(String tripId) async {
    if (_submitting.contains(tripId)) return null;
    _submitting.add(tripId);
    notifyListeners();
    try {
      final updated = await _service.submit(tripId);
      _trips = [for (final t in _trips) t.id == updated.id ? updated : t];
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      _submitting.remove(tripId);
      notifyListeners();
    }
  }

  /// Drops cached data (called on sign-out so the next user never sees it).
  /// Deliberately silent: it runs from a provider update during build, and the
  /// signed-in screens that listen are already being torn down.
  void clear() {
    _trips = const [];
    _state = LoadState.idle;
    _error = null;
    _submitting.clear();
  }

  Trip? byId(String id) {
    for (final t in _trips) {
      if (t.id == id) return t;
    }
    return null;
  }
}
