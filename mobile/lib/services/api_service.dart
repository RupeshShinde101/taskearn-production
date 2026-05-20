import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  static const String _prodUrl =
      'https://taskearn-production-production.up.railway.app/api';
  // static const String _devUrl = 'http://localhost:5000/api';

  static String get baseUrl {
    // Switch to dev URL in debug mode if needed
    return _prodUrl;
  }

  static Map<String, String> get _headers {
    final token = StorageService.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ─── GET ────────────────────────────────────────────────────────────────────
  static Future<dynamic> get(String path,
      {Map<String, String>? queryParams}) async {
    Uri uri = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }

    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 30));

    return _handleResponse(response);
  }

  // ─── POST ───────────────────────────────────────────────────────────────────
  static Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 30));

    return _handleResponse(response);
  }

  // ─── PUT ────────────────────────────────────────────────────────────────────
  static Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    final response = await http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: _headers,
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 30));

    return _handleResponse(response);
  }

  // ─── DELETE ─────────────────────────────────────────────────────────────────
  static Future<dynamic> delete(String path) async {
    final response = await http
        .delete(Uri.parse('$baseUrl$path'), headers: _headers)
        .timeout(const Duration(seconds: 30));

    return _handleResponse(response);
  }

  // ─── MULTIPART (file upload) ─────────────────────────────────────────────────
  static Future<dynamic> uploadFile(
    String path,
    String filePath,
    String fieldName, {
    Map<String, String>? fields,
  }) async {
    final token = StorageService.getToken();
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'));

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));
    if (fields != null) request.fields.addAll(fields);

    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    return _handleResponse(response);
  }

  // ─── RESPONSE HANDLER ───────────────────────────────────────────────────────
  static dynamic _handleResponse(http.Response response) {
    final body = utf8.decode(response.bodyBytes);
    dynamic data;

    try {
      data = jsonDecode(body);
    } catch (_) {
      data = {'message': body};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    final message = data is Map
        ? (data['error'] ?? data['message'] ?? 'Request failed')
        : 'Request failed';

    throw ApiException(message.toString(), statusCode: response.statusCode);
  }
}
