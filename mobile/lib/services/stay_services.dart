import '../models/accommodation.dart';
import '../models/booking.dart';
import '../models/review.dart';
import '../utils/format.dart';
import 'api_client.dart';

/// A malformed body becomes a clean error instead of an uncaught TypeError.
T _parse<T>(T Function() parse) {
  try {
    return parse();
  } on TypeError {
    throw const ApiException('The server sent an unexpected response.');
  } on FormatException {
    throw const ApiException('The server sent an unexpected response.');
  }
}

/// Browse stays and price a stay (`/api/accommodations`).
class AccommodationService {
  final ApiClient _api;
  AccommodationService(this._api);

  Future<AccommodationPage> list({
    String? search,
    String? type,
    String sortBy = 'Name',
    bool descending = false,
    int page = 1,
    int pageSize = 10,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'type': ?type,
      'sortBy': sortBy,
      'sortDescending': descending.toString(),
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    final path = Uri(path: '/api/accommodations', queryParameters: query).toString();
    final data = await _api.get(path);
    return _parse(() => AccommodationPage.fromJson(data as Map<String, dynamic>));
  }

  Future<Accommodation> get(String id) async {
    final data = await _api.get('/api/accommodations/$id');
    return _parse(() => Accommodation.fromJson(data as Map<String, dynamic>));
  }

  /// Availability and price for a stay.
  Future<AvailabilityQuote> quote({
    required String id,
    required DateTime checkIn,
    required DateTime checkOut,
    required int rooms,
  }) async {
    final path = Uri(
      path: '/api/accommodations/$id/quote',
      queryParameters: {
        'checkIn': toApiDate(checkIn),
        'checkOut': toApiDate(checkOut),
        'rooms': rooms.toString(),
      },
    ).toString();
    final data = await _api.get(path);
    return _parse(() => AvailabilityQuote.fromJson(data as Map<String, dynamic>));
  }
}

/// Make, read and cancel bookings (`/api/bookings`).
class BookingService {
  final ApiClient _api;
  BookingService(this._api);

  /// Books one stay for a trip. The API reserves the rooms in the same step.
  Future<Booking> create({
    required String tripId,
    required String accommodationId,
    required DateTime checkIn,
    required DateTime checkOut,
    required int rooms,
    required int guests,
    String? notes,
  }) async {
    final data = await _api.post('/api/bookings', {
      'tripId': tripId,
      'items': [
        {
          'accommodationId': accommodationId,
          'checkIn': toApiDate(checkIn),
          'checkOut': toApiDate(checkOut),
          'rooms': rooms,
          'guests': guests,
        }
      ],
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
    return _parse(() => Booking.fromJson(data as Map<String, dynamic>));
  }

  Future<List<Booking>> mine() async {
    final data = await _api.get('/api/bookings/mine');
    return _parse(() => (data as List<dynamic>)
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList(growable: false));
  }

  Future<Booking> cancel(String id) async {
    final data = await _api.post('/api/bookings/$id/cancel', {});
    return _parse(() => Booking.fromJson(data as Map<String, dynamic>));
  }
}

/// Reviews of a stay (`/api/accommodations/{id}/reviews`).
class ReviewService {
  final ApiClient _api;
  ReviewService(this._api);

  Future<ReviewPage> list(String accommodationId,
      {int page = 1, int pageSize = 5}) async {
    final path = Uri(
      path: '/api/accommodations/$accommodationId/reviews',
      queryParameters: {'page': page.toString(), 'pageSize': pageSize.toString()},
    ).toString();
    final data = await _api.get(path);
    return _parse(() => ReviewPage.fromJson(data as Map<String, dynamic>));
  }

  Future<Review> create(String accommodationId,
      {required int rating, required String comment}) async {
    final data = await _api.post('/api/accommodations/$accommodationId/reviews', {
      'rating': rating,
      'comment': comment.trim(),
    });
    return _parse(() => Review.fromJson(data as Map<String, dynamic>));
  }
}
