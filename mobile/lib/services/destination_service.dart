import '../models/destination.dart';
import 'api_client.dart';

class DestinationService {
  final ApiClient _api;
  DestinationService(this._api);

  Future<DestinationPage> list({
    String? search,
    String? category,
    String sortBy = 'Name',
    bool descending = false,
    int page = 1,
    int pageSize = 10,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'category': ?category,
      'sortBy': sortBy,
      'sortDescending': descending.toString(),
      'page': page.toString(),
      'pageSize': pageSize.toString(),
    };
    final path = Uri(path: '/api/destinations', queryParameters: query).toString();
    final data = await _api.get(path);
    return _parse(() => DestinationPage.fromJson(data as Map<String, dynamic>));
  }

  Future<DestinationSummary> summary(String id) async {
    final data = await _api.get('/api/destinations/$id/summary');
    return _parse(
        () => DestinationSummary.fromJson(data as Map<String, dynamic>));
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
