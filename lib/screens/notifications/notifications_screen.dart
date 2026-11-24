import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/notification_model.dart';
import '../../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationProvider>().fetchNotifications();
    });
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Notifications?'),
        content: const Text(
          'Are you sure you want to clear all notifications? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.gray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      await context.read<NotificationProvider>().clearAll();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete $count ${count == 1 ? 'Notification' : 'Notifications'}?'),
        content: const Text('Are you sure you want to delete the selected notifications?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.gray)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final idsToDelete = Set<String>.from(_selectedIds);
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
      await context.read<NotificationProvider>().deleteSelected(idsToDelete);
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _navigateForNotification(BuildContext context, AppNotification n) {
    final type = n.type ?? '';
    // Expired/cancelled notifications belong to deleted tasks.
    // Use go() not push() — /my-tasks lives inside the ShellRoute so push()
    // triggers '!keyReservation.contains(key)' when the tab is already mounted.
    // task_expired: notification already marked read by caller — no navigation.
    if (type == 'task_expired') return;
    const noTaskTypes = {'task_cancelled_confirmation'};
    if (noTaskTypes.contains(type)) {
      // Defer until the current frame (markRead notifyListeners) is done.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/my-tasks');
      });
      return;
    }
    final taskId = n.taskId;
    if (taskId == null || taskId.isEmpty) return;
    const posterTrackingTypes = {
      'task_accepted', 'task_completed', 'verify_and_pay',
    };
    const inProgressTypes = {
      'task_assigned', 'task_completed_helper',
      'task_verify_sent', 'payment_released', 'payment_received',
      'payment_done', 'task_final_completed', 'task_cancelled_by_poster',
    };
    // Defer push to next frame so markRead's notifyListeners() rebuild
    // doesn't conflict with the navigator key reservation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (type == 'chat' || type == 'chat_message') {
        context.push('/chat/$taskId');
      } else if (posterTrackingTypes.contains(type)) {
        context.push('/poster-task-in-progress/$taskId');
      } else if (inProgressTypes.contains(type)) {
        context.push('/task-in-progress/$taskId');
      } else {
        context.push('/task/$taskId');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (_, notif, __) {
        final notifications = notif.notifications;
        final hasNotifications = notifications.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            leading: _selectionMode
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _selectionMode = false;
                      _selectedIds.clear();
                    }),
                  )
                : null,
            title: Text(
              _selectionMode
                  ? '${_selectedIds.length} Selected'
                  : 'Notifications',
            ),
            actions: [
              if (_selectionMode) ...[
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selectedIds.length == notifications.length) {
                        _selectedIds.clear();
                      } else {
                        _selectedIds.clear();
                        _selectedIds.addAll(notifications.map((n) => n.id));
                      }
                    });
                  },
                  child: Text(
                    _selectedIds.length == notifications.length
                        ? 'Deselect All'
                        : 'Select All',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                  tooltip: 'Delete Selected',
                ),
              ] else if (hasNotifications) ...[
                TextButton(
                  onPressed: () => setState(() {
                    _selectionMode = true;
                    _selectedIds.clear();
                  }),
                  child: const Text('Select'),
                ),
                TextButton(
                  onPressed: _confirmClearAll,
                  child: const Text('Clear All'),
                ),
              ],
            ],
          ),
          body: notif.isLoading
              ? const Center(child: CircularProgressIndicator())
              : notifications.isEmpty
                  ? RefreshIndicator(
                      onRefresh: () => notif.fetchNotifications(),
                      child: LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.notifications_none,
                                      size: 64, color: AppColors.grayLight),
                                  SizedBox(height: 12),
                                  Text('No notifications',
                                      style: TextStyle(color: AppColors.gray)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () => notif.fetchNotifications(),
                      child: ListView.separated(
                        itemCount: notifications.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final n = notifications[i];
                          final isSelected = _selectedIds.contains(n.id);
                          return _NotificationTile(
                            notification: n,
                            selectionMode: _selectionMode,
                            isSelected: isSelected,
                            onTap: () {
                              if (_selectionMode) {
                                _toggleSelection(n.id);
                              } else {
                                notif.markRead(n.id);
                                _navigateForNotification(context, n);
                              }
                            },
                            onLongPress: () {
                              if (!_selectionMode) {
                                setState(() {
                                  _selectionMode = true;
                                  _selectedIds.add(n.id);
                                });
                              } else {
                                _toggleSelection(n.id);
                              }
                            },
                          );
                        },
                      ),
                    ),
        );
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NotificationTile({
    required this.notification,
    this.selectionMode = false,
    this.isSelected = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: selectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onTap(),
              activeColor: AppColors.primary,
            )
          : CircleAvatar(
              backgroundColor: _iconBg,
              child: Icon(_icon, color: _iconColor, size: 20),
            ),
      title: Text(
        notification.title,
        style: TextStyle(
          fontWeight: notification.isRead
              ? FontWeight.w400
              : FontWeight.w700,
          color: AppColors.dark,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(notification.body,
              style: const TextStyle(color: AppColors.gray, fontSize: 13)),
          const SizedBox(height: 2),
          Text(
            _formatDate(notification.createdAt),
            style: const TextStyle(
                color: AppColors.grayLight, fontSize: 11),
          ),
        ],
      ),
      trailing: notification.isRead
          ? null
          : Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
            ),
    );
  }

  IconData get _icon {
    switch (notification.type) {
      case 'chat':
      case 'chat_message':   return Icons.chat_bubble_outline_rounded;
      case 'skill_matched':
      case 'task_matched':
      case 'matched_task':
      case 'nearby_task':    return Icons.work_outline_rounded;
      case 'task_accepted':  return Icons.check_circle_outline_rounded;
      case 'task_assigned':  return Icons.assignment_ind_outlined;
      case 'payment_released':
      case 'payment_received':
      case 'payment_done':   return Icons.payments_outlined;
      case 'task_completed':
      case 'verify_and_pay': return Icons.verified_outlined;
      default:               return Icons.notifications_outlined;
    }
  }

  Color get _iconColor {
    switch (notification.type) {
      case 'chat':
      case 'chat_message':   return const Color(0xFF6366F1);
      case 'skill_matched':
      case 'task_matched':
      case 'matched_task':
      case 'nearby_task':    return AppColors.primary;
      case 'payment_released':
      case 'payment_received':
      case 'payment_done':   return AppColors.success;
      case 'task_completed':
      case 'verify_and_pay': return AppColors.warning;
      default:               return AppColors.primary;
    }
  }

  Color get _iconBg => _iconColor.withValues(alpha: 0.1);

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.isNegative || diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
