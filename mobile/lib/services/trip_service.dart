import '../models/trip.dart';
import '../utils/format.dart';
import 'api_client.dart';

class TripService {
  final ApiClient _api;
  TripService(this._api);

  Future<List<Trip>> myTrips() async {
    final data = await _api.get('/api/trips/mine');
    return _parse(() => (data as List<dynamic>)
        .map((e) => Trip.fromJson(e as Map<String, dynamic>))
        .toList(growable: false));
  }

  Future<Trip> create({
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required double budget,
  }) async {
    final data = await _api.post('/api/trips', {
      'title': title,
      'startDate': toApiDate(startDate),
      'endDate': toApiDate(endDate),
      'budget': budget,
    });
    return _parse(() => Trip.fromJson(data as Map<String, dynamic>));
  }

  Future<Trip> submit(String tripId) async {
    final data = await _api.post('/api/trips/$tripId/submit', {});
    return _parse(() => Trip.fromJson(data as Map<String, dynamic>));
  }

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
}
