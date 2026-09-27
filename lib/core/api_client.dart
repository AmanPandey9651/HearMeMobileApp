import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final dynamic body;
  ApiException(this.statusCode, this.message, [this.body]);
  @override
  String toString() => message;
}

class ApiClient {
  final http.Client _client = http.Client();
  String? token;
  Future<void> Function()? onUnauthorized;
  bool _handlingUnauthorized = false;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final clean = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('${AppConfig.apiBaseUrl}$clean');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: query.map((k, v) => MapEntry(k, '$v')));
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'X-Client-Platform': 'mobile',
        if (token?.isNotEmpty == true) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);
  Future<dynamic> post(String path, {dynamic body}) => _send('POST', path, body: body);
  Future<dynamic> put(String path, {dynamic body}) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, {dynamic body}) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path, {dynamic body}) => _send('DELETE', path, body: body);

  Future<dynamic> _send(String method, String path, {dynamic body, Map<String, dynamic>? query}) async {
    final request = http.Request(method, _uri(path, query));
    request.headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _client.send(request).timeout(AppConfig.networkTimeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 204) return null;
    dynamic decoded;
    if (response.body.trim().isEmpty) {
      decoded = null;
    } else {
      try {
        decoded = jsonDecode(response.body);
      } catch (_) {
        decoded = response.body;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed (${response.statusCode})';
      if (decoded is Map) {
        message = '${decoded['message'] ?? decoded['detail'] ?? decoded['error'] ?? message}';
      } else if (decoded is String && decoded.isNotEmpty) {
        message = decoded;
      }
      if (response.statusCode == 401 && onUnauthorized != null && !_handlingUnauthorized) {
        _handlingUnauthorized = true;
        try { await onUnauthorized!(); } catch (_) {} finally { _handlingUnauthorized = false; }
      }
      throw ApiException(response.statusCode, message, decoded);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> multipart(
    String path, {
    required File file,
    String fieldName = 'file',
    Map<String, String> fields = const {},
  }) async {
    final req = http.MultipartRequest('POST', _uri(path));
    if (token?.isNotEmpty == true) req.headers['Authorization'] = 'Bearer $token';
    req.fields.addAll(fields);
    req.files.add(await http.MultipartFile.fromPath(fieldName, file.path));
    final streamed = await req.send().timeout(AppConfig.networkTimeout);
    final response = await http.Response.fromStream(streamed);
    final dynamic decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && onUnauthorized != null && !_handlingUnauthorized) {
        _handlingUnauthorized = true;
        try { await onUnauthorized!(); } catch (_) {} finally { _handlingUnauthorized = false; }
      }
      throw ApiException(response.statusCode, '${decoded is Map ? decoded['message'] ?? 'Upload failed' : 'Upload failed'}', decoded);
    }
    return Map<String, dynamic>.from(decoded as Map);
  }
}
