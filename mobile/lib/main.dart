import 'dart:async' show TimeoutException;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'app.dart';
import 'providers/auth_provider.dart';
import 'providers/task_provider.dart';
import 'providers/wallet_provider.dart';
import 'providers/notification_provider.dart';
import 'services/doh_helper.dart';
import 'services/storage_service.dart';
import 'services/notification_service.dart';

// ── DNS-over-HTTPS fallback HttpOverrides ─────────────────────────────────────
// The Railway *.up.railway.app domain is not resolvable on some ISP DNS servers
// (particularly in India). This override silently falls back to Google DoH
// (dns.google) when system DNS lookup fails, while keeping TLS certificate
// verification fully intact (no bypass — the socket is plain TCP and the
// dart:io HttpClient applies TLS with the original hostname for SNI + cert check).
class _AppHttpOverrides extends HttpOverrides {
  static const String _railwayHost =
      'taskearn-production-production.up.railway.app';

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..connectionFactory = _dnsAwareFactory;
  }

  static Future<ConnectionTask<Socket>> _dnsAwareFactory(
      Uri url, String? proxyHost, int? proxyPort) async {
    final host = url.host;
    final port =
        url.hasPort ? url.port : (url.isScheme('https') ? 443 : 80);

    if (host == _railwayHost) {
      InternetAddress? addr;

      // 1. Try system DNS first (fast path — works when ISP DNS is healthy)
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
      } catch (_) {
        // Any other system DNS failure — fall through to DoH
      }

      // 2. DoH fallback via Google dns.google
      if (addr == null) {
        addr = await DohHelper.resolve(host);
      }

      if (addr == null) {
        throw SocketException('Failed host lookup: $host');
      }

      // Connect plain TCP to the resolved IP.
      // For HTTPS, dart:io's HttpClient wraps this socket with TLS using the
      // ORIGINAL hostname for SNI + certificate verification — fully secure.
      return Socket.startConnect(addr, port);
    }

    // All other hosts: normal system DNS
    final addrs = await InternetAddress.lookup(host);
    if (addrs.isEmpty) throw SocketException('Failed host lookup: $host');
    final addr = addrs.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addrs.first,
    );
    return Socket.startConnect(addr, port);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // DNS-over-HTTPS fallback for ISPs that can't resolve *.up.railway.app
  HttpOverrides.global = _AppHttpOverrides();

  // Firebase (required for FCM)
  await Firebase.initializeApp();

  // Set up FCM + local notifications
  await NotificationService.init();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  await StorageService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => WalletProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: const Workmate4uApp(),
    ),
  );
}

