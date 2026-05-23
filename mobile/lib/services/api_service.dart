import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show SocketException;
import 'package:flutter/foundation.dart';
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

  // ─── NETWORK ERROR WRAPPER ────────────────────────────────────────────────
  static Future<dynamic> _safeRequest(
      Future<http.Response> Function() fn) async {
    try {
      return _handleResponse(await fn());
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.');
    } on http.ClientException {
      throw ApiException('Network error. Please try again.');
    } on TimeoutException {
      throw ApiException('Request timed out. Please try again.');
    }
  }

  // ─── GET ────────────────────────────────────────────────────────────────────
  static Future<dynamic> get(String path,
      {Map<String, String>? queryParams}) async {
    Uri uri = Uri.parse('$baseUrl$path');
    if (queryParams != null && queryParams.isNotEmpty) {
      uri = uri.replace(queryParameters: queryParams);
    }
    return _safeRequest(
      () => http.get(uri, headers: _headers).timeout(const Duration(seconds: 30)),
    );
  }

  // ─── POST ───────────────────────────────────────────────────────────────────
  static Future<dynamic> post(String path, {Map<String, dynamic>? body}) async {
    return _safeRequest(
      () => http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30)),
    );
  }

  // ─── PUT ────────────────────────────────────────────────────────────────────
  static Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    return _safeRequest(
      () => http
          .put(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 30)),
    );
  }

  // ─── DELETE ─────────────────────────────────────────────────────────────────
  static Future<dynamic> delete(String path) async {
    return _safeRequest(
      () => http
          .delete(Uri.parse('$baseUrl$path'), headers: _headers)
          .timeout(const Duration(seconds: 30)),
    );
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

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.');
    } on http.ClientException {
      throw ApiException('Network error. Please try again.');
    } on TimeoutException {
      throw ApiException('Request timed out. Please try again.');
    }
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

    if (response.statusCode != 404) {
      debugPrint('[API] ERROR ${response.statusCode} ${response.request?.url}: $message');
    }
    throw ApiException(message.toString(), statusCode: response.statusCode);
  }
}
