import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_card.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TaskProvider>().fetchMyTasks();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.gray,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Posted'),
            Tab(text: 'Accepted'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: Consumer<TaskProvider>(
        builder: (_, tasks, __) {
          if (tasks.isLoadingMy) {
            return const Center(child: CircularProgressIndicator());
          }

          return TabBarView(
            controller: _tabs,
            children: [
              _PostedTaskList(tasks: tasks.myPostedTasks),
              _TaskList(
                tasks: tasks.myAcceptedTasks,
                emptyMsg: 'No accepted tasks',
                onTap: (t) => context.push('/task-in-progress/${t.id}'),
              ),
              _CompletedTaskList(
                tasks: tasks.myCompletedTasks,
                onTap: (t) => context.push('/task/${t.id}'),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Posted tasks tab — full poster-management UI ─────────────────────────────
class _PostedTaskList extends StatelessWidget {
  final List<Task> tasks;
  const _PostedTaskList({required this.tasks});

  static const _cancellableStatuses = {'posted', 'accepted', 'in_progress'};
  // After helper submits for verification, cancel is no longer allowed
  static const _nonCancellableStatuses = {
    'completed', 'verify_pending', 'payment_released',
    'verified', 'paid', 'done', 'finished', 'cancelled',
  };

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 64, color: AppColors.grayLight),
            SizedBox(height: 12),
            Text('No posted tasks',
                style: TextStyle(color: AppColors.gray, fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<TaskProvider>().fetchMyTasks(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: tasks.length,
        itemBuilder: (_, i) {
          final t = tasks[i];
          final hasHelper = t.helperId != null && t.helperId!.isNotEmpty;
          final canCancel = _cancellableStatuses.contains(t.status);
          final needsVerify = t.status == 'completed' || t.status == 'verify_pending';

          return Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: InkWell(
              onTap: () => context.push('/task/${t.id}'),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title + budget row ───────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(child: Text(_emoji(t.category),
                              style: const TextStyle(fontSize: 20))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: AppColors.dark),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(t.category,
                                  style: const TextStyle(
                                      color: AppColors.gray, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text('₹${t.budget.toStringAsFixed(0)}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.success)),
                      ],
                    ),

                    // ── Status badge ────────────────────────────────────
                    const SizedBox(height: 8),
                    _StatusBadge(status: t.status, needsVerify: needsVerify),

                    // ── Helper info (shown when task is accepted) ───────
                    if (hasHelper) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.15),
                              child: Text(
                                (t.helperName?.isNotEmpty == true)
                                    ? t.helperName![0].toUpperCase()
                                    : 'H',
                                style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Helper Assigned',
                                      style: TextStyle(
                                          color: AppColors.gray,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500)),
                                  Text(
                                    t.helperName ?? 'Helper',
                                    style: const TextStyle(
                                        color: AppColors.dark,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.person_outline,
                                color: AppColors.primary, size: 18),
                          ],
                        ),
                      ),
                    ],

                    // ── Action buttons ──────────────────────────────────
                    if (canCancel) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: Text(hasHelper
                              ? 'Cancel Task (notify helper)'
                              : 'Cancel Task'),
                          onPressed: () => _confirmCancel(context, t, hasHelper),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            minimumSize: const Size(double.infinity, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                        ),
                      ),
                    ],

                    // ── Verify action banner ────────────────────────────
                    if (needsVerify) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => context.push('/task/${t.id}'),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFFF6B35)
                                    .withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.verified_outlined,
                                  color: Color(0xFFFF6B35), size: 16),
                              SizedBox(width: 6),
                              Text('Tap to verify & release payment',
                                  style: TextStyle(
                                      color: Color(0xFFFF6B35),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmCancel(
      BuildContext context, Task t, bool hasHelper) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Task'),
        content: Text(hasHelper
            ? 'The helper will be notified and released. A refund will be processed to your wallet.'
            : 'Are you sure you want to cancel this task?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, Cancel',
                  style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final ok = await context
        .read<TaskProvider>()
        .cancelTask(t.id, hasHelper: hasHelper);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Task cancelled.' : 'Failed to cancel task.'),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ));
    }
  }

  String _emoji(String cat) {
    const m = {
      'delivery': '🚚', 'pickup': '📦', 'transport': '🚗', 'moving': '🏠',
      'groceries': '🛒', 'cooking': '🍳', 'cleaning': '🧹', 'laundry': '👕',
      'electrician': '⚡', 'plumbing': '🔧', 'carpentry': '🪚',
      'painting': '🎨', 'repair': '🔨', 'tutoring': '📚',
      'data_entry': '💻', 'photography': '📷', 'gardening': '🌱',
      'pet_care': '🐾', 'child_care': '👶', 'elder_care': '👴',
      'errands': '🏃', 'queue_standing': '🕐', 'event_help': '🎉',
      'tech_support': '💡',
    };
    return m[cat] ?? '📋';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool needsVerify;
  const _StatusBadge({required this.status, required this.needsVerify});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'posted' || 'active' => ('Open', AppColors.primary),
      'accepted' || 'in_progress' => ('In Progress', AppColors.warning),
      'completed' || 'verify_pending' => ('Needs Verification', const Color(0xFFFF6B35)),
      'payment_released' => ('Payment Released', AppColors.success),
      'verified' || 'paid' || 'done' => ('Completed', AppColors.success),
      'cancelled' => ('Cancelled', AppColors.grayLight),
      _ => (status, AppColors.gray),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Completed tasks tab — shows 48 h expiry countdown ───────────────────────
class _CompletedTaskList extends StatelessWidget {
  final List<Task> tasks;
  final void Function(Task) onTap;

  const _CompletedTaskList({required this.tasks, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 64, color: AppColors.grayLight),
            SizedBox(height: 12),
            Text('No completed tasks',
                style: TextStyle(color: AppColors.gray, fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<TaskProvider>().fetchMyTasks(),
      child: ListView.builder(
        itemCount: tasks.length,
        itemBuilder: (_, i) {
          final t = tasks[i];
          final expiry = _expiryLabel(t.completedAt);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TaskCard(task: t, onTap: () => onTap(t)),
              if (expiry != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _expiryColor(t.completedAt)
                          .withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      border: Border.all(
                          color: _expiryColor(t.completedAt)
                              .withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.access_time_rounded,
                            size: 13,
                            color: _expiryColor(t.completedAt)),
                        const SizedBox(width: 5),
                        Text(
                          expiry,
                          style: TextStyle(
                              fontSize: 11,
                              color: _expiryColor(t.completedAt),
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Returns a human-readable expiry string based on completedAt + 48 h.
  /// Returns null if no completedAt is available.
  String? _expiryLabel(DateTime? completedAt) {
    if (completedAt == null) return 'Visible for 48 h after completion';
    final expireAt = completedAt.add(const Duration(hours: 48));
    final remaining = expireAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Archived — no longer visible';
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    if (h >= 1) return 'Visible for ${h}h ${m}m more';
    return 'Expires in ${remaining.inMinutes} min';
  }

  Color _expiryColor(DateTime? completedAt) {
    if (completedAt == null) return AppColors.gray;
    final remaining =
        completedAt.add(const Duration(hours: 48)).difference(DateTime.now());
    if (remaining.isNegative) return AppColors.grayLight;
    if (remaining.inHours < 6) return AppColors.danger;
    if (remaining.inHours < 24) return AppColors.warning;
    return AppColors.success;
  }
}


class _TaskList extends StatelessWidget {
  final List<Task> tasks;
  final String emptyMsg;
  final void Function(Task) onTap;

  const _TaskList({
    required this.tasks,
    required this.emptyMsg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.task_alt, size: 64, color: AppColors.grayLight),
            const SizedBox(height: 12),
            Text(emptyMsg,
                style: const TextStyle(color: AppColors.gray, fontSize: 15)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<TaskProvider>().fetchMyTasks(),
      child: ListView.builder(
        itemCount: tasks.length,
        itemBuilder: (_, i) {
          final t = tasks[i];
          return TaskCard(task: t, onTap: () => onTap(t));
        },
      ),
    );
  }
}

