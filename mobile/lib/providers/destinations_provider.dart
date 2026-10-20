import 'package:flutter/foundation.dart';

import '../models/destination.dart';
import '../services/api_client.dart';
import '../services/destination_service.dart';
import 'trips_provider.dart' show LoadState;

enum DestinationSort {
  nameAsc('Name (A–Z)', 'Name', false),
  nameDesc('Name (Z–A)', 'Name', true),
  regionAsc('Region (A–Z)', 'Region', false),
  regionDesc('Region (Z–A)', 'Region', true);

  final String label;
  final String sortBy;
  final bool descending;
  const DestinationSort(this.label, this.sortBy, this.descending);
}

/// Search / filter / sort / paginate state for the Destinations tab.
class DestinationsProvider extends ChangeNotifier {
  static const pageSize = 10;

  final DestinationService _service;
  DestinationsProvider(this._service);

  final List<Destination> _items = [];
  int _total = 0;
  int _page = 0; // last page loaded
  LoadState _state = LoadState.idle;
  String? _error;
  bool _loadingMore = false;
  String? _moreError;

  String _search = '';
  String? _category;
  DestinationSort _sort = DestinationSort.nameAsc;

  // Bumped on every reload so a slow, older response can never overwrite a newer one.
  int _generation = 0;

  List<Destination> get items => List.unmodifiable(_items);
  int get total => _total;
  LoadState get state => _state;
  String? get error => _error;
  bool get loadingMore => _loadingMore;
  String? get moreError => _moreError;
  String get search => _search;
  String? get category => _category;
  DestinationSort get sort => _sort;
  bool get hasMore => _items.length < _total;

  /// Fetches the first page with the current filters.
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
  Future<void> setCategory(String? value) {
    if (value == _category) return Future.value();
    _category = value;
    return load();
  }

  Future<void> setSort(DestinationSort value) {
    if (value == _sort) return Future.value();
    _sort = value;
    return load();
  }

  Future<DestinationSummary> summaryFor(String id) => _service.summary(id);

  Destination? byId(String id) {
    for (final d in _items) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Drops cached data and filters on sign-out. Silent for the same reason as
  /// [TripsProvider.clear]: it runs during a provider update.
  void clear() {
    _generation++;
    _items.clear();
    _total = 0;
    _page = 0;
    _state = LoadState.idle;
    _error = null;
    _moreError = null;
    _loadingMore = false;
    _search = '';
    _category = null;
    _sort = DestinationSort.nameAsc;
  }

  Future<DestinationPage> _fetch(int page) => _service.list(
        search: _search,
        category: _category,
        sortBy: _sort.sortBy,
        descending: _sort.descending,
        page: page,
        pageSize: pageSize,
      );
}
