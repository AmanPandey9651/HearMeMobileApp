class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080/api/v1',
  );

  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '792080217058-430nba8au4hs4kn0lb6l94o2aoqmjb5r.apps.googleusercontent.com',
  );

  static const Duration networkTimeout = Duration(seconds: 25);
}
