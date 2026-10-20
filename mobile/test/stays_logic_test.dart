import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/models/accommodation.dart';
import 'package:mobile/models/booking.dart';
import 'package:mobile/providers/accommodations_provider.dart';
import 'package:mobile/providers/bookings_provider.dart';
import 'package:mobile/providers/reviews_provider.dart';
import 'package:mobile/providers/trips_provider.dart' show LoadState;
import 'package:mobile/services/api_client.dart';
import 'package:mobile/services/stay_services.dart';

import 'support/stays_backend.dart';

ApiClient _api(MockClient client) {
  final api = ApiClient(httpClient: client, baseUrl: 'http://test');
  api.setToken('jwt-token');
  return api;
}

final _in = DateTime(2026, 11, 1);
final _out = DateTime(2026, 11, 3);

void main() {
  group('parseDateOnly', () {
    test('reads a calendar date without any time-zone shift', () {
      final d = parseDateOnly('2026-11-01');
      expect([d.year, d.month, d.day], [2026, 11, 1]);
      expect(d.isUtc, isFalse);
    });

    test('rejects anything else', () {
      expect(() => parseDateOnly('2026-11'), throwsFormatException);
      expect(() => parseDateOnly('nov 1'), throwsFormatException);
    });
  });

  group('Booking model', () {
    test('knows when a stay has ended (check-out day counts)', () {
      final item = BookingItem.fromJson(
          (bookingJson('b1', checkIn: _in, checkOut: _out)['items'] as List).first
              as Map<String, dynamic>);

      expect(item.hasEnded(DateTime(2026, 11, 2, 23)), isFalse);
      expect(item.hasEnded(DateTime(2026, 11, 3, 0, 5)), isTrue);
      expect(item.hasEnded(DateTime(2026, 12, 1)), isTrue);
    });

    test('first check-in and last check-out span all stays', () {
      final json = bookingJson('b1', checkIn: _in, checkOut: _out);
      (json['items'] as List).add({
        ...(json['items'] as List).first as Map<String, dynamic>,
        'id': 'i2',
        'checkIn': '2026-11-05',
        'checkOut': '2026-11-09',
      });

      final booking = Booking.fromJson(json);

      expect(booking.firstCheckIn, DateTime(2026, 11, 1));
      expect(booking.lastCheckOut, DateTime(2026, 11, 9));
    });
  });

  group('services', () {
    test('AccommodationService.list sends the filters as query parameters', () async {
      final backend = StaysBackend();
      await AccommodationService(_api(backend.client)).list(
        search: '  fort ',
        type: 'Villa',
        sortBy: 'Price',
        descending: true,
        page: 2,
        pageSize: 5,
      );

      final r = backend.requests('GET', '/api/accommodations').single;
      expect(r.headers['Authorization'], 'Bearer jwt-token');
      expect(r.url.queryParameters, {
        'search': 'fort',
        'type': 'Villa',
        'sortBy': 'Price',
        'sortDescending': 'true',
        'page': '2',
        'pageSize': '5',
      });
    });

    test('list leaves out a blank search and no type', () async {
      final backend = StaysBackend();
      await AccommodationService(_api(backend.client)).list(search: '  ');

      final q = backend.requests('GET', '/api/accommodations').single.url.queryParameters;
      expect(q.containsKey('search'), isFalse);
      expect(q.containsKey('type'), isFalse);
    });

    test('quote sends date-only strings and the room count', () async {
      final backend = StaysBackend();
      final quote = await AccommodationService(_api(backend.client))
          .quote(id: 's1', checkIn: _in, checkOut: _out, rooms: 2);

      final q = backend.requests('GET', '/api/accommodations/s1/quote').single.url.queryParameters;
      expect(q, {'checkIn': '2026-11-01', 'checkOut': '2026-11-03', 'rooms': '2'});
      expect(quote.nights, 2);
      expect(quote.totalPrice, 80000);
      expect(quote.isAvailable, isTrue);
      expect(quote.days, hasLength(2));
      expect(quote.checkIn, DateTime(2026, 11, 1));
    });

    test('a malformed body becomes a clean error', () async {
      final service = AccommodationService(_api(MockClient((_) async => json({'x': 1}, 200))));

      await expectLater(
          service.list(),
          throwsA(isA<ApiException>()
              .having((e) => e.message, 'message', contains('unexpected response'))));
      await expectLater(
          service.quote(id: 's1', checkIn: _in, checkOut: _out, rooms: 1),
          throwsA(isA<ApiException>()));
    });

    test('BookingService.create sends one item, date-only, trimmed notes', () async {
      final backend = StaysBackend();
      await BookingService(_api(backend.client)).create(
        tripId: 't1',
        accommodationId: 's1',
        checkIn: _in,
        checkOut: _out,
        rooms: 2,
        guests: 3,
        notes: '  late arrival ',
      );

      final body = jsonDecode(backend.requests('POST', '/api/bookings').single.body);
      expect(body, {
        'tripId': 't1',
        'items': [
          {
            'accommodationId': 's1',
            'checkIn': '2026-11-01',
            'checkOut': '2026-11-03',
            'rooms': 2,
            'guests': 3,
          }
        ],
        'notes': 'late arrival',
      });
    });

    test('create omits blank notes', () async {
      final backend = StaysBackend();
      await BookingService(_api(backend.client)).create(
          tripId: 't1', accommodationId: 's1', checkIn: _in, checkOut: _out,
          rooms: 1, guests: 1, notes: '   ');

      final body = jsonDecode(backend.requests('POST', '/api/bookings').single.body) as Map;
      expect(body.containsKey('notes'), isFalse);
    });

    test('ReviewService posts the rating and a trimmed comment', () async {
      final backend = StaysBackend();
      await ReviewService(_api(backend.client))
          .create('s1', rating: 5, comment: '  Great  ');

      final r = backend.requests('POST', '/api/accommodations/s1/reviews').single;
      expect(jsonDecode(r.body), {'rating': 5, 'comment': 'Great'});
    });
  });

  group('AccommodationsProvider', () {
    AccommodationsProvider build(StaysBackend b) =>
        AccommodationsProvider(AccommodationService(_api(b.client)));

    StaysBackend many() => StaysBackend(stays: [
          stayJson(1, name: 'Alpha Hotel', price: 30000, rating: 4.5, reviews: 4),
          stayJson(2, name: 'Beta Villa', type: 'Villa', price: 10000, rating: 3.0, reviews: 2),
          stayJson(3, name: 'Gamma Hostel', type: 'Hostel', price: 5000, destination: 'Ella'),
          for (var i = 4; i <= 25; i++) stayJson(i, name: 'Stay $i'),
        ]);

    test('load fetches the first page and caches the stays', () async {
      final p = build(many());
      await p.load();

      expect(p.state, LoadState.loaded);
      expect(p.items, hasLength(AccommodationsProvider.pageSize));
      expect(p.total, 25);
      expect(p.byId('s1')!.name, 'Alpha Hotel');
      expect(p.hasMore, isTrue);
    });

    test('loadMore appends until everything is loaded', () async {
      final p = build(many());
      await p.load();
      await p.loadMore();
      await p.loadMore();
      expect(p.items, hasLength(25));
      expect(p.hasMore, isFalse);

      await p.loadMore(); // no-op
      expect(p.items.map((a) => a.id).toSet(), hasLength(25));
    });

    test('changing the type reloads from page one', () async {
      final p = build(many());
      await p.load();
      await p.loadMore();

      await p.setType('Villa');

      expect(p.items.map((a) => a.name), ['Beta Villa']);
      expect(p.total, 1);
    });

    test('search is trimmed and an unchanged value does not refetch', () async {
      final b = many();
      final p = build(b);
      await p.load();

      await p.setSearch('  ella ');
      expect(p.items.map((a) => a.name), ['Gamma Hostel']);
      final calls = b.requests('GET', '/api/accommodations').length;

      await p.setSearch('ella');
      expect(b.requests('GET', '/api/accommodations').length, calls);
    });

    test('sorting by price and by rating', () async {
      final p = build(many());
      await p.load();

      await p.setSort(StaySort.priceAsc);
      expect(p.items.first.name, 'Gamma Hostel');

      await p.setSort(StaySort.priceDesc);
      expect(p.items.first.name, 'Alpha Hotel');

      await p.setSort(StaySort.topRated);
      expect(p.items.first.name, 'Alpha Hotel');
    });

    test('a slow older response cannot overwrite a newer one', () async {
      final backend = many();
      final slow = Completer<http.Response>();
      final client = MockClient((req) {
        if (req.url.queryParameters['search'] == 'old') return slow.future;
        return backend.handle(req);
      });
      final p = AccommodationsProvider(AccommodationService(_api(client)));

      final first = p.setSearch('old');
      await p.setSearch('alpha');
      expect(p.items.single.name, 'Alpha Hotel');

      slow.complete(json({'items': [stayJson(99)], 'totalCount': 1, 'page': 1, 'pageSize': 10}, 200));
      await first;

      expect(p.items.single.name, 'Alpha Hotel');
    });

    test('a failure reports the message and clears the list', () async {
      final b = many()..listFailure = 500;
      final p = build(b);

      await p.load();

      expect(p.state, LoadState.failed);
      expect(p.error, 'Something went wrong on the server.');
      expect(p.items, isEmpty);
    });

    test('fetch updates the cache and the listed item (e.g. a new rating)', () async {
      final b = many();
      final p = build(b);
      await p.load();

      b.stays[0] = stayJson(1, name: 'Alpha Hotel', price: 30000, rating: 5.0, reviews: 9);
      final error = await p.fetch('s1');

      expect(error, isNull);
      expect(p.byId('s1')!.reviewCount, 9);
      expect(p.items.first.averageRating, 5.0);
    });

    test('fetch of an unknown stay returns the message', () async {
      final p = build(many());
      expect(await p.fetch('nope'), 'Accommodation not found.');
    });

    test('clear forgets stays and filters', () async {
      final p = build(many());
      await p.setType('Hotel');

      p.clear();

      expect(p.items, isEmpty);
      expect(p.byId('s1'), isNull);
      expect(p.type, isNull);
      expect(p.state, LoadState.idle);
    });
  });

  group('BookingsProvider', () {
    BookingsProvider build(StaysBackend b) => BookingsProvider(BookingService(_api(b.client)));

    Future<(Booking?, String?)> book(BookingsProvider p, {String trip = 't1'}) => p.create(
        tripId: trip, accommodationId: 's1', checkIn: _in, checkOut: _out, rooms: 1, guests: 2);

    test('create prepends the new booking', () async {
      final p = build(StaysBackend());

      final (booking, error) = await book(p);

      expect(error, isNull);
      expect(booking!.isConfirmed, isTrue);
      expect(p.items.first.id, booking.id);
      expect(p.creating, isFalse);
    });

    test('create reports the server message when the rooms are gone', () async {
      final b = StaysBackend()
        ..bookingFailure = json({'message': 'Stay 01 does not have 1 room(s) free on 2026-11-02.'}, 409);
      final p = build(b);

      final (booking, error) = await book(p);

      expect(booking, isNull);
      expect(error, contains('2026-11-02'));
      expect(p.items, isEmpty);
      expect(p.creating, isFalse);
    });

    test('a second create while one is running is ignored', () async {
      final gate = Completer<http.Response>();
      final b = StaysBackend();
      final p = BookingsProvider(BookingService(_api(MockClient((req) {
        if (req.method == 'POST') return gate.future;
        return b.handle(req);
      }))));

      final first = book(p);
      expect(p.creating, isTrue);
      final second = await book(p);
      expect(second, (null, null));
      expect(b.requests('POST', '/api/bookings'), isEmpty);

      gate.complete(json(bookingJson('b1', checkIn: _in, checkOut: _out), 201));
      final (booking, _) = await first;
      expect(booking!.id, 'b1');
      expect(p.items, hasLength(1));
    });

    test('load sorts newest first and forTrip filters', () async {
      final b = StaysBackend()
        ..bookings = [
          bookingJson('old', checkIn: _in, checkOut: _out, created: '2026-10-01T00:00:00Z'),
          bookingJson('new', checkIn: _in, checkOut: _out, tripId: 't2', created: '2026-10-05T00:00:00Z'),
        ];
      final p = build(b);

      await p.load();

      expect(p.items.map((x) => x.id), ['new', 'old']);
      expect(p.forTrip('t2').map((x) => x.id), ['new']);
      expect(p.forTrip('zzz'), isEmpty);
    });

    test('cancel replaces the booking with its cancelled version', () async {
      final b = StaysBackend();
      final p = build(b);
      final (booking, _) = await book(p);

      final error = await p.cancel(booking!.id);

      expect(error, isNull);
      expect(p.byId(booking.id)!.isCancelled, isTrue);
      expect(p.isCancelling(booking.id), isFalse);
    });

    test('a refused cancel keeps the booking and returns the message', () async {
      final b = StaysBackend();
      final p = build(b);
      final (booking, _) = await book(p);
      b.cancelFailure = 'This booking can no longer be cancelled because the first stay has started.';

      final error = await p.cancel(booking!.id);

      expect(error, contains('first stay has started'));
      expect(p.byId(booking.id)!.isConfirmed, isTrue);
    });

    test('load failure is reported', () async {
      final p = BookingsProvider(BookingService(_api(MockClient((_) async => json({}, 500)))));

      await p.load();

      expect(p.state, LoadState.failed);
      expect(p.error, isNotNull);
    });

    test('clear drops bookings, and a request finishing afterwards is ignored', () async {
      final gate = Completer<http.Response>();
      final p = BookingsProvider(BookingService(_api(MockClient((_) => gate.future))));

      final pending = book(p);
      p.clear(); // sign-out mid-request
      gate.complete(json(bookingJson('b1', checkIn: _in, checkOut: _out), 201));
      await pending;

      expect(p.items, isEmpty);
      expect(p.creating, isFalse);
    });
  });

  group('ReviewsProvider', () {
    StaysBackend withReviews(int count) {
      final b = StaysBackend();
      b.reviews['s1'] = [for (var i = 1; i <= count; i++) reviewJson(i)];
      return b;
    }

    ReviewsProvider build(StaysBackend b) => ReviewsProvider(ReviewService(_api(b.client)));

    test('load reads the first page and the total', () async {
      final p = build(withReviews(12));

      await p.load('s1');

      final r = p.reviewsFor('s1');
      expect(r.state, LoadState.loaded);
      expect(r.items, hasLength(ReviewsProvider.pageSize));
      expect(r.total, 12);
      expect(r.hasMore, isTrue);
    });

    test('loadMore appends the next pages until done', () async {
      final p = build(withReviews(12));
      await p.load('s1');

      await p.loadMore('s1');
      await p.loadMore('s1');

      expect(p.reviewsFor('s1').items, hasLength(12));
      expect(p.reviewsFor('s1').hasMore, isFalse);
      await p.loadMore('s1'); // no-op
      expect(p.reviewsFor('s1').items.map((r) => r.id).toSet(), hasLength(12));
    });

    test('a stay with no reviews is an empty loaded list', () async {
      final p = build(StaysBackend());
      await p.load('s1');

      expect(p.reviewsFor('s1').state, LoadState.loaded);
      expect(p.reviewsFor('s1').items, isEmpty);
    });

    test('add posts the review and shows it first', () async {
      final b = withReviews(2);
      final p = build(b);
      await p.load('s1');

      final error = await p.add('s1', rating: 5, comment: 'Superb');

      expect(error, isNull);
      expect(p.reviewsFor('s1').total, 3);
      expect(p.reviewsFor('s1').items.first.comment, 'Superb');
      expect(p.isSubmitting('s1'), isFalse);
    });

    test('add returns the API message when the stay is not finished yet', () async {
      final b = withReviews(0)
        ..reviewFailure = (403, 'You can review a place only after your stay there has ended.');
      final p = build(b);

      final error = await p.add('s1', rating: 4, comment: 'x');

      expect(error, 'You can review a place only after your stay there has ended.');
      expect(p.reviewsFor('s1').items, isEmpty);
      expect(p.isSubmitting('s1'), isFalse);
    });

    test('a duplicate review is explained', () async {
      final b = withReviews(0)..reviewFailure = (409, 'You have already reviewed this accommodation.');
      final p = build(b);

      expect(await p.add('s1', rating: 4, comment: 'x'), contains('already reviewed'));
    });

    test('a failing page keeps what is shown and offers a retry', () async {
      final b = withReviews(12);
      var failPage2 = false;
      final p = ReviewsProvider(ReviewService(_api(MockClient((req) {
        if (failPage2 && req.url.queryParameters['page'] == '2') {
          return Future.value(json({}, 500));
        }
        return b.handle(req);
      }))));
      await p.load('s1');

      failPage2 = true;
      await p.loadMore('s1');
      expect(p.reviewsFor('s1').items, hasLength(5));
      expect(p.reviewsFor('s1').moreError, isNotNull);

      failPage2 = false;
      await p.loadMore('s1');
      expect(p.reviewsFor('s1').items, hasLength(10));
      expect(p.reviewsFor('s1').moreError, isNull);
    });

    test('clear forgets every stay', () async {
      final p = build(withReviews(3));
      await p.load('s1');

      p.clear();

      expect(p.reviewsFor('s1').items, isEmpty);
      expect(p.reviewsFor('s1').state, LoadState.idle);
    });
  });
}
