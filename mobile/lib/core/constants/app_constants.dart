import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static const String appName = 'LC Connect';

  static String get apiBaseUrl {
    final url = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8000/api/v1';
    // The Android emulator can't reach the host Mac via `localhost` (that points at
    // the emulator itself); 10.0.2.2 is its built-in alias for the host loopback.
    // iOS Simulator shares the host network, so it keeps localhost as-is.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return url
          .replaceFirst('localhost', '10.0.2.2')
          .replaceFirst('127.0.0.1', '10.0.2.2');
    }
    return url;
  }

  static String get env => dotenv.env['ENV'] ?? 'development';

  static bool get isDev => env == 'development';

  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  static const String tokenKey = 'lc_connect_access_token';
}
