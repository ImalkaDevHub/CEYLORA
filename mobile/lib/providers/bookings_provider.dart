import 'package:flutter/foundation.dart';

import '../models/booking.dart';
import '../services/api_client.dart';
import '../services/stay_services.dart';
import 'trips_provider.dart' show LoadState;

class BookingsProvider extends ChangeNotifier {
  final BookingService _service;
  BookingsProvider(this._service);

  List<Booking> _items = const [];
  LoadState _state = LoadState.idle;
  String? _error;
  bool _creating = false;
  final Set<String> _cancelling = {};

  // Bumped by clear() so a request that finishes after sign-out is dropped.
  int _epoch = 0;

  List<Booking> get items => _items;
  LoadState get state => _state;
  String? get error => _error;

  /// True while a booking request is in flight.
  bool get creating => _creating;
  bool isCancelling(String id) => _cancelling.contains(id);

  Booking? byId(String id) {
    for (final b in _items) {
      if (b.id == id) return b;
    }
    return null;
  }

  List<Booking> forTrip(String tripId) =>
      [for (final b in _items) if (b.tripId == tripId) b];

  Future<void> load() async {
    final epoch = _epoch;
    _state = LoadState.loading;
    _error = null;
    notifyListeners();
    try {
      final items = await _service.mine();
      if (epoch != _epoch) return;
      _items = _newestFirst(items);
      _state = LoadState.loaded;
    } on ApiException catch (e) {
      if (epoch != _epoch) return;
      _error = e.message;
      _state = LoadState.failed;
    }
    notifyListeners();
  }

  /// Books one stay. Returns the booking, or an error message.
  Future<(Booking?, String?)> create({
    required String tripId,
    required String accommodationId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int rooms,
    required int guests,
    String? notes,
  }) async {
    if (_creating) return (null, null);
    final epoch = _epoch;
    _creating = true;
    notifyListeners();
    try {
      final booking = await _service.create(
        tripId: tripId,
        accommodationId: accommodationId,
        checkIn: checkIn,
        checkOut: checkOut,
        rooms: rooms,
        guests: guests,
        notes: notes,
      );
      if (epoch == _epoch) {
        _items = _newestFirst([booking, ..._items]);
        _state = LoadState.loaded;
      }
      return (booking, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } finally {
      if (epoch == _epoch) _creating = false;
      notifyListeners();
    }
  }

  /// Cancels a booking. Returns null on success, otherwise a message.
  Future<String?> cancel(String id) async {
    if (_cancelling.contains(id)) return null;
    final epoch = _epoch;
    _cancelling.add(id);
    notifyListeners();
    try {
      final updated = await _service.cancel(id);
      if (epoch == _epoch) {
        _items = [for (final b in _items) b.id == id ? updated : b];
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      if (epoch == _epoch) _cancelling.remove(id);
      notifyListeners();
    }
  }

  /// Silent: runs from a provider update during build.
  void clear() {
    _epoch++;
    _items = const [];
    _state = LoadState.idle;
    _error = null;
    _creating = false;
    _cancelling.clear();
  }

  static List<Booking> _newestFirst(List<Booking> list) =>
      [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
