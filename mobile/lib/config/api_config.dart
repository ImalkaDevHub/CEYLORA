import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Base URL of the CEYLORA.Api backend.
///
/// Override at build/run time:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5091
///
/// Defaults target a local `dotnet run` (http profile, port 5091):
///   - Android emulator reaches the host machine at 10.0.2.2
///   - Everything else (desktop/web/iOS simulator) uses localhost
class ApiConfig {
  static const String _override = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_override.isNotEmpty) return _override;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:5091';
    return 'http://localhost:5091';
  }
}
