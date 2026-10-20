import 'package:flutter/foundation.dart';

import '../models/accommodation.dart';
import '../services/api_client.dart';
import '../services/stay_services.dart';
import 'trips_provider.dart' show LoadState;

enum StaySort {
  nameAsc('Name (A–Z)', 'Name', false),
  priceAsc('Price: low to high', 'Price', false),
  priceDesc('Price: high to low', 'Price', true),
  topRated('Top rated', 'Rating', true);

  final String label;
  final String sortBy;
  final bool descending;
  const StaySort(this.label, this.sortBy, this.descending);
}

/// Search / filter / sort / paginate state for the Stays tab, plus a cache of stays
/// seen so far (so a detail screen can open one without refetching).
class AccommodationsProvider extends ChangeNotifier {
  static const pageSize = 10;

  final AccommodationService _service;
  AccommodationsProvider(this._service);

  final List<Accommodation> _items = [];
  final Map<String, Accommodation> _cache = {};
  int _total = 0;
  int _page = 0;
  LoadState _state = LoadState.idle;
  String? _error;
  bool _loadingMore = false;
  String? _moreError;

  String _search = '';
  String? _type;
  StaySort _sort = StaySort.nameAsc;

  // Bumped on every reload so a slow, older response can never overwrite a newer one.
  int _generation = 0;

  List<Accommodation> get items => List.unmodifiable(_items);
  int get total => _total;
  LoadState get state => _state;
  String? get error => _error;
  bool get loadingMore => _loadingMore;
  String? get moreError => _moreError;
  String get search => _search;
  String? get type => _type;
  StaySort get sort => _sort;
  bool get hasMore => _items.length < _total;

  Accommodation? byId(String id) => _cache[id];

  Future<void> load() async {
    final gen = ++_generation;
    _state = LoadState.loading;
    _error = null;
    _moreError = null;
    _loadingMore = false;
    notifyListeners();
    try {
      final page = await _fetch(1);
      if (gen != _generation) return;
      _items
        ..clear()
        ..addAll(page.items);
      for (final a in page.items) {
        _cache[a.id] = a;
      }
      _total = page.totalCount;
      _page = 1;
      _state = LoadState.loaded;
    } on ApiException catch (e) {
      if (gen != _generation) return;
      _items.clear();
      _total = 0;
      _page = 0;
      _error = e.message;
      _state = LoadState.failed;
    }
    notifyListeners();
  }

  /// Appends the next page (infinite scroll). No-op while busy or at the end.
  Future<void> loadMore() async {
    if (_loadingMore || _state != LoadState.loaded || !hasMore) return;
    final gen = _generation;
    _loadingMore = true;
    _moreError = null;
    notifyListeners();
    try {
      final page = await _fetch(_page + 1);
      if (gen != _generation) return;
      _items.addAll(page.items);
      for (final a in page.items) {
        _cache[a.id] = a;
      }
      _total = page.totalCount;
      _page += 1;
    } on ApiException catch (e) {
      if (gen != _generation) return;
      _moreError = e.message;
    }
    _loadingMore = false;
    notifyListeners();
  }

  Future<void> setSearch(String value) {
    final trimmed = value.trim();
    if (trimmed == _search) return Future.value();
    _search = trimmed;
    return load();
  }

  /// Pass null for "All".
  Future<void> setType(String? value) {
    if (value == _type) return Future.value();
    _type = value;
    return load();
  }

  Future<void> setSort(StaySort value) {
    if (value == _sort) return Future.value();
    _sort = value;
    return load();
  }

  /// Loads one stay (e.g. opened from a booking, or to refresh its rating).
  /// Returns null on success, otherwise a message.
  Future<String?> fetch(String id) async {
    try {
      final stay = await _service.get(id);
      _cache[id] = stay;
      final index = _items.indexWhere((a) => a.id == id);
      if (index != -1) _items[index] = stay;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<AvailabilityQuote> quote({
    required String id,
    required DateTime checkIn,
    required DateTime checkOut,
    required int rooms,
  }) =>
      _service.quote(id: id, checkIn: checkIn, checkOut: checkOut, rooms: rooms);

  /// Silent: runs from a provider update during build (see [TripsProvider.clear]).
  void clear() {
    _generation++;
    _items.clear();
    _cache.clear();
    _total = 0;
    _page = 0;
    _state = LoadState.idle;
    _error = null;
    _moreError = null;
    _loadingMore = false;
    _search = '';
    _type = null;
    _sort = StaySort.nameAsc;
  }

  Future<AccommodationPage> _fetch(int page) => _service.list(
        search: _search,
        type: _type,
        sortBy: _sort.sortBy,
        descending: _sort.descending,
        page: page,
        pageSize: pageSize,
      );
}
