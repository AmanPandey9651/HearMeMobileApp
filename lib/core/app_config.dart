import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

enum AppEnvironment {
  local,
  netlify,
  production,
  custom;

  String get key => name;

  String get displayName {
    switch (this) {
      case AppEnvironment.local:
        return 'Local Development';
      case AppEnvironment.netlify:
        return 'Netlify / Staging';
      case AppEnvironment.production:
        return 'Production';
      case AppEnvironment.custom:
        return 'Custom Server';
    }
  }

  String get defaultHost {
    switch (this) {
      case AppEnvironment.local:
        // On Android emulator, 10.0.2.2 connects to host machine's localhost.
        if (!kIsWeb && Platform.isAndroid) {
          return 'http://10.0.2.2:8080';
        }
        return 'http://localhost:8080';
      case AppEnvironment.netlify:
        return 'https://hearmebackendd.onrender.com';
      case AppEnvironment.production:
        return 'https://www.feelback.in';
      case AppEnvironment.custom:
        return '';
    }
  }

  String get apiBaseUrl => AppConfig.normalizeApiUrl(defaultHost);
  String get healthUrl => '${AppConfig.normalizeHostUrl(defaultHost)}/health';

  static AppEnvironment fromString(String? value) {
    if (value == null) return AppEnvironment.netlify;
    final clean = value.trim().toLowerCase();
    if (clean == 'local' || clean.contains('localhost') || clean.contains('10.0.2.2')) {
      return AppEnvironment.local;
    }
    if (clean == 'netlify' || clean == 'render' || clean.contains('onrender')) {
      return AppEnvironment.netlify;
    }
    if (clean == 'production' || clean == 'prod' || clean.contains('feelback')) {
      return AppEnvironment.production;
    }
    if (clean == 'custom') {
      return AppEnvironment.custom;
    }
    return AppEnvironment.netlify;
  }
}

class HealthResult {
  final bool isHealthy;
  final String status;
  final String message;
  final int latencyMs;
  final String? error;

  const HealthResult({
    required this.isHealthy,
    required this.status,
    required this.message,
    required this.latencyMs,
    this.error,
  });
}

class AppConfig {
  static const String _prefEnvKey = 'app_backend_environment';
  static const String _prefCustomUrlKey = 'app_backend_custom_url';

  // Compile-time environment configuration
  static const String _compileTimeEnv = String.fromEnvironment('APP_ENV', defaultValue: '');
  static const String _compileTimeApiUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '792080217058-430nba8au4hs4kn0lb6l94o2aoqmjb5r.apps.googleusercontent.com',
  );

  static const Duration networkTimeout = Duration(seconds: 25);

  static AppEnvironment _currentEnvironment = AppEnvironment.netlify;
  static String? _customUrl;
  static bool _initialized = false;

  static AppEnvironment get currentEnvironment => _currentEnvironment;
  static String? get customUrl => _customUrl;

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

  /// Active API base URL for all ApiClient requests (e.g. https://hearmebackendd.onrender.com/api/v1)
  static String get apiBaseUrl {
    // 1. Explicit compile-time API_BASE_URL override has top precedence
    if (_compileTimeApiUrl.isNotEmpty) {
      return normalizeApiUrl(_compileTimeApiUrl);
    }
    // 2. Custom environment URL if selected
    if (_currentEnvironment == AppEnvironment.custom && _customUrl != null && _customUrl!.trim().isNotEmpty) {
      return normalizeApiUrl(_customUrl!);
    }
    // 3. Current active environment
    return _currentEnvironment.apiBaseUrl;
  }

  /// Active root origin (e.g. https://hearmebackendd.onrender.com)
  static String get currentHost => normalizeHostUrl(apiBaseUrl);

  /// Active health check URL (e.g. https://hearmebackendd.onrender.com/health)
  static String get healthUrl => '$currentHost/health';

  /// Initializes the environment from storage or compile-time flags.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEnv = prefs.getString(_prefEnvKey);
      _customUrl = prefs.getString(_prefCustomUrlKey);

      if (savedEnv != null && savedEnv.isNotEmpty) {
        _currentEnvironment = AppEnvironment.fromString(savedEnv);
      } else if (_compileTimeEnv.isNotEmpty) {
        _currentEnvironment = AppEnvironment.fromString(_compileTimeEnv);
      } else {
        // Default to Netlify / Render backend
        _currentEnvironment = AppEnvironment.netlify;
      }
    } catch (_) {
      if (_compileTimeEnv.isNotEmpty) {
        _currentEnvironment = AppEnvironment.fromString(_compileTimeEnv);
      }
    }
  }

  /// Updates active environment and persists to SharedPreferences.
  static Future<void> setEnvironment(AppEnvironment env, {String? customUrl}) async {
    _currentEnvironment = env;
    if (customUrl != null) {
      _customUrl = customUrl.trim();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefEnvKey, env.key);
      if (_customUrl != null) {
        await prefs.setString(_prefCustomUrlKey, _customUrl!);
      }
    } catch (_) {}
  }

  /// Tests connectivity by calling the backend's /health endpoint.
  static Future<HealthResult> checkHealth([String? targetUrl]) async {
    final stopwatch = Stopwatch()..start();
    final urlToTest = targetUrl != null && targetUrl.trim().isNotEmpty
        ? (targetUrl.endsWith('/health') ? targetUrl.trim() : '${normalizeHostUrl(targetUrl)}/health')
        : healthUrl;

    try {
      final uri = Uri.parse(urlToTest);
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final data = jsonDecode(response.body);
          final status = data['status']?.toString() ?? 'UP';
          final message = data['message']?.toString() ?? 'HearMe is running';
          return HealthResult(
            isHealthy: true,
            status: status,
            message: message,
            latencyMs: stopwatch.elapsedMilliseconds,
          );
        } catch (_) {
          return HealthResult(
            isHealthy: true,
            status: 'UP',
            message: 'Connected successfully',
            latencyMs: stopwatch.elapsedMilliseconds,
          );
        }
      } else {
        return HealthResult(
          isHealthy: false,
          status: 'HTTP ${response.statusCode}',
          message: 'Server returned HTTP ${response.statusCode}',
          latencyMs: stopwatch.elapsedMilliseconds,
          error: response.body,
        );
      }
    } catch (e) {
      stopwatch.stop();
      return HealthResult(
        isHealthy: false,
        status: 'UNREACHABLE',
        message: 'Could not connect to $urlToTest',
        latencyMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
      );
    }
  }
}
