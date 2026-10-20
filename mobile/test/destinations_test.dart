import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/main.dart';
import 'package:mobile/models/auth_session.dart';
import 'package:mobile/models/destination.dart';
import 'package:mobile/providers/destinations_provider.dart';
import 'package:mobile/providers/trips_provider.dart' show LoadState;
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/destination_service.dart';
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

AuthSession _session() => AuthSession(
      token: 'jwt-token',
      email: 'sam@example.com',
      fullName: 'Sam Traveler',
      role: 'Traveler',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Map<String, dynamic> _dest(int n, {String? category, String? region}) => {
      'id': 'd$n',
      'name': 'Place ${n.toString().padLeft(2, '0')}',
      'region': region ?? 'Region ${n % 3}',
      'description': 'About place $n',
      'category': category ?? travelCategories[n % travelCategories.length],
      'imageUrl': null,
      'isActive': true,
    };

/// In-memory stand-in for GET /api/destinations (+ /summary): ILIKE search on
/// name/region, category filter, sort and paging, like DestinationService.
MockClient fakeBackend(List<Map<String, dynamic>> all,
        {List<http.Request>? log}) =>
    MockClient((req) {
      log?.add(req);
      return destHandler(all, req);
    });

Future<http.Response> destHandler(
    List<Map<String, dynamic>> all, http.Request req) async {
  {
    final path = req.url.path;
    if (path == '/api/destinations') {
      final q = req.url.queryParameters;
      var rows = [...all];
      final search = q['search']?.toLowerCase();
      if (search != null) {
        rows = rows
            .where((d) =>
                (d['name'] as String).toLowerCase().contains(search) ||
                (d['region'] as String).toLowerCase().contains(search))
            .toList();
      }
      if (q['category'] != null) {
        rows = rows.where((d) => d['category'] == q['category']).toList();
      }
      final key = q['sortBy'] == 'Region' ? 'region' : 'name';
      rows.sort((a, b) => (a[key] as String).compareTo(b[key] as String));
      if (q['sortDescending'] == 'true') rows = rows.reversed.toList();
      final page = int.parse(q['page']!);
      final size = int.parse(q['pageSize']!);
      return _json({
        'items': rows.skip((page - 1) * size).take(size).toList(),
        'totalCount': rows.length,
        'page': page,
        'pageSize': size,
      }, 200);
    }
    if (path.endsWith('/summary')) {
      return _json({
        'destinationId': path.split('/')[3],
        'name': 'x',
        'experienceCount': 3,
        'minPrice': 5000,
        'maxPrice': 25000,
        'averagePrice': 12500.5,
      }, 200);
    }
    return _json({}, 404);
  }
}

DestinationsProvider _provider(MockClient client) {
  final api = ApiClient(httpClient: client, baseUrl: 'http://test');
  api.setToken('jwt-token');
  return DestinationsProvider(DestinationService(api));
}

void main() {
  final all = [for (var i = 1; i <= 25; i++) _dest(i)];

  test('categoryLabel prettifies CityLife only', () {
    expect(categoryLabel('CityLife'), 'City life');
    expect(categoryLabel('Beach'), 'Beach');
  });

  group('DestinationService', () {
    test('sends search, category, sort and paging as query parameters',
        () async {
      final log = <http.Request>[];
      final api = ApiClient(
          httpClient: fakeBackend(all, log: log), baseUrl: 'http://test');
      api.setToken('jwt-token');

      await DestinationService(api).list(
        search: '  ella ',
        category: 'Nature',
        sortBy: 'Region',
        descending: true,
        page: 2,
        pageSize: 5,
      );

      expect(log.single.headers['Authorization'], 'Bearer jwt-token');
      expect(log.single.url.queryParameters, {
        'search': 'ella',
        'category': 'Nature',
        'sortBy': 'Region',
        'sortDescending': 'true',
        'page': '2',
        'pageSize': '5',
      });
    });

    test('omits blank search and null category', () async {
      final log = <http.Request>[];
      final api = ApiClient(
          httpClient: fakeBackend(all, log: log), baseUrl: 'http://test');

      await DestinationService(api).list(search: '   ');

      expect(log.single.url.queryParameters.containsKey('search'), isFalse);
      expect(log.single.url.queryParameters.containsKey('category'), isFalse);
    });

    test('ignores non-http image URLs', () {
      final d = Destination.fromJson({
        ..._dest(1),
        'imageUrl': 'javascript:alert(1)',
      });
      expect(d.imageUrl, isNull);
      final ok = Destination.fromJson({
        ..._dest(1),
        'imageUrl': 'https://img.example/ella.jpg',
      });
      expect(ok.imageUrl, 'https://img.example/ella.jpg');
    });
  });

  group('DestinationsProvider', () {
    test('load fetches the first page', () async {
      final p = _provider(fakeBackend(all));

      await p.load();

      expect(p.state, LoadState.loaded);
      expect(p.items, hasLength(10));
      expect(p.total, 25);
      expect(p.hasMore, isTrue);
      expect(p.items.first.name, 'Place 01');
    });

    test('loadMore appends pages until everything is loaded', () async {
      final p = _provider(fakeBackend(all));
      await p.load();

      await p.loadMore();
      await p.loadMore();
      expect(p.items, hasLength(25));
      expect(p.hasMore, isFalse);

      await p.loadMore(); // no-op at the end
      expect(p.items, hasLength(25));
      expect(p.items.map((d) => d.id).toSet(), hasLength(25));
    });

    test('changing the category reloads from page one', () async {
      final p = _provider(fakeBackend(all));
      await p.load();
      await p.loadMore();

      await p.setCategory('Beach');

      expect(p.category, 'Beach');
      expect(p.items.every((d) => d.category == 'Beach'), isTrue);
      expect(p.total, p.items.length);
      expect(p.hasMore, isFalse);
    });

    test('sorting by name descending reverses the order', () async {
      final p = _provider(fakeBackend(all));
      await p.load();

      await p.setSort(DestinationSort.nameDesc);

      expect(p.items.first.name, 'Place 25');
    });

    test('search is trimmed and an unchanged value does not refetch',
        () async {
      final log = <http.Request>[];
      final p = _provider(fakeBackend(all, log: log));
      await p.load();

      await p.setSearch('  place 07 ');
      expect(p.items.single.id, 'd7');
      final calls = log.length;

      await p.setSearch('place 07');
      expect(log.length, calls);
    });

    test('a slow older response cannot overwrite a newer one', () async {
      final slow = Completer<http.Response>();
      final client = MockClient((req) {
        if (req.url.queryParameters['search'] == 'old') return slow.future;
        return destHandler(all, req);
      });
      final p = _provider(client);

      final first = p.setSearch('old'); // stays pending
      await p.setSearch('place 03'); // newer request finishes first
      expect(p.items.single.id, 'd3');

      slow.complete(_json({
        'items': [_dest(99)],
        'totalCount': 1,
        'page': 1,
        'pageSize': 10,
      }, 200));
      await first;

      expect(p.items.single.id, 'd3');
    });

    test('load failure reports the message and clears the list', () async {
      final p = _provider(MockClient((_) async => _json({}, 500)));

      await p.load();

      expect(p.state, LoadState.failed);
      expect(p.error, 'Something went wrong on the server.');
      expect(p.items, isEmpty);
    });

    test('a loadMore failure keeps the items and can be retried', () async {
      var fail = false;
      final p = _provider(MockClient((req) async {
        if (fail && req.url.queryParameters['page'] == '2') {
          return _json({}, 500);
        }
        return destHandler(all, req);
      }));
      await p.load();

      fail = true;
      await p.loadMore();
      expect(p.items, hasLength(10));
      expect(p.moreError, isNotNull);
      expect(p.state, LoadState.loaded);

      fail = false;
      await p.loadMore();
      expect(p.items, hasLength(20));
      expect(p.moreError, isNull);
    });

    test('clear resets data and filters', () async {
      final p = _provider(fakeBackend(all));
      await p.setCategory('Beach');

      p.clear();

      expect(p.items, isEmpty);
      expect(p.category, isNull);
      expect(p.state, LoadState.idle);
    });
  });

  group('Explore UI', () {
    Future<void> pumpExplore(WidgetTester tester, MockClient client) async {
      final api = ApiClient(httpClient: client, baseUrl: 'http://test');
      await tester
          .pumpWidget(CeyloraApp(api: api, store: _MemoryStore(_session())));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore').last);
      await tester.pumpAndSettle();
    }

    testWidgets('lists destinations with category chips', (tester) async {
      await pumpExplore(tester, fakeBackend(all));

      expect(find.text('Place 01'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Beach'), findsOneWidget);
    });

    testWidgets('filtering by category narrows the list', (tester) async {
      await pumpExplore(tester, fakeBackend(all));

      await tester.tap(find.widgetWithText(ChoiceChip, 'Beach'));
      await tester.pumpAndSettle();

      final beach = all.where((d) => d['category'] == 'Beach').toList();
      expect(find.text(beach.first['name'] as String), findsOneWidget);
      expect(find.text('Place 01'), findsNothing); // Place 01 is not a beach
    });

    testWidgets('search waits for a typing pause, then filters',
        (tester) async {
      final log = <http.Request>[];
      await pumpExplore(tester, fakeBackend(all, log: log));
      final before = log.length;

      await tester.enterText(find.byType(TextField), 'place 07');
      await tester.pump(const Duration(milliseconds: 200));
      expect(log.length, before); // still debouncing

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(log.length, before + 1);
      expect(find.text('Place 07'), findsOneWidget);
      expect(find.text('Place 01'), findsNothing);
    });

    testWidgets('shows a no-match message', (tester) async {
      await pumpExplore(tester, fakeBackend(all));

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();

      expect(find.text('No destinations match your search.'), findsOneWidget);
    });

    testWidgets('shows an error with retry when loading fails',
        (tester) async {
      await pumpExplore(tester, MockClient((_) async => _json({}, 500)));

      expect(find.text('Something went wrong on the server.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('scrolling to the end loads the next page', (tester) async {
      final log = <http.Request>[];
      await pumpExplore(tester, fakeBackend(all, log: log));

      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byKey(const Key('destinations-list')), const Offset(0, -3000));
        await tester.pumpAndSettle();
      }

      final pages = log
          .where((r) => r.url.path == '/api/destinations')
          .map((r) => r.url.queryParameters['page'])
          .toList();
      expect(pages, containsAll(['1', '2']));
    });

    testWidgets('opens a destination with its experience prices',
        (tester) async {
      await pumpExplore(tester, fakeBackend(all));

      await tester.tap(find.text('Place 01'));
      await tester.pumpAndSettle();

      expect(find.text('About place 1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // experience count
      expect(find.text('LKR 5,000'), findsOneWidget);
      expect(find.text('LKR 25,000'), findsOneWidget);
      expect(find.text('LKR 12,500.50'), findsOneWidget);
    });
  });
}
