import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../services/storage_service.dart';
import 'doh_helper.dart';

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
  static const String _railwayHost =
      'taskearn-production-production.up.railway.app';
  // Last-resort IP confirmed working via direct TCP+TLS test.
  // Update if Railway migrates the deployment to a new IP.
  static const String _railwayFallbackIp = '66.33.22.54';

  static String get baseUrl => _prodUrl;

  // ─── Custom HTTP client with DoH fallback for Railway host ─────────────────
  // Only this client has a connectionFactory — Firebase, Google Sign-In, and
  // all other packages use the default system-DNS client unaffected.
  static http.Client? _client;
  static http.Client get _httpClient =>
      _client ??= IOClient(_buildDartClient());

  static HttpClient _buildDartClient() {
    return HttpClient()..connectionFactory = _connectionFactory;
  }

  /// DNS-aware connection factory:
  /// • Proxy connections go to the proxy host (not the target).
  /// • Railway host: system DNS (4 s) → DoH fallback via [DohHelper].
  /// • All other hosts: system DNS as normal.
  /// IMPORTANT: When connectionFactory is set, dart:io does NOT auto-wrap in
  /// TLS. We must return a SecureSocket for HTTPS so TLS is established with
  /// the original hostname for SNI + cert verification — no security compromise.
  static Future<ConnectionTask<Socket>> _connectionFactory(
      Uri url, String? proxyHost, int? proxyPort) async {
    // ── Proxy: connect to the proxy, dart:io handles the CONNECT tunnel ──────
    if (proxyHost != null) {
      final addrs = await InternetAddress.lookup(proxyHost);
      if (addrs.isEmpty) throw SocketException('Failed host lookup: $proxyHost');
      final addr = addrs.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => addrs.first,
      );
      return Socket.startConnect(addr, proxyPort!);
    }

    final host = url.host;
    final port =
        url.hasPort ? url.port : (url.isScheme('https') ? 443 : 80);

    // ── Railway backend: try system DNS → DoH fallback ───────────────────────
    if (host == _railwayHost) {
      InternetAddress? addr;

      try {
        final addrs = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 4));
        if (addrs.isNotEmpty) {
          addr = addrs.firstWhere(
            (a) => a.type == InternetAddressType.IPv4,
            orElse: () => addrs.first,
          );
        }
      } on SocketException {
        // System DNS returned an error — fall through to DoH
      } on TimeoutException {
        // System DNS timed out — fall through to DoH
      } catch (_) {}

      addr ??= await DohHelper.resolve(host);

      // Absolute last resort: hardcoded known IP.
      // TCP+TLS to this IP with SNI=hostname is confirmed working.
      if (addr == null) {
        debugPrint('[API] DNS+DoH both failed — using hardcoded IP $_railwayFallbackIp');
        addr = InternetAddress(_railwayFallbackIp,
            type: InternetAddressType.IPv4);
      }

      debugPrint('[API] Connecting to $host via ${addr.address}:$port');
      // connectionFactory bypasses dart:io's auto-TLS wrapping.
      // For HTTPS: plain TCP to the resolved/hardcoded IP, then TLS with
      // hostname as SNI via SecureSocket.secure, wrapped in ConnectionTask.
      if (url.isScheme('https')) {
        final sf = Socket.connect(addr, port)
            .timeout(const Duration(seconds: 10))
            .then((plain) => SecureSocket.secure(plain, host: host)
                .timeout(const Duration(seconds: 10)));
        return Future.value(ConnectionTask.fromSocket(sf, () {}));
      }
      return Socket.startConnect(addr, port);
    }

    // ── All other hosts: normal system DNS ──────────────────────────────────
    final addrs = await InternetAddress.lookup(host);
    if (addrs.isEmpty) throw SocketException('Failed host lookup: $host');
    final addr = addrs.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addrs.first,
    );
    if (url.isScheme('https')) {
      final sf = Socket.connect(addr, port)
          .timeout(const Duration(seconds: 10))
          .then((plain) => SecureSocket.secure(plain, host: host)
              .timeout(const Duration(seconds: 10)));
      return Future.value(ConnectionTask.fromSocket(sf, () {}));
    }
    return Socket.startConnect(addr, port);
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
    } on SocketException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('failed host lookup') || msg.contains('network is unreachable')) {
        throw ApiException('Cannot reach the server. Check your internet connection and try again.', statusCode: null);
      }
      throw ApiException('No internet connection. Please check your network.', statusCode: null);
    } on TlsException {
      throw ApiException('Secure connection failed. Please try again.', statusCode: null);
    } on HttpException {
      throw ApiException('Network error. Please try again.', statusCode: null);
    } on http.ClientException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('handshake') || msg.contains('tls') || msg.contains('certificate')) {
        throw ApiException('Secure connection failed. Please try again.', statusCode: null);
      }
      throw ApiException('Network error. Please try again.', statusCode: null);
    } on TimeoutException {
      throw ApiException('Request timed out. Please try again.', statusCode: null);
    } catch (e) {
      // Catch-all safety net for unexpected platform errors
      throw ApiException('Connection error. Please try again.', statusCode: null);
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
      () => _httpClient.get(uri, headers: _headers).timeout(const Duration(seconds: 30)),
    );
  }

  // ─── POST ───────────────────────────────────────────────────────────────────
  static Future<dynamic> post(String path,
      {Map<String, dynamic>? body,
      Duration timeout = const Duration(seconds: 30)}) async {
    return _safeRequest(
      () => _httpClient
          .post(
            Uri.parse('$baseUrl$path'),
            headers: _headers,
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(timeout),
    );
  }

  // ─── PUT ────────────────────────────────────────────────────────────────────
  static Future<dynamic> put(String path, {Map<String, dynamic>? body}) async {
    return _safeRequest(
      () => _httpClient
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
      () => _httpClient
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
      final streamed = await _httpClient.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response);
    } on SocketException {
      throw ApiException('No internet connection. Please check your network.', statusCode: null);
    } on TlsException {
      throw ApiException('Secure connection failed. Please try again.', statusCode: null);
    } on http.ClientException {
      throw ApiException('Network error. Please try again.', statusCode: null);
    } on TimeoutException {
      throw ApiException('Request timed out. Please try again.', statusCode: null);
    } catch (e) {
      throw ApiException('Connection error. Please try again.', statusCode: null);
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
