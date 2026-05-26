import 'dart:async';
import 'dart:convert';
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

    // ── Helper final mark-complete (helper gets this after /mark-completed) ─
    case 'task_final_completed':
      title = data['title'] ?? 'Task Complete! 🏆';
      body = data['body'] ?? 'You\'ve fully completed the task. Great work!';
      channelId = 'workmate4u_payment';
      channelName = 'Payments';
      channelDesc = 'Payment alerts and confirmations';
      importance = Importance.max;
      break;

    // ── Poster notified after helper's final mark-complete ─────────────────
    case 'task_final_completed_poster':
      title = data['title'] ?? 'All Done! ✅';
      body = data['body'] ?? 'Your task has been fully completed by the helper.';
      channelId = 'workmate4u_main';
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
    payload: jsonEncode({
      'task_id': data['task_id'] ?? data['taskId'] ?? '',
      'type': type,
    }),
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

  /// Holds the data from getInitialMessage() / getNotificationAppLaunchDetails()
  /// so it can be consumed AFTER the app widget has subscribed to [onNotificationTap].
  /// Using a static store prevents the race-condition where the initial message is
  /// broadcast before any listener exists (broadcast streams don't buffer).
  static Map<String, dynamic>? _pendingInitialTap;

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
          try {
            final decoded = jsonDecode(payload) as Map<String, dynamic>;
            onNotificationTap.add(decoded);
          } catch (_) {
            // Legacy plain task_id payload
            onNotificationTap.add({'task_id': payload, 'type': ''});
          }
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
          type == 'withdrawal_rejected' || type == 'withdrawal_requested' ||
          type == 'task_final_completed';
      final isTaskCompleted = type == 'task_completed' ||
          type == 'verify_pending' ||
          type == 'task_complete_verify' ||
          type == 'verify_and_pay' ||
          type == 'task_final_completed_poster';

      if (notification != null) {
        // FCM message carries a notification payload — show with appropriate channel
        _showLocalNotification(
          title: notification.title ?? 'Workmate4u',
          body: notification.body ?? '',
          taskId: message.data['task_id']?.toString(),
          notificationType: type,
          isMatchedTask: isMatch,
          isPayment: isPayment,
        );
      } else {
        // Data-only FCM message — show for all known types
        String? msgTitle = message.data['title'];
        String? msgBody = message.data['body'];
        // Resolve taskId from either key name the backend may send
        final String? msgTaskId = message.data['task_id']?.toString()
            ?? message.data['taskId']?.toString();

        // Provide fallback title/body for critical notification types so they
        // are always displayed even if the data fields are unexpectedly absent.
        if (msgTitle == null || msgBody == null) {
          switch (type) {
            case 'task_assigned':
              msgTitle ??= 'Task Assigned! 📌';
              msgBody ??= 'You accepted a new task. Complete it to earn.';
              break;
            case 'task_accepted':
              msgTitle ??= 'Task Accepted! 🎉';
              msgBody ??= 'A helper accepted your task.';
              break;
            case 'payment_done':
              msgTitle ??= 'Payment Done! ✅';
              msgBody ??= 'Your payment was processed successfully.';
              break;
            case 'payment_released':
              msgTitle ??= 'Payment Released! 🎉';
              msgBody ??= 'Payment released. Mark the task as completed.';
              break;
            case 'task_completed':
              msgTitle ??= 'Task Completed! 💰 Pay Now';
              msgBody ??= 'Your helper has completed the task. Please pay now.';
              break;
            case 'task_completed_helper':
              msgTitle ??= 'Task Done! ✅';
              msgBody ??= 'Waiting for poster to release payment.';
              break;
            case 'verify_and_pay':
              msgTitle ??= 'Verify & Pay Now ✅';
              msgBody ??= 'Your helper verified the task is done. Please pay to release funds.';
              break;
            case 'task_verify_sent':
              msgTitle ??= 'Verification Sent! ⏳';
              msgBody ??= 'Waiting for the poster to confirm and pay.';
              break;
            case 'task_final_completed':
              msgTitle ??= 'Task Complete! 🏆';
              msgBody ??= 'You\'ve fully completed the task. Great work!';
              break;
            case 'task_final_completed_poster':
              msgTitle ??= 'All Done! ✅';
              msgBody ??= 'Your task has been fully completed by the helper.';
              break;
            default:
              break;
          }
        }

        if (msgTitle != null && msgBody != null) {
          _showLocalNotification(
            title: msgTitle,
            body: msgBody,
            taskId: msgTaskId,
            notificationType: type,
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

    // ── App opened from a background-state FCM notification ─────────────────
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      onNotificationTap.add(message.data);
    });

    // ── Check for notification that LAUNCHED the app (terminated-state tap) ─
    // We intentionally store it rather than broadcast immediately, because the
    // broadcast stream has NO listeners yet at this point in main() — storing
    // lets app.dart consume it after didChangeDependencies() sets up its sub.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      _pendingInitialTap = initial.data;
    }

    // Also check for a tap via a local notification that launched the app.
    // flutter_local_notifications surfaces this through getNotificationAppLaunchDetails.
    final launchDetails = await _local.getNotificationAppLaunchDetails();
    if (launchDetails != null &&
        launchDetails.didNotificationLaunchApp &&
        launchDetails.notificationResponse?.payload != null) {
      final payload = launchDetails.notificationResponse!.payload!;
      try {
        final decoded = jsonDecode(payload) as Map<String, dynamic>;
        _pendingInitialTap ??= decoded; // FCM wins if both present
      } catch (_) {
        _pendingInitialTap ??= {'task_id': payload, 'type': ''};
      }
    }
  }

  /// Returns and clears any notification data that was stored during app launch
  /// (terminated-state tap). Call this once after subscribing to [onNotificationTap].
  static Map<String, dynamic>? consumePendingInitialTap() {
    final tap = _pendingInitialTap;
    _pendingInitialTap = null;
    return tap;
  }

  static Future<String?> getToken() async {
    try {
      return await _fcm.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken error: $e');
      return null;
    }
  }

  static void onTokenRefresh(void Function(String) callback) {
    _fcm.onTokenRefresh.listen(callback);
  }

  /// Shows a local notification when one of the user's posted tasks expires.
  /// Called from TaskProvider when it detects a status transition to 'expired'.
  static Future<void> showTaskExpiredNotification(String taskTitle) async {
    await _showLocalNotification(
      title: 'Task Expired ⏰',
      body: '"$taskTitle" has expired and been removed from the board.',
      notificationType: 'task_expired',
    );
  }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? taskId,
    String? notificationType,
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
      // Always include a payload so tapping the notification always triggers
      // onDidReceiveNotificationResponse and the app can route appropriately
      // even when task_id is absent (e.g. server omits it for some events).
      payload: jsonEncode({
        if (taskId != null && taskId.isNotEmpty) 'task_id': taskId,
        'type': notificationType ?? '',
      }),
    );
  }
}
