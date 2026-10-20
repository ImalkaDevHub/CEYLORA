import '../models/ai_workflow.dart';
import 'api_client.dart';

class AiWorkflowService {
  final ApiClient _api;

  /// The API waits up to 30s for the AI service, so allow it a little more.
  final Duration startTimeout;

  static const defaultStartTimeout = Duration(seconds: 60);
  static const unavailableMessage =
      'The AI planner is unavailable right now. Please try again in a moment.';

  AiWorkflowService(this._api, {this.startTimeout = defaultStartTimeout});

  Future<List<AiWorkflow>> mine() async {
    final data = await _api.get('/api/ai/workflows/mine');
    return _parse(() => (data as List<dynamic>)
        .map((e) => AiWorkflow.fromJson(e as Map<String, dynamic>))
        .toList(growable: false));
  }

  Future<AiWorkflow> get(String id) async {
    final data = await _api.get('/api/ai/workflows/$id');
    return _parse(() => AiWorkflow.fromJson(data as Map<String, dynamic>));
  }

  /// Runs the planner. The API answers only once the plan is finished.
  Future<AiWorkflow> start({
    required String goal,
    required int days,
    required double budget,
    required List<String> interests,
  }) async {
    final dynamic data;
    try {
      data = await _api.post(
        '/api/ai/workflows',
        {
          'goal': goal,
          'days': days,
          'budget': budget,
          'interests': interests,
        },
        timeout: startTimeout,
      );
    } on ApiException catch (e) {
      final status = e.statusCode;
      // The raw 5xx text is meaningless to a traveler; an AI-service failure
      // surfaces as a 500.
      if (status != null && status >= 500) {
        throw ApiException(unavailableMessage, statusCode: status);
      }
      rethrow;
    }
    return _parse(() => AiWorkflow.fromJson(data as Map<String, dynamic>));
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
