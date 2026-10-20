import 'package:flutter/foundation.dart';

import '../models/review.dart';
import '../services/api_client.dart';
import '../services/stay_services.dart';
import 'trips_provider.dart' show LoadState;

/// Everything the UI needs about one stay's reviews.
class StayReviews {
  final List<Review> items;
  final int total;
  final LoadState state;
  final String? error;
  final bool loadingMore;
  final String? moreError;

  const StayReviews({
    this.items = const [],
    this.total = 0,
    this.state = LoadState.idle,
    this.error,
    this.loadingMore = false,
    this.moreError,
  });

  bool get hasMore => items.length < total;

  StayReviews copyWith({
    List<Review>? items,
    int? total,
    LoadState? state,
    String? error,
    bool clearError = false,
    bool? loadingMore,
    String? moreError,
    bool clearMoreError = false,
  }) =>
      StayReviews(
        items: items ?? this.items,
        total: total ?? this.total,
        state: state ?? this.state,
        error: clearError ? null : (error ?? this.error),
        loadingMore: loadingMore ?? this.loadingMore,
        moreError: clearMoreError ? null : (moreError ?? this.moreError),
      );
}

class ReviewsProvider extends ChangeNotifier {
  static const pageSize = 5;

  final ReviewService _service;
  ReviewsProvider(this._service);

  final Map<String, StayReviews> _byStay = {};
  final Map<String, int> _pages = {};
  final Set<String> _submitting = {};
  int _epoch = 0;

  StayReviews reviewsFor(String accommodationId) =>
      _byStay[accommodationId] ?? const StayReviews();

  bool isSubmitting(String accommodationId) => _submitting.contains(accommodationId);

  Future<void> load(String id) async {
    final epoch = _epoch;
    _byStay[id] = reviewsFor(id).copyWith(state: LoadState.loading, clearError: true);
    notifyListeners();
    try {
      final page = await _service.list(id, page: 1, pageSize: pageSize);
      if (epoch != _epoch) return;
      _pages[id] = 1;
      _byStay[id] = StayReviews(
          items: page.items, total: page.totalCount, state: LoadState.loaded);
    } on ApiException catch (e) {
      if (epoch != _epoch) return;
      _byStay[id] = reviewsFor(id).copyWith(state: LoadState.failed, error: e.message);
    }
    notifyListeners();
  }

  Future<void> loadMore(String id) async {
    final current = reviewsFor(id);
    if (current.loadingMore || current.state != LoadState.loaded || !current.hasMore) {
      return;
    }
    final epoch = _epoch;
    _byStay[id] = current.copyWith(loadingMore: true, clearMoreError: true);
    notifyListeners();
    try {
      final page = await _service.list(id, page: (_pages[id] ?? 1) + 1, pageSize: pageSize);
      if (epoch != _epoch) return;
      _pages[id] = page.page;
      _byStay[id] = reviewsFor(id).copyWith(
          items: [...reviewsFor(id).items, ...page.items],
          total: page.totalCount,
          loadingMore: false);
    } on ApiException catch (e) {
      if (epoch != _epoch) return;
      _byStay[id] = reviewsFor(id).copyWith(loadingMore: false, moreError: e.message);
    }
    notifyListeners();
  }

  /// Posts a review. Returns null on success, otherwise the API's message
  /// (e.g. "You can review a place only after your stay there has ended.").
  Future<String?> add(String id, {required int rating, required String comment}) async {
    if (_submitting.contains(id)) return null;
    final epoch = _epoch;
    _submitting.add(id);
    notifyListeners();
    try {
      await _service.create(id, rating: rating, comment: comment);
    } on ApiException catch (e) {
      return e.message;
    } finally {
      if (epoch == _epoch) _submitting.remove(id);
      notifyListeners();
    }
    // Reload so the new review shows in its place and the total is right.
    await load(id);
    return null;
  }

  /// Silent: runs from a provider update during build.
  void clear() {
    _epoch++;
    _byStay.clear();
    _pages.clear();
    _submitting.clear();
  }
}
