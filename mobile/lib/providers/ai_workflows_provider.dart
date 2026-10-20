import 'package:flutter/foundation.dart';

import '../models/ai_workflow.dart';
import '../services/ai_workflow_service.dart';
import '../services/api_client.dart';
import 'trips_provider.dart' show LoadState;

class AiWorkflowsProvider extends ChangeNotifier {
  final AiWorkflowService _service;
  AiWorkflowsProvider(this._service);

  List<AiWorkflow> _items = const [];
  LoadState _state = LoadState.idle;
  String? _error;
  bool _starting = false;
  final Set<String> _refreshing = {};

  /// Bumped by [clear] so a response that lands after sign-out is dropped
  /// instead of leaking into the next user's session.
  int _epoch = 0;

  /// Newest first.
  List<AiWorkflow> get items => _items;
  LoadState get state => _state;
  String? get error => _error;
  bool get starting => _starting;

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

  /// Runs the planner and returns `(workflow, null)` on success or
  /// `(null, message)` on failure. A second call while one is running is
  /// ignored and returns `(null, null)`.
  Future<(AiWorkflow?, String?)> start({
    required String goal,
    required int days,
    required double budget,
    required List<String> interests,
    DateTime? startDate,
  }) async {
    if (_starting) return (null, null);
    final epoch = _epoch;
    _starting = true;
    notifyListeners();
    try {
      final workflow = await _service.start(
        goal: goal,
        days: days,
        budget: budget,
        interests: interests,
        startDate: startDate,
      );
      if (epoch == _epoch) {
        _items = _newestFirst([workflow, ..._items]);
        _state = LoadState.loaded;
      }
      return (workflow, null);
    } on ApiException catch (e) {
      return (null, e.message);
    } finally {
      if (epoch == _epoch) _starting = false;
      notifyListeners();
    }
  }

  /// Re-reads one workflow (e.g. to see an operator's decision). Returns null
  /// on success or a user-facing error message. Overlapping calls for the same
  /// id are skipped.
  Future<String?> refresh(String id) async {
    if (!_refreshing.add(id)) return null;
    final epoch = _epoch;
    try {
      final updated = await _service.get(id);
      if (epoch != _epoch) return null;
      final exists = _items.any((w) => w.id == id);
      _items = exists
          ? [for (final w in _items) w.id == id ? updated : w]
          : _newestFirst([updated, ..._items]);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      _refreshing.remove(id);
    }
  }

  AiWorkflow? byId(String id) {
    for (final w in _items) {
      if (w.id == id) return w;
    }
    return null;
  }

  /// Drops cached data (called on sign-out so the next user never sees it).
  /// Deliberately silent, like the other providers.
  void clear() {
    _epoch++;
    _items = const [];
    _state = LoadState.idle;
    _error = null;
    _starting = false;
    _refreshing.clear();
  }

  List<AiWorkflow> _newestFirst(List<AiWorkflow> list) =>
      [...list]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}
