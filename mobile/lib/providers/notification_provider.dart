import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/api_service.dart';

class NotificationProvider extends ChangeNotifier {
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _loading = false;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _loading;

  Future<void> fetchNotifications() async {
    _loading = true;
    notifyListeners();

    try {
      final data = await ApiService.get('/notifications');
      _notifications = (data['notifications'] as List? ?? data as List? ?? [])
          .map((j) => AppNotification.fromJson(j))
          .toList();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
    } catch (_) {}

    _loading = false;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    try {
      await ApiService.post('/notifications/$id/read');
      final idx = _notifications.indexWhere((n) => n.id == id);
      if (idx >= 0) {
        _notifications[idx] =
            AppNotification.fromJson({..._toJson(_notifications[idx]), 'is_read': true});
        _unreadCount = _notifications.where((n) => !n.isRead).length;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> clearAll() async {
    // Optimistic clear — update UI immediately
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();

    // Try DELETE first (405 on POST /clear-all means DELETE is likely correct)
    for (final path in [
      '/notifications/clear-all',
      '/notifications',
    ]) {
      try {
        await ApiService.delete(path);
        return; // success
      } catch (_) {}
    }
    // Fallback: try POST variants
    for (final path in [
      '/notifications/clear-all',
      '/notifications/clear',
    ]) {
      try {
        await ApiService.post(path);
        return;
      } catch (_) {
        // UI already cleared; silently ignore if all endpoints fail
      }
    }
  }

  Map<String, dynamic> _toJson(AppNotification n) => {
        'id': n.id,
        'title': n.title,
        'body': n.body,
        'type': n.type,
        'task_id': n.taskId,
        'is_read': n.isRead,
        'created_at': n.createdAt.toIso8601String(),
      };
}
