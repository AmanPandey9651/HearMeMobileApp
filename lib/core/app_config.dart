import 'dart:io';
import 'package:flutter/foundation.dart';

enum AppEnvironment {
  local,
  staging,
  production;

  String get displayName {
    switch (this) {
      case AppEnvironment.local:
        return 'Local Development (localhost:8080)';
      case AppEnvironment.staging:
        return 'AWS Deployment (3.108.61.140)';
      case AppEnvironment.production:
        return 'Production (3.108.61.140)';
    }
  }

  String get defaultHost {
    switch (this) {
      case AppEnvironment.local:
        // On Android emulator, 10.0.2.2 reaches the host machine's localhost.
        if (!kIsWeb && Platform.isAndroid) {
          return 'http://10.0.2.2:8080';
        }
        return 'http://localhost:8080';
      case AppEnvironment.staging:
        return 'http://3.108.61.140';
      case AppEnvironment.production:
        return 'http://3.108.61.140';
    }
  }

  String get apiBaseUrl => AppConfig.normalizeApiUrl(defaultHost);

  static AppEnvironment fromString(String? value) {
    if (value == null) return AppEnvironment.production;
    final clean = value.trim().toLowerCase();
    if (clean == 'local' || clean.contains('localhost') || clean.contains('10.0.2.2')) {
      return AppEnvironment.local;
    }
    if (clean == 'staging' || clean == 'netlify' || clean.contains('onrender')) {
      return AppEnvironment.staging;
    }
    return AppEnvironment.production;
  }
}

class AppConfig {
  // Compile-time environment configuration
  // Defaults to production (https://www.feelback.in)
  // Pass: --dart-define=APP_ENV=staging OR --dart-define=APP_ENV=local
  static const String _compileTimeEnv = String.fromEnvironment('APP_ENV', defaultValue: 'staging');
  static const String _compileTimeApiUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '792080217058-430nba8au4hs4kn0lb6l94o2aoqmjb5r.apps.googleusercontent.com',
  );

  static const Duration networkTimeout = Duration(seconds: 25);

  /// Strips trailing slashes, /health, /api/v1, /api to get the root origin.
  static String normalizeHostUrl(String raw) {
    var trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    trimmed = trimmed.replaceAll(RegExp(r'/health/?$'), '');
    trimmed = trimmed.replaceAll(RegExp(r'/api/v1/?$'), '');
    trimmed = trimmed.replaceAll(RegExp(r'/api/?$'), '');
    return trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  /// Ensures the URL ends with /api/v1 for REST API client calls.
  static String normalizeApiUrl(String raw) {
    final host = normalizeHostUrl(raw);
    if (host.isEmpty) return '';
    return '$host/api/v1';
  }

  /// Active environment resolved from compile-time settings (defaults to Production www.feelback.in)
  static AppEnvironment get currentEnvironment => AppEnvironment.fromString(_compileTimeEnv);

  /// Active API base URL for all ApiClient requests (e.g. https://www.feelback.in/api/v1)
  static String get apiBaseUrl {
    // 1. Explicit compile-time API_BASE_URL override has top precedence
    if (_compileTimeApiUrl.isNotEmpty) {
      return normalizeApiUrl(_compileTimeApiUrl);
    }
    // 2. Active environment API base URL
    return currentEnvironment.apiBaseUrl;
  }

  /// Active root origin (e.g. https://www.feelback.in)
  static String get currentHost => normalizeHostUrl(apiBaseUrl);

  /// Active health check URL (e.g. https://www.feelback.in/health)
  static String get healthUrl => '$currentHost/health';

  /// Optional initialization hook
  static Future<void> initialize() async {}
}
