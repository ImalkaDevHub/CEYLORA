// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../models/auth_session.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/token_storage.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthProvider extends ChangeNotifier {
  final ApiClient _api;
  final AuthService _service;
  final SessionStore _store;

  AuthStatus _status = AuthStatus.unknown;
  AuthSession? _session;
  bool _busy = false;
  String? _error;

  AuthProvider({
    required ApiClient api,
    required AuthService service,
    required SessionStore store,
  })  : _api = api,
        _service = service,
        _store = store {
    // An expired/invalid token on any authenticated call signs the user out.
    _api.onUnauthorized =
        () => signOut(message: 'Your session expired. Please sign in again.');
  }

  AuthStatus get status => _status;
  AuthSession? get session => _session;
  bool get busy => _busy;
  String? get error => _error;

  /// Restores a saved session on app start, if it is still valid.
  Future<void> restore() async {
    final saved = await _store.read();
    if (saved != null && !saved.isExpired) {
      _apply(saved);
    } else {
      if (saved != null) await _store.clear();
      _status = AuthStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) =>
      _run(() => _service.login(email.trim(), password));

  Future<bool> register(String fullName, String email, String password) =>
      _run(() => _service.register(fullName.trim(), email.trim(), password));

  Future<void> signOut({String? message}) async {
    _api.setToken(null);
    _session = null;
    _status = AuthStatus.signedOut;
    _error = message;
    await _store.clear();
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  Future<bool> _run(Future<AuthSession> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final session = await action();
      await _store.write(session);
      _apply(session);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _apply(AuthSession session) {
    _session = session;
    _api.setToken(session.token);
    _status = AuthStatus.signedIn;
  }
}
