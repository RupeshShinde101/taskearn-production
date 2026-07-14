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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationProvider>().fetchNotifications();
    });
  }

  void _navigateForNotification(BuildContext context, AppNotification n) {
    final type = n.type ?? '';
    // Expired/cancelled notifications belong to deleted tasks.
    // Use go() not push() — /my-tasks lives inside the ShellRoute so push()
    // triggers '!keyReservation.contains(key)' when the tab is already mounted.
    const noTaskTypes = {'task_expired', 'task_cancelled_confirmation'};
    if (noTaskTypes.contains(type)) {
      // Defer until the current frame (markRead notifyListeners) is done.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/my-tasks');
      });
      return;
    }
    final taskId = n.taskId;
    if (taskId == null || taskId.isEmpty) return;
    const inProgressTypes = {
      'task_assigned', 'task_accepted', 'task_completed_helper',
      'task_verify_sent', 'payment_released', 'payment_received',
      'payment_done', 'verify_and_pay', 'task_completed',
      'task_final_completed', 'task_cancelled_by_poster',
    };
    // Defer push to next frame so markRead's notifyListeners() rebuild
    // doesn't conflict with the navigator key reservation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (inProgressTypes.contains(type)) {
        context.push('/task-in-progress/$taskId');
      } else {
        context.push('/task/$taskId');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () =>
                context.read<NotificationProvider>().clearAll(),
            child: const Text('Clear All'),
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (_, notif, __) {
          if (notif.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (notif.notifications.isEmpty) {
            return const Center(
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
            );
          }

          return RefreshIndicator(
            onRefresh: () => notif.fetchNotifications(),
            child: ListView.separated(
              itemCount: notif.notifications.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final n = notif.notifications[i];
                return _NotificationTile(
                  notification: n,
                  onTap: () {
                    notif.markRead(n.id);
                    _navigateForNotification(context, n);
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;

  const _NotificationTile(
      {required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
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
