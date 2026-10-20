import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/auth_service.dart';
import 'package:mobile/services/token_storage.dart';

class _MemoryStore implements SessionStore {
  AuthSession? saved;
  _MemoryStore([this.saved]);

  @override
  Future<AuthSession?> read() async => saved;
  @override
  Future<void> write(AuthSession session) async => saved = session;
  @override
  Future<void> clear() async => saved = null;
}

Map<String, dynamic> _authJson({DateTime? expiresAt}) => {
      'token': 'jwt-token',
      'email': 'sam@example.com',
      'fullName': 'Sam Traveler',
      'role': 'Traveler',
      'expiresAt':
          (expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)))
              .toIso8601String(),
    };

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

AuthProvider _provider(MockClient client, SessionStore store) {
  final api = ApiClient(httpClient: client, baseUrl: 'http://test');
  return AuthProvider(api: api, service: AuthService(api), store: store);
}

void main() {
  group('AuthProvider', () {
    test('login success stores session and signs in', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return _json(_authJson(), 200);
      });
      final store = _MemoryStore();
      final auth = _provider(client, store);

      final ok = await auth.login(' sam@example.com ', 'secret1');

      expect(ok, isTrue);
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.session!.role, 'Traveler');
      expect(store.saved?.token, 'jwt-token');
      expect(seen.url.path, '/api/auth/login');
      expect(jsonDecode(seen.body), {
        'email': 'sam@example.com',
        'password': 'secret1',
      });
    });

    test('login failure surfaces the API message and stays signed out',
        () async {
      final client = MockClient((_) async =>
          _json({'message': 'Invalid email or password.'}, 401));
      final store = _MemoryStore();
      final auth = _provider(client, store);

      final ok = await auth.login('sam@example.com', 'wrong');

      expect(ok, isFalse);
      expect(auth.error, 'Invalid email or password.');
      expect(auth.status, isNot(AuthStatus.signedIn));
      expect(store.saved, isNull);
    });

    test('register always asks for the Traveler role', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return _json(_authJson(), 200);
      });
      final auth = _provider(client, _MemoryStore());

      await auth.register('Sam Traveler', 'sam@example.com', 'secret1');

      expect(jsonDecode(seen.body)['roleName'], 'Traveler');
      expect(auth.status, AuthStatus.signedIn);
    });

    test('duplicate email on register shows the conflict message', () async {
      final client = MockClient((_) async => _json(
          {'message': 'Email already registered or invalid role.'}, 409));
      final auth = _provider(client, _MemoryStore());

      final ok = await auth.register('Sam', 'sam@example.com', 'secret1');

      expect(ok, isFalse);
      expect(auth.error, contains('already registered'));
    });

    test('restore signs in from a valid saved session', () async {
      final saved = AuthSession.fromJson(_authJson());
      final auth =
          _provider(MockClient((_) async => _json({}, 200)), _MemoryStore(saved));

      await auth.restore();

      expect(auth.status, AuthStatus.signedIn);
      expect(auth.session!.email, 'sam@example.com');
    });

    test('restore discards an expired saved session', () async {
      final expired = AuthSession.fromJson(_authJson(
          expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1))));
      final store = _MemoryStore(expired);
      final auth = _provider(MockClient((_) async => _json({}, 200)), store);

      await auth.restore();

      expect(auth.status, AuthStatus.signedOut);
      expect(store.saved, isNull);
    });

    test('a 401 on an authenticated call signs the user out', () async {
      final client = MockClient((req) async => req.url.path == '/api/auth/login'
          ? _json(_authJson(), 200)
          : _json({'message': 'nope'}, 401));
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      final store = _MemoryStore();
      final auth =
          AuthProvider(api: api, service: AuthService(api), store: store);
      await auth.login('sam@example.com', 'secret1');
      expect(auth.status, AuthStatus.signedIn);

      await expectLater(api.get('/api/trips/mine'), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);

      expect(auth.status, AuthStatus.signedOut);
      expect(store.saved, isNull);
      expect(auth.error, contains('expired'));
    });
  });

  group('CeyloraApp', () {
    testWidgets('shows login, then the home screen after signing in',
        (tester) async {
      final client = MockClient((_) async => _json(_authJson(), 200));
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');

      await tester.pumpWidget(CeyloraApp(api: api, store: _MemoryStore()));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Email'), 'sam@example.com');
      await tester.enterText(find.bySemanticsLabel('Password'), 'secret1');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Welcome, Sam Traveler'), findsOneWidget);
      expect(find.text('Traveler'), findsOneWidget);
    });

    testWidgets('blocks empty submit with validation messages',
        (tester) async {
      final api = ApiClient(
          httpClient: MockClient((_) async => _json(_authJson(), 200)),
          baseUrl: 'http://test');

      await tester.pumpWidget(CeyloraApp(api: api, store: _MemoryStore()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in'));
      await tester.pump();

      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
    });
  });
}
