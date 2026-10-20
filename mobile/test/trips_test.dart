import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/providers/trips_provider.dart';
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/token_storage.dart';
import 'package:mobile/services/trip_service.dart';
import 'package:mobile/utils/format.dart';

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

AuthSession _session() => AuthSession(
      token: 'jwt-token',
      email: 'sam@example.com',
      fullName: 'Sam Traveler',
      role: 'Traveler',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

Map<String, dynamic> _trip(String id,
        {String title = 'Kandy escape',
        String status = 'Draft',
        String start = '2026-11-01T00:00:00Z',
        String end = '2026-11-04T00:00:00Z',
        num budget = 150000}) =>
    {
      'id': id,
      'title': title,
      'startDate': start,
      'endDate': end,
      'budget': budget,
      'status': status,
      'travelerName': 'Sam Traveler',
    };

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('formatters', () {
    test('formatDate uses the UTC calendar day', () {
      expect(formatDate(DateTime.utc(2026, 11, 1)), '1 Nov 2026');
    });

    test('toApiDate pads month and day', () {
      expect(toApiDate(DateTime(2026, 3, 5)), '2026-03-05');
    });

    test('formatLkr groups thousands and keeps cents only when present', () {
      expect(formatLkr(150000), 'LKR 150,000');
      expect(formatLkr(999), 'LKR 999');
      expect(formatLkr(1234567.5), 'LKR 1,234,567.50');
    });
  });

  group('TripsProvider', () {
    TripsProvider build(MockClient client) {
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      api.setToken('jwt-token');
      return TripsProvider(TripService(api));
    }

    test('load sorts newest start date first', () async {
      final provider = build(MockClient((_) async => _json([
            _trip('a', start: '2026-10-01T00:00:00Z'),
            _trip('b', start: '2026-12-01T00:00:00Z'),
          ], 200)));

      await provider.load();

      expect(provider.state, LoadState.loaded);
      expect(provider.trips.map((t) => t.id), ['b', 'a']);
    });

    test('load failure keeps the API message and failed state', () async {
      final provider = build(MockClient((_) async => _json({}, 403)));

      await provider.load();

      expect(provider.state, LoadState.failed);
      expect(provider.error, "You don't have permission to do that.");
    });

    test('a non-list body becomes a clean error, not a crash', () async {
      final provider = build(MockClient((_) async => _json({'x': 1}, 200)));

      await provider.load();

      expect(provider.state, LoadState.failed);
      expect(provider.error, contains('unexpected response'));
    });

    test('create posts date-only strings and prepends the new trip', () async {
      late http.Request seen;
      final provider = build(MockClient((req) async {
        seen = req;
        return _json(_trip('new', title: 'Galle weekend'), 201);
      }));

      final error = await provider.create(
        title: 'Galle weekend',
        startDate: DateTime(2026, 11, 1),
        endDate: DateTime(2026, 11, 4),
        budget: 150000,
      );

      expect(error, isNull);
      expect(seen.url.path, '/api/trips');
      expect(seen.headers['Authorization'], 'Bearer jwt-token');
      expect(jsonDecode(seen.body), {
        'title': 'Galle weekend',
        'startDate': '2026-11-01',
        'endDate': '2026-11-04',
        'budget': 150000,
      });
      expect(provider.trips.first.id, 'new');
    });

    test('create returns the server validation message', () async {
      final provider = build(MockClient((_) async =>
          _json({'message': 'End date cannot be before start date.'}, 400)));

      final error = await provider.create(
        title: 'x',
        startDate: DateTime(2026, 11, 4),
        endDate: DateTime(2026, 11, 1),
        budget: 1,
      );

      expect(error, 'End date cannot be before start date.');
      expect(provider.trips, isEmpty);
    });

    test('submit replaces the trip with the updated status', () async {
      var call = 0;
      final provider = build(MockClient((req) async {
        call++;
        if (call == 1) return _json([_trip('a')], 200);
        expect(req.url.path, '/api/trips/a/submit');
        return _json(_trip('a', status: 'Submitted'), 200);
      }));
      await provider.load();
      expect(provider.byId('a')!.isDraft, isTrue);

      final error = await provider.submit('a');

      expect(error, isNull);
      expect(provider.byId('a')!.status, 'Submitted');
      expect(provider.isSubmitting('a'), isFalse);
    });

    test('submit surfaces the not-in-Draft message', () async {
      final provider = build(MockClient((_) async => _json(
          {'message': 'Trip not found, not yours, or not in Draft status.'},
          400)));

      final error = await provider.submit('a');

      expect(error, contains('not in Draft'));
    });

    test('clear drops cached trips', () async {
      final provider =
          build(MockClient((_) async => _json([_trip('a')], 200)));
      await provider.load();

      provider.clear();

      expect(provider.trips, isEmpty);
      expect(provider.state, LoadState.idle);
    });
  });

  group('My trips UI', () {
    // Minimal in-memory backend for /api/trips.
    MockClient fakeBackend(List<Map<String, dynamic>> db) =>
        MockClient((req) async {
          final path = req.url.path;
          if (req.method == 'GET' && path == '/api/trips/mine') {
            return _json(db, 200);
          }
          if (req.method == 'POST' && path == '/api/trips') {
            final body = jsonDecode(req.body) as Map<String, dynamic>;
            final created = _trip('t${db.length + 1}',
                title: body['title'] as String,
                start: '${body['startDate']}T00:00:00Z',
                end: '${body['endDate']}T00:00:00Z',
                budget: body['budget'] as num);
            db.add(created);
            return _json(created, 201);
          }
          if (req.method == 'POST' && path.endsWith('/submit')) {
            final id = path.split('/')[3];
            final i = db.indexWhere((t) => t['id'] == id);
            db[i] = {...db[i], 'status': 'Submitted'};
            return _json(db[i], 200);
          }
          return _json({}, 404);
        });

    Future<void> pumpSignedIn(WidgetTester tester, MockClient client) async {
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      await tester
          .pumpWidget(CeyloraApp(api: api, store: _MemoryStore(_session())));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the traveler\'s trips on the My trips tab',
        (tester) async {
      await pumpSignedIn(
          tester, fakeBackend([_trip('t1'), _trip('t2', title: 'Ella hike')]));

      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();

      expect(find.text('Kandy escape'), findsOneWidget);
      expect(find.text('Ella hike'), findsOneWidget);
      expect(find.text('1 Nov 2026 → 4 Nov 2026 · 4 days'), findsNWidgets(2));
      expect(find.text('LKR 150,000'), findsNWidgets(2));
    });

    testWidgets('shows the empty state when there are no trips',
        (tester) async {
      await pumpSignedIn(tester, fakeBackend([]));

      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('No trips yet'), findsOneWidget);
    });

    testWidgets('shows an error with retry when loading fails',
        (tester) async {
      await pumpSignedIn(tester, MockClient((_) async => _json({}, 500)));

      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();

      expect(find.text('Something went wrong on the server.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('create form blocks empty and invalid input', (tester) async {
      await pumpSignedIn(tester, fakeBackend([]));
      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('New trip'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create trip'));
      await tester.pump();

      expect(find.text('Give your trip a title'), findsOneWidget);
      expect(find.text('Pick a start and end date'), findsOneWidget);
      expect(find.text('Enter your budget'), findsOneWidget);

      await tester.enterText(find.bySemanticsLabel('Budget'), '0');
      await tester.tap(find.text('Create trip'));
      await tester.pump();
      expect(find.text('Budget must be more than 0'), findsOneWidget);
    });

    testWidgets('create a trip, open it, and submit it', (tester) async {
      final db = <Map<String, dynamic>>[];
      await pumpSignedIn(tester, fakeBackend(db));
      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('New trip'));
      await tester.pumpAndSettle();
      await tester.enterText(find.bySemanticsLabel('Trip title'), 'Sigiriya');
      await tester.enterText(find.bySemanticsLabel('Budget'), '90000');

      // Pick a start date, then an end date, in the date picker dialog.
      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create trip'));
      await tester.pumpAndSettle();

      // Back on the list with the new trip.
      expect(db, hasLength(1));
      expect(find.text('Sigiriya'), findsOneWidget);
      expect(find.text('Draft'), findsOneWidget);

      await tester.tap(find.text('Sigiriya'));
      await tester.pumpAndSettle();
      expect(find.text('Trip details'), findsOneWidget);

      await tester.tap(find.text('Submit trip'));
      await tester.pumpAndSettle();

      expect(find.text('Trip submitted.'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Submit trip'), findsNothing);
    });

    testWidgets('signing out clears trips for the next user', (tester) async {
      await pumpSignedIn(tester, fakeBackend([_trip('t1')]));
      await tester.tap(find.text('My trips').last);
      await tester.pumpAndSettle();
      expect(find.text('Kandy escape'), findsOneWidget);

      await tester.tap(find.byTooltip('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      final provider = tester
          .element(find.byType(Scaffold).first)
          .read<TripsProvider>();
      expect(provider.trips, isEmpty);
    });
  });
}
