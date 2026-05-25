import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Resolves hostnames via DNS-over-HTTPS (Google DoH) when the device's
/// ISP DNS cannot resolve them (e.g. *.up.railway.app on some Indian ISPs).
///
/// Uses a dedicated HTTP client that connects directly to Google's well-known
/// DNS IP addresses (8.8.8.8 / 8.8.4.4), eliminating any circular DNS
/// dependency — DoH works even when system DNS is completely broken.
///
/// Results are cached per DNS TTL (clamped 60 s – 1 h).
class DohHelper {
  DohHelper._();

  static final Map<String, _CachedAddress> _cache = {};

  // Google's stable anycast DNS IPs — used to reach dns.google without DNS.
  static const List<String> _googleDnsIps = ['8.8.8.8', '8.8.4.4'];

  // Dedicated HTTP client whose connectionFactory bypasses DNS for dns.google
  // by connecting directly to the known IPs.  The dart:io HttpClient still
  // performs TLS with hostname 'dns.google' (SNI + cert verification) — secure.
  static final http.Client _dohClient = IOClient(
    HttpClient()
      ..connectionFactory =
          (Uri url, String? proxyHost, int? proxyPort) async {
        final port =
            url.hasPort ? url.port : (url.isScheme('https') ? 443 : 80);

        if (url.host == 'dns.google') {
          Exception? lastErr;
          for (final ip in _googleDnsIps) {
            try {
              return await Socket.startConnect(
                InternetAddress(ip, type: InternetAddressType.IPv4),
                port,
              ).timeout(const Duration(seconds: 5));
            } catch (e) {
              lastErr = e is Exception ? e : Exception(e.toString());
            }
          }
          throw lastErr ?? SocketException('Cannot reach dns.google');
        }

        // Any other host: normal system DNS (shouldn't be needed in practice).
        final addrs = await InternetAddress.lookup(url.host);
        if (addrs.isEmpty) {
          throw SocketException('Failed host lookup: ${url.host}');
        }
        final addr = addrs.firstWhere(
          (a) => a.type == InternetAddressType.IPv4,
          orElse: () => addrs.first,
        );
        return Socket.startConnect(addr, port);
      },
  );

  /// Try to resolve [hostname] via Google DNS-over-HTTPS.
  /// Returns a resolved [InternetAddress] (IPv4), or null on failure.
  static Future<InternetAddress?> resolve(String hostname) async {
    final cached = _cache[hostname];
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      debugPrint('[DoH] Cache hit: $hostname → ${cached.address.address}');
      return cached.address;
    }

    debugPrint('[DoH] Resolving $hostname via Google DoH…');
    try {
      final url = Uri.parse(
        'https://dns.google/resolve'
        '?name=${Uri.encodeComponent(hostname)}&type=A',
      );
      final resp = await _dohClient
          .get(url, headers: {'Accept': 'application/dns-json'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final answers = (data['Answer'] as List<dynamic>?) ?? [];
        for (final raw in answers) {
          final ans = raw as Map<String, dynamic>;
          if (ans['type'] == 1) {
            // A record (IPv4)
            final ipStr = (ans['data'] as String).trim();
            final ttl =
                ((ans['TTL'] as num?) ?? 300).toInt().clamp(60, 3600);
            final address =
                InternetAddress(ipStr, type: InternetAddressType.IPv4);
            _cache[hostname] = _CachedAddress(
              address: address,
              expires: DateTime.now().add(Duration(seconds: ttl)),
            );
            debugPrint('[DoH] Resolved $hostname → $ipStr (TTL ${ttl}s)');
            return address;
          }
        }
      }
    } catch (e) {
      debugPrint('[DoH] Resolution failed for $hostname: $e');
    }
    return null;
  }
}

class _CachedAddress {
  final InternetAddress address;
  final DateTime expires;

  const _CachedAddress({required this.address, required this.expires});
}
