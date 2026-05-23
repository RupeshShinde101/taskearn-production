import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Key for storing the UTC timestamp of the last "clear all" action.
const _kClearedAtKey = 'notif_cleared_at';

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
      var list = (data['notifications'] as List? ?? data as List? ?? [])
          .map((j) => AppNotification.fromJson(j))
          .toList();

      // Filter out any notifications that were cleared locally.
      // This ensures cleared notifications never reappear even when the
      // backend delete endpoint fails (network error, 404, etc.).
      final clearedStr = StorageService.getString(_kClearedAtKey);
      if (clearedStr != null) {
        final clearedAt = DateTime.tryParse(clearedStr);
        if (clearedAt != null) {
          list = list
              .where((n) => n.createdAt.isAfter(clearedAt))
              .toList();
        }
      }

      _notifications = list;
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
    // Persist cleared timestamp BEFORE optimistic clear so that even if the
    // app restarts mid-operation, the filter is already in place.
    final clearedAt = DateTime.now().toUtc().toIso8601String();
    await StorageService.setString(_kClearedAtKey, clearedAt);

    // Optimistic clear — update UI immediately
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();

    // Best-effort: also delete from backend so other devices are cleared too.
    // The local timestamp filter above guarantees notifications won't reappear
    // on this device even if the backend call fails.
    try {
      await ApiService.delete('/notifications/clear-all');
    } catch (_) {
      try {
        await ApiService.post('/notifications/clear-all');
      } catch (_) {}
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
