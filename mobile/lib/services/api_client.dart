import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

/// Error with a message that is safe to show to the user.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  const ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Thin JSON client for CEYLORA.Api. Attaches the bearer token when one is set
/// and reports 401s through [onUnauthorized] so the app can clear the session.
class ApiClient {
  final http.Client _http;
  final String baseUrl;
  String? _token;

  /// Called when an authenticated request comes back 401 (expired/invalid token).
  void Function()? onUnauthorized;

  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        baseUrl = baseUrl ?? ApiConfig.baseUrl;

  void setToken(String? token) => _token = token;

  Future<dynamic> post(String path, Map<String, dynamic> body) =>
      _send('POST', path, body: body);

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> _send(String method, String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    };

    late final http.Response response;
    try {
      final request = method == 'POST'
          ? _http.post(uri, headers: headers, body: jsonEncode(body))
          : _http.get(uri, headers: headers);
      response = await request.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.');
    } on SocketException {
      throw const ApiException(
          'Cannot reach the server. Check your connection and the API address.');
    } on http.ClientException {
      throw const ApiException(
          'Cannot reach the server. Check your connection and the API address.');
    }

    final decoded = response.body.isEmpty ? null : _tryDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401 && _token != null) {
      onUnauthorized?.call();
    }
    throw ApiException(_messageFor(response.statusCode, decoded),
        statusCode: response.statusCode);
  }

  dynamic _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// The API answers errors as `{ "message": "..." }` (auth) or ASP.NET
  /// validation problem details (`errors` map / `title`).
  String _messageFor(int status, dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final message = decoded['message'];
      if (message is String && message.isNotEmpty) return message;

      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      final title = decoded['title'];
      if (title is String && title.isNotEmpty) return title;
    }
    if (status >= 500) return 'Something went wrong on the server.';
    return 'Request failed ($status).';
  }

  void close() => _http.close();
}
