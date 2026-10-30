import 'package:flutter/material.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import '../utils/image_utils.dart';

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;
  final Widget? trailing;

  const TaskCard({
    super.key,
    required this.task,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Category icon badge
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        TaskCategory.iconFor(task.category),
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.dark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          task.category,
                          style: const TextStyle(
                            color: AppColors.gray,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Task Budget
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Task Budget',
                        style: TextStyle(fontSize: 10, color: AppColors.gray, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\u20b9${task.budget.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.primary),
                      ),
                      if (task.distanceKm != null)
                        Text(
                          '${task.distanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            color: AppColors.grayLight,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),

                  if (trailing != null) ...[
                    const SizedBox(width: 4),
                    trailing!,
                  ],
                ],
              ),

              // Route preview for delivery, pickup, transport, moving
              if (task.isDeliveryCategory && task.effectiveDropAddress != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.radio_button_checked, size: 12, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          task.effectivePickupAddress.isNotEmpty
                              ? task.effectivePickupAddress
                              : 'Pickup',
                          style: const TextStyle(fontSize: 11, color: AppColors.dark, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, size: 12, color: AppColors.grayLight),
                      ),
                      const Icon(Icons.location_on, size: 12, color: AppColors.danger),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          task.effectiveDropAddress!,
                          style: const TextStyle(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Description preview
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  task.description,
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontSize: 13,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 10),

              // Footer: poster, status, location
              Row(
                children: [
                  // Poster avatar
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.light,
                    backgroundImage: avatarImage(task.posterAvatar),
                    child: task.posterAvatar == null
                        ? Text(
                            task.posterName.isNotEmpty
                                ? task.posterName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.posterName,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.gray),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (task.posterRating > 0)
                          Row(
                            children: [
                              const Icon(Icons.star, size: 11, color: AppColors.warning),
                              const SizedBox(width: 2),
                              Text(
                                task.posterRating.toStringAsFixed(1),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.gray),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                  // Status chip
                  _StatusChip(status: task.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'posted':
        return AppColors.primary;
      case 'accepted':
      case 'in_progress':
      case 'verify_pending':
        return AppColors.warning;
      case 'completed':
      case 'verified':
      case 'payment_released':
      case 'paid':
      case 'done':
        return AppColors.success;
      case 'cancelled':
        return AppColors.danger;
      default:
        return AppColors.gray;
    }
  }

  String get _label {
    switch (status) {
      case 'posted':
        return 'Open';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'verify_pending':
        return 'Verify Pending';
      case 'payment_released':
        return 'Payment Released';
      case 'completed':
      case 'verified':
      case 'paid':
      case 'done':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _label,
        style: TextStyle(
            color: _color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
