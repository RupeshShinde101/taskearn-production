import 'package:flutter/material.dart';
import '../models/notification_model.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// Key for storing the UTC timestamp of the last "clear all" action.
const _kClearedAtKey = 'notif_cleared_at';

/// Key for persisting the set of notification IDs the user has read locally.
/// Comma-separated string of IDs (e.g. "12,45,78").
const _kReadIdsKey = 'notif_read_ids';

class NotificationProvider extends ChangeNotifier {
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _loading = false;
  // Tracks IDs marked read locally so re-fetches don't revert the read state.
  // This set is also persisted to storage so it survives app restarts.
  final Set<String> _locallyReadIds = {};
  bool _readIdsLoaded = false;

  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _loading;

  Future<void> fetchNotifications() async {
    _loading = true;
    notifyListeners();

    // Load persisted read IDs on the first fetch so the overlay survives restarts.
    if (!_readIdsLoaded) {
      _readIdsLoaded = true;
      final stored = StorageService.getString(_kReadIdsKey) ?? '';
      if (stored.isNotEmpty) {
        _locallyReadIds.addAll(stored.split(',').where((s) => s.isNotEmpty));
      }
    }

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

      // Apply locally tracked read state so tab-switches don't revert reads.
      _notifications = list.map((n) {
        if (_locallyReadIds.contains(n.id)) {
          return AppNotification.fromJson(
              {..._toJson(n), 'is_read': true});
        }
        return n;
      }).toList();
      _unreadCount = _notifications.where((n) => !n.isRead).length;
    } catch (_) {}

    _loading = false;
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    // Optimistic update first — persists even if the API call fails.
    _locallyReadIds.add(id);
    // Persist to storage so the read state survives app restarts.
    await StorageService.setString(_kReadIdsKey, _locallyReadIds.join(','));
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx >= 0 && !_notifications[idx].isRead) {
      _notifications[idx] = AppNotification.fromJson(
          {..._toJson(_notifications[idx]), 'is_read': true});
      _unreadCount = _notifications.where((n) => !n.isRead).length;
      notifyListeners();
    }
    // Sync with backend in background.
    try {
      await ApiService.post('/notifications/$id/read');
    } catch (_) {}
  }

  Future<void> clearAll() async {
    // Persist cleared timestamp BEFORE optimistic clear so that even if the
    // app restarts mid-operation, the filter is already in place.
    final clearedAt = DateTime.now().toUtc().toIso8601String();
    await StorageService.setString(_kClearedAtKey, clearedAt);

    // Optimistic clear — update UI immediately
    _locallyReadIds.clear();
    await StorageService.setString(_kReadIdsKey, '');
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
