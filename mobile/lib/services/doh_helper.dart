import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Resolves hostnames via DNS-over-HTTPS (Google DoH) when the device's
/// system/ISP DNS cannot resolve a hostname (e.g. *.up.railway.app on some
/// Indian ISP networks).
///
/// Responses are cached for the duration of the DNS record's TTL (clamped
/// to 1 minute – 1 hour) to avoid repeated DoH round-trips.
class DohHelper {
  DohHelper._();

  static final Map<String, _CachedAddress> _cache = {};

  /// Try to resolve [hostname] via Google DNS-over-HTTPS.
  /// Returns a resolved [InternetAddress] (IPv4 preferred), or null on failure.
  static Future<InternetAddress?> resolve(String hostname) async {
    // Return cached value while still valid
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
      final resp = await http
          .get(url, headers: {'Accept': 'application/dns-json'})
          .timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final answers = (data['Answer'] as List<dynamic>?) ?? [];
        for (final raw in answers) {
          final ans = raw as Map<String, dynamic>;
          if (ans['type'] == 1) {
            // Type 1 = A record (IPv4)
            final ipStr = (ans['data'] as String).trim();
            final ttl = ((ans['TTL'] as num?) ?? 300).toInt().clamp(60, 3600);
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
