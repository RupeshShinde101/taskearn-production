import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Top-level handler for background/terminated messages (must be outside class).
///
/// The backend sends DATA-ONLY FCM messages (no notification key) so that this
/// handler is always called — Android routes data-only messages here regardless
/// of whether the app is in the foreground, background, or terminated.
@pragma('vm:entry-point')
Future<void> _bgMessageHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  // Skip if it somehow has a notification payload (OS would have shown it).
  if (message.notification != null) return;

  final data = message.data;
  final type = data['type']?.toString() ?? '';
  if (type.isEmpty) return;

  // Re-initialise local notifications plugin inside this background isolate
  // and pre-create all three channels so notifications are never silently dropped.
  final local = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  await local.initialize(
    settings: const InitializationSettings(android: androidInit),
  );

  // Pre-create channels (idempotent — safe to call every time).
  final androidPlugin = local
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (androidPlugin != null) {
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'workmate4u_main', 'Task Updates',
      description: 'Task updates and alerts',
      importance: Importance.high,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'workmate4u_matched', 'Matched Tasks',
      description: 'Tasks near you that match your skills profile',
      importance: Importance.max,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'workmate4u_payment', 'Payments',
      description: 'Payment alerts and confirmations',
      importance: Importance.max,
    ));
  }

  // Choose channel, title, body and importance based on notification type.
  String title = data['title'] ?? 'Workmate4u';
  String body = data['body'] ?? '';
  String channelId = 'workmate4u_main';
  String channelName = 'Task Updates';
  String channelDesc = 'Task updates and alerts';
  Importance importance = Importance.high;

  switch (type) {
    // ── Nearby task match ──────────────────────────────────────────────────
    case 'task_matched':
    case 'matched_task':
      title = data['title'] ?? '🎯 New task near you!';
      body = data['body'] ?? 'A task within 10 km matches your profile. Tap to view.';
      channelId = 'workmate4u_matched';
      channelName = 'Matched Tasks';
      channelDesc = 'Tasks near you that match your skills profile';
      importance = Importance.max;
      break;

    // ── Task accepted (poster gets this) ───────────────────────────────────
    case 'task_accepted':
      title = data['title'] ?? 'Task Accepted! 🎉';
      body = data['body'] ?? 'A helper accepted your task.';
      channelId = 'workmate4u_main';
      importance = Importance.max;
      break;

    // ── Task assigned (helper gets this) ───────────────────────────────────
    case 'task_assigned':
      title = data['title'] ?? 'Task Assigned! 📌';
      body = data['body'] ?? 'You accepted a task. Complete it to earn.';
      channelId = 'workmate4u_main';
      importance = Importance.high;
      break;

    // ── Helper marked task complete — poster must pay ──────────────────────
    case 'task_completed':
      title = data['title'] ?? 'Task Completed! 💰 Pay Now';
      body = data['body'] ?? 'Your helper completed the task. Please pay now.';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.max;
      break;

    // ── Helper awaiting payment ────────────────────────────────────────────
    case 'task_completed_helper':
      title = data['title'] ?? 'Task Done! ✅';
      body = data['body'] ?? 'Waiting for poster to release payment.';
      channelId = 'workmate4u_main';
      importance = Importance.high;
      break;

    // ── Helper verified task — poster must verify & pay (new flow) ─────────
    case 'verify_and_pay':
      title = data['title'] ?? 'Verify & Pay Now ✅';
      body = data['body'] ?? 'Your helper verified the task is done. Please pay to release funds.';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.max;
      break;

    // ── Helper sent verification — waiting for poster ──────────────────────
    case 'task_verify_sent':
      title = data['title'] ?? 'Verification Sent! ⏳';
      body = data['body'] ?? 'Waiting for the poster to confirm and pay.';
      channelId = 'workmate4u_main';
      importance = Importance.high;
      break;

    // ── Payment released to helper ─────────────────────────────────────────
    case 'payment_released':
      title = data['title'] ?? 'Payment Released! 🎉';
      body = data['body'] ?? 'Your payment has been released. Mark the task as completed.';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.max;
      break;

    // ── Legacy: direct payment received ───────────────────────────────────
    case 'payment_received':
      title = data['title'] ?? 'Payment Received! 💰';
      body = data['body'] ?? 'Your earnings have been credited to your wallet.';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.max;
      break;

    // ── Poster confirmation that payment went through ──────────────────────
    case 'payment_done':
      title = data['title'] ?? 'Payment Done! ✅';
      body = data['body'] ?? 'Your payment was successful.';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.high;
      break;

    // ── Poster cancelled the accepted task ─────────────────────────────────
    case 'task_cancelled_by_poster':
      title = data['title'] ?? 'Task Cancelled ⚠️';
      body = data['body'] ?? 'The poster has cancelled the task.';
      channelId = 'workmate4u_main';
      importance = Importance.max;
      break;

    // ── Wallet / withdrawal ────────────────────────────────────────────────
    case 'withdrawal_requested':
    case 'withdrawal_approved':
    case 'withdrawal_rejected':
      title = data['title'] ?? '🏦 Withdrawal Update';
      body = data['body'] ?? 'Your withdrawal status has changed.';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.high;
      break;

    // ── Generic fallback ───────────────────────────────────────────────────
    default:
      if (title.isEmpty || body.isEmpty) return; // nothing to show
      break;
  }

  final androidDetails = AndroidNotificationDetails(
    channelId,
    channelName,
    channelDescription: channelDesc,
    importance: importance,
    priority: importance == Importance.max ? Priority.max : Priority.high,
    icon: '@mipmap/ic_launcher',
    color: channelId == 'workmate4u_payment'
        ? const Color(0xFF10B981)  // green for money
        : channelId == 'workmate4u_matched'
            ? const Color(0xFF6366F1)  // indigo for matches
            : const Color(0xFF0EA5E9), // sky-blue for tasks
    enableVibration: true,
    playSound: true,
  );

  await local.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(android: androidDetails),
    payload: data['task_id'],
  );
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static FirebaseMessaging get _fcm => FirebaseMessaging.instance;

  // Broadcast stream so any widget can listen for tapped notifications.
  static final StreamController<Map<String, dynamic>> onNotificationTap =
      StreamController.broadcast();

  // Broadcast stream for foreground task_completed events (poster's in-app popup).
  static final StreamController<Map<String, dynamic>> onTaskCompleted =
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

    // ── Pre-create Android notification channels ───────────────────────────
    // Must exist before FCM delivers any message; creating upfront prevents
    // silent drops when the background isolate shows the first notification.
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
        'workmate4u_main', 'Task Updates',
        description: 'Task updates and alerts',
        importance: Importance.high,
      ));
      await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
        'workmate4u_matched', 'Matched Tasks',
        description: 'Tasks near you that match your skills profile',
        importance: Importance.max,
      ));
      await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
        'workmate4u_payment', 'Payments',
        description: 'Payment alerts and confirmations',
        importance: Importance.max,
      ));
    }

    // ── FCM permissions ────────────────────────────────────────────────────
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

    // ── Background handler ─────────────────────────────────────────────────
    FirebaseMessaging.onBackgroundMessage(_bgMessageHandler);

    // ── Foreground messages ────────────────────────────────────────────────
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[FCM] Foreground message: type=${message.data['type']} hasNotif=${message.notification != null}');
      final notification = message.notification;
      final type = message.data['type']?.toString() ?? '';
      final isMatch = type == 'task_matched' || type == 'matched_task';
      final isPayment = type == 'task_completed' || type == 'verify_and_pay' ||
          type == 'payment_released' || type == 'payment_received' ||
          type == 'payment_done' || type == 'withdrawal_approved' ||
          type == 'withdrawal_rejected' || type == 'withdrawal_requested';
      final isTaskCompleted = type == 'task_completed' ||
          type == 'verify_pending' ||
          type == 'task_complete_verify' ||
          type == 'verify_and_pay';

      if (notification != null) {
        // FCM message carries a notification payload — show with appropriate channel
        _showLocalNotification(
          title: notification.title ?? 'Workmate4u',
          body: notification.body ?? '',
          payload: message.data['task_id'],
          isMatchedTask: isMatch,
          isPayment: isPayment,
        );
      } else {
        // Data-only FCM message — show for all known types
        final title = message.data['title'];
        final body = message.data['body'];
        if (title != null && body != null) {
          _showLocalNotification(
            title: title,
            body: body,
            payload: message.data['task_id'],
            isMatchedTask: isMatch,
            isPayment: isPayment,
          );
        }
      }

      // Notify the app to show an in-app popup when the task poster is active.
      if (isTaskCompleted) {
        final taskId = message.data['task_id']?.toString() ?? '';
        if (taskId.isNotEmpty) {
          onTaskCompleted.add({
            'task_id': taskId,
            'title': notification?.title ?? message.data['title'] ?? 'Task Completed',
            'body': notification?.body ?? message.data['body'] ?? '',
          });
        }
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
    bool isMatchedTask = false,
    bool isPayment = false,
  }) async {
    final AndroidNotificationDetails androidDetails;
    if (isMatchedTask) {
      androidDetails = const AndroidNotificationDetails(
        'workmate4u_matched',
        'Matched Tasks',
        channelDescription: 'Tasks near you that match your skills profile',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF6366F1),
        enableVibration: true,
        playSound: true,
      );
    } else if (isPayment) {
      androidDetails = const AndroidNotificationDetails(
        'workmate4u_payment',
        'Payments',
        channelDescription: 'Payment alerts and confirmations',
        importance: Importance.max,
        priority: Priority.max,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF10B981),
        enableVibration: true,
        playSound: true,
      );
    } else {
      androidDetails = const AndroidNotificationDetails(
        'workmate4u_main',
        'Task Updates',
        channelDescription: 'Task updates and alerts',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFF0EA5E9),
      );
    }
    const iosDetails = DarwinNotificationDetails();
    final details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _local.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
