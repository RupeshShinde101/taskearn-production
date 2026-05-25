import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Resolves hostnames via DNS-over-HTTPS when ISP DNS is broken.
///
/// Tries two providers in order:
///   1. Google   (8.8.8.8 / 8.8.4.4)
///   2. Cloudflare (1.1.1.1 / 1.0.0.1)
///
/// Both providers are reached via hardcoded IPs, so DoH works even when
/// system DNS cannot resolve dns.google or cloudflare-dns.com.
/// The dart:io HttpClient still performs TLS with the original hostname
/// for SNI + certificate verification — fully secure.
///
/// Results are cached per DNS TTL (clamped 60 s – 1 h).
class DohHelper {
  DohHelper._();

  static final Map<String, _CachedAddress> _cache = {};

  // Known stable anycast IPs for each DoH provider.
  static const List<String> _googleIps = ['8.8.8.8', '8.8.4.4'];
  static const List<String> _cloudflareIps = ['1.1.1.1', '1.0.0.1'];

  // Dedicated HTTP client whose connectionFactory bypasses DNS entirely for
  // both dns.google and cloudflare-dns.com by connecting to known IPs.
  static final http.Client _dohClient = IOClient(
    HttpClient()
      ..connectionFactory =
          (Uri url, String? proxyHost, int? proxyPort) async {
        final port =
            url.hasPort ? url.port : (url.isScheme('https') ? 443 : 80);

        List<String>? ips;
        if (url.host == 'dns.google') {
          ips = _googleIps;
        } else if (url.host == 'cloudflare-dns.com') {
          ips = _cloudflareIps;
        }

        if (ips != null) {
          // DoH is always HTTPS. connectionFactory bypasses dart:io's auto-TLS,
          // so we must do TLS ourselves:
          //   plain TCP to the hardcoded IP  →  SecureSocket.secure with the
          //   real hostname for SNI →  wrap in ConnectionTask.fromSocket.
          final hostname = url.host;
          final secureSocketFuture =
              _connectSecureToFirst(ips, port, hostname);
          return Future.value(
              ConnectionTask.fromSocket(secureSocketFuture, () {}));
        }

        // Any other host (not expected in practice): normal system DNS.
        final addrs = await InternetAddress.lookup(url.host);
        if (addrs.isEmpty) {
          throw SocketException('Failed host lookup: ${url.host}');
        }
        final addr = addrs.firstWhere(
          (a) => a.type == InternetAddressType.IPv4,
          orElse: () => addrs.first,
        );
        if (url.isScheme('https')) {
          final sf = Socket.connect(addr, port).then(
              (s) => SecureSocket.secure(s, host: url.host));
          return Future.value(ConnectionTask.fromSocket(sf, () {}));
        }
        return Socket.startConnect(addr, port);
      },
  );

  /// Try to resolve [hostname] via DoH.
  /// Tries Google DoH first, then Cloudflare DoH as backup.
  /// Returns a resolved [InternetAddress] (IPv4), or null if both fail.
  static Future<InternetAddress?> resolve(String hostname) async {
    final cached = _cache[hostname];
    if (cached != null && DateTime.now().isBefore(cached.expires)) {
      debugPrint('[DoH] Cache hit: $hostname → ${cached.address.address}');
      return cached.address;
    }

    // 1. Google DoH
    var addr = await _queryProvider(
      hostname,
      'https://dns.google/resolve'
      '?name=${Uri.encodeComponent(hostname)}&type=A',
    );

    // 2. Cloudflare DoH
    addr ??= await _queryProvider(
      hostname,
      'https://cloudflare-dns.com/dns-query'
      '?name=${Uri.encodeComponent(hostname)}&type=A',
    );

    return addr;
  }

  static Future<InternetAddress?> _queryProvider(
      String hostname, String doHUrl) async {
    debugPrint('[DoH] Querying $doHUrl for $hostname…');
    try {
      final resp = await _dohClient
          .get(Uri.parse(doHUrl),
              headers: {'Accept': 'application/dns-json'})
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
      debugPrint('[DoH] $doHUrl failed for $hostname: $e');
    }
    return null;
  }

  /// Tries each IP in order via plain TCP, then upgrades to TLS with [hostname]
  /// as the SNI name. Returns the first successful [SecureSocket].
  static Future<SecureSocket> _connectSecureToFirst(
      List<String> ips, int port, String hostname) async {
    Object? lastErr;
    for (final ip in ips) {
      try {
        final plain = await Socket.connect(
          InternetAddress(ip, type: InternetAddressType.IPv4),
          port,
        ).timeout(const Duration(seconds: 5));
        return await SecureSocket.secure(plain, host: hostname)
            .timeout(const Duration(seconds: 10));
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? SocketException('Cannot connect to $hostname');
  }
}

class _CachedAddress {
  final InternetAddress address;
  final DateTime expires;

  const _CachedAddress({required this.address, required this.expires});
}

