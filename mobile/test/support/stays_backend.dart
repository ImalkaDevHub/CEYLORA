import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

String apiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, dynamic> stayJson(
  int n, {
  String? name,
  String type = 'Hotel',
  num price = 20000,
  double? rating,
  int reviews = 0,
  String destination = 'Galle Fort',
  int maxGuests = 2,
  bool active = true,
  String description = 'A lovely place to stay',
}) =>
    {
      'id': 's$n',
      'destinationId': 'd1',
      'destinationName': destination,
      'name': name ?? 'Stay ${n.toString().padLeft(2, '0')}',
      'description': description,
      'type': type,
      'pricePerNight': price,
      'maxGuestsPerRoom': maxGuests,
      'isActive': active,
      'averageRating': rating,
      'reviewCount': reviews,
    };

Map<String, dynamic> reviewJson(int n,
        {String stayId = 's1', int rating = 4, String comment = 'Nice'}) =>
    {
      'id': 'r$n',
      'accommodationId': stayId,
      'travelerId': 'u$n',
      'travelerName': 'Traveler $n',
      'rating': rating,
      'comment': comment,
      // Always a valid day of October: n is small for seeded reviews, 100+ for new ones.
      'createdAt': '2026-10-${(10 + n % 20).toString().padLeft(2, '0')}T08:00:00Z',
    };

Map<String, dynamic> tripJson(String id, String title, {String status = 'Draft'}) => {
      'id': id,
      'title': title,
      'startDate': '2026-11-01T00:00:00Z',
      'endDate': '2026-11-05T00:00:00Z',
      'budget': 200000,
      'status': status,
      'travelerName': 'Sam Traveler',
    };

Map<String, dynamic> bookingJson(
  String id, {
  String tripId = 't1',
  String tripTitle = 'South coast',
  String status = 'Confirmed',
  required DateTime checkIn,
  required DateTime checkOut,
  String stayId = 's1',
  String stayName = 'Stay 01',
  int rooms = 1,
  int guests = 2,
  num rate = 20000,
  String created = '2026-10-20T10:00:00Z',
  String? notes,
}) {
  final nights = checkOut.difference(checkIn).inDays;
  return {
    'id': id,
    'tripId': tripId,
    'tripTitle': tripTitle,
    'travelerId': 'u1',
    'travelerName': 'Sam Traveler',
    'status': status,
    'totalAmount': rate * nights * rooms,
    'notes': notes,
    'createdAt': created,
    'cancelledAt': status == 'Cancelled' ? '2026-10-21T10:00:00Z' : null,
    'items': <Map<String, dynamic>>[
      {
        'id': 'i-$id',
        'accommodationId': stayId,
        'accommodationName': stayName,
        'destinationName': 'Galle Fort',
        'checkIn': apiDate(checkIn),
        'checkOut': apiDate(checkOut),
        'nights': nights,
        'rooms': rooms,
        'guests': guests,
        'nightlyRate': rate,
        'subtotal': rate * nights * rooms,
      }
    ],
  };
}

/// In-memory stand-in for the stays, bookings, reviews and trips endpoints.
/// Tweak the public fields to steer a test.
class StaysBackend {
  List<Map<String, dynamic>> stays;
  List<Map<String, dynamic>> bookings = [];
  List<Map<String, dynamic>> trips;
  final Map<String, List<Map<String, dynamic>>> reviews = {};
  final List<http.Request> log = [];

  /// How many rooms of any stay are free for a quote.
  int freeRooms = 3;

  /// Make the next booking fail with this response (e.g. 409 sold out).
  http.Response? bookingFailure;

  /// Make cancelling fail with this message (400).
  String? cancelFailure;

  /// Make posting a review fail with (status, message).
  (int, String)? reviewFailure;

  /// Fail the stays list with this status.
  int? listFailure;

  /// Fail "my bookings" with this status.
  int? bookingsFailure;

  StaysBackend({List<Map<String, dynamic>>? stays, List<Map<String, dynamic>>? trips})
      : stays = stays ?? [for (var i = 1; i <= 3; i++) stayJson(i)],
        trips = trips ?? [tripJson('t1', 'South coast')];

  MockClient get client => MockClient((req) async => handle(req));

  List<http.Request> requests(String method, String path) =>
      log.where((r) => r.method == method && r.url.path == path).toList();

