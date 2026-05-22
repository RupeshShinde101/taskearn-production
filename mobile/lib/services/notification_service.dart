import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level handler for background messages (must be outside any class).
@pragma('vm:entry-point')
Future<void> _bgMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  // Broadcast stream so any widget can listen for tapped notifications.
  static final StreamController<Map<String, dynamic>> onNotificationTap =
      StreamController.broadcast();

  static Future<void> init() async {
    // ── Local notifications setup ──────────────────────────────────────────
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          onNotificationTap.add({'payload': payload});
        }
      },
    );

    // ── FCM permissions ────────────────────────────────────────────────────
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // ── Background handler ─────────────────────────────────────────────────
    FirebaseMessaging.onBackgroundMessage(_bgMessageHandler);

    // ── Foreground messages ────────────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification != null) {
        _showLocalNotification(
          title: notification.title ?? 'Workmate4u',
          body: notification.body ?? '',
          payload: message.data['task_id'],
        );
      }
    });

    // ── App opened from notification ───────────────────────────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap.add(message.data);
    });

    // Check if app was launched by a notification
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      onNotificationTap.add(initial.data);
    }
  }

  static Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (_) {
      return null;
    }
  }

  static void onTokenRefresh(void Function(String) callback) {
    _fcm.onTokenRefresh.listen(callback);
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'workmate4u_main',
      'Workmate4u Notifications',
      channelDescription: 'Task updates and alerts',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(
        android: androidDetails, iOS: iosDetails);

    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