  Future<http.Response> handle(http.Request req) async {
    log.add(req);
    final path = req.url.path;
    final q = req.url.queryParameters;

    if (req.method == 'GET' && path == '/api/trips/mine') return json(trips, 200);

    if (req.method == 'GET' && path == '/api/accommodations') {
      if (listFailure != null) return json({}, listFailure!);
      var rows = [...stays.where((s) => s['isActive'] == true)];
      final search = q['search']?.toLowerCase();
      if (search != null) {
        rows = rows
            .where((s) =>
                (s['name'] as String).toLowerCase().contains(search) ||
                (s['destinationName'] as String).toLowerCase().contains(search))
            .toList();
      }
      if (q['type'] != null) rows = rows.where((s) => s['type'] == q['type']).toList();
      int Function(Map<String, dynamic>, Map<String, dynamic>) cmp;
      switch (q['sortBy']) {
        case 'Price':
          cmp = (a, b) => (a['pricePerNight'] as num).compareTo(b['pricePerNight'] as num);
        case 'Rating':
          cmp = (a, b) =>
              ((a['averageRating'] ?? 0) as num).compareTo((b['averageRating'] ?? 0) as num);
        default:
          cmp = (a, b) => (a['name'] as String).compareTo(b['name'] as String);
      }
      rows.sort(cmp);
      if (q['sortDescending'] == 'true') rows = rows.reversed.toList();
      final page = int.parse(q['page']!);
      final size = int.parse(q['pageSize']!);
      return json({
        'items': rows.skip((page - 1) * size).take(size).toList(),
        'totalCount': rows.length,
        'page': page,
        'pageSize': size,
      }, 200);
    }

    final stayMatch = RegExp(r'^/api/accommodations/([^/]+)(/quote|/reviews)?$').firstMatch(path);
    if (stayMatch != null) {
      final id = stayMatch.group(1)!;
      final tail = stayMatch.group(2);
      final stay = stays.where((s) => s['id'] == id).toList();
      if (stay.isEmpty) return json({'message': 'Accommodation not found.'}, 404);

      if (tail == null && req.method == 'GET') return json(stay.first, 200);

      if (tail == '/quote' && req.method == 'GET') {
        final checkIn = DateTime.parse(q['checkIn']!);
        final checkOut = DateTime.parse(q['checkOut']!);
        final rooms = int.parse(q['rooms']!);
        final nights = checkOut.difference(checkIn).inDays;
        if (nights < 1) return json({'message': 'Check-out must be after check-in.'}, 400);
        if (nights > 30) return json({'message': 'A stay can be at most 30 nights.'}, 400);
        final price = stay.first['pricePerNight'] as num;
        return json({
          'accommodationId': id,
          'accommodationName': stay.first['name'],
          'checkIn': q['checkIn'],
          'checkOut': q['checkOut'],
          'nights': nights,
          'rooms': rooms,
          'pricePerNight': price,
          'totalPrice': price * nights * rooms,
          'isAvailable': rooms <= freeRooms,
          'maxRoomsAvailable': freeRooms,
          'days': [
            for (var i = 0; i < nights; i++)
              {
                'date': apiDate(checkIn.add(Duration(days: i))),
                'totalRooms': freeRooms,
                'bookedRooms': 0,
                'availableRooms': freeRooms,
              }
          ],
        }, 200);
      }

      if (tail == '/reviews' && req.method == 'GET') {
        final all = reviews[id] ?? const [];
        final page = int.parse(q['page'] ?? '1');
        final size = int.parse(q['pageSize'] ?? '10');
        return json({
          'items': all.skip((page - 1) * size).take(size).toList(),
          'totalCount': all.length,
          'page': page,
          'pageSize': size,
        }, 200);
      }

      if (tail == '/reviews' && req.method == 'POST') {
        if (reviewFailure != null) {
          return json({'message': reviewFailure!.$2}, reviewFailure!.$1);
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final list = reviews.putIfAbsent(id, () => []);
        final created = reviewJson(list.length + 100,
            stayId: id, rating: body['rating'] as int, comment: body['comment'] as String);
        list.insert(0, created);
        return json(created, 201);
      }
    }

    if (path == '/api/bookings/mine' && req.method == 'GET') {
      if (bookingsFailure != null) return json({}, bookingsFailure!);
      return json(bookings, 200);
    }

    if (path == '/api/bookings' && req.method == 'POST') {
      if (bookingFailure != null) return bookingFailure!;
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final item = (body['items'] as List).first as Map<String, dynamic>;
      final stay = stays.firstWhere((s) => s['id'] == item['accommodationId']);
      final trip = trips.firstWhere((t) => t['id'] == body['tripId']);
      final created = bookingJson('b${bookings.length + 1}',
          tripId: trip['id'] as String,
          tripTitle: trip['title'] as String,
          stayId: stay['id'] as String,
          stayName: stay['name'] as String,
          checkIn: DateTime.parse(item['checkIn'] as String),
          checkOut: DateTime.parse(item['checkOut'] as String),
          rooms: item['rooms'] as int,
          guests: item['guests'] as int,
          rate: stay['pricePerNight'] as num,
          created: '2026-10-2${bookings.length + 1}T10:00:00Z',
          notes: body['notes'] as String?);
      bookings.add(created);
      return json(created, 201);
    }

    final cancelMatch = RegExp(r'^/api/bookings/([^/]+)/cancel$').firstMatch(path);
    if (cancelMatch != null && req.method == 'POST') {
      if (cancelFailure != null) return json({'message': cancelFailure}, 400);
      final id = cancelMatch.group(1)!;
      final index = bookings.indexWhere((b) => b['id'] == id);
      if (index == -1) return json({'message': 'Booking not found.'}, 404);
      bookings[index] = {
        ...bookings[index],
        'status': 'Cancelled',
        'cancelledAt': '2026-10-21T10:00:00Z',
      };
      return json(bookings[index], 200);
    }

    return json({'message': 'not found'}, 404);
  }
}
