import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class TaskDetailScreen extends StatefulWidget {
  final String taskId;
  const TaskDetailScreen({super.key, required this.taskId});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  Task? _task;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  Future<void> _loadTask() async {
    final task =
        await context.read<TaskProvider>().getTaskDetail(widget.taskId);
    if (!mounted) return;
    setState(() {
      _task = task;
      _loading = false;
      _error = task == null ? 'Task not found' : null;
    });
  }

  Future<void> _accept() async {
    final ok = await context.read<TaskProvider>().acceptTask(widget.taskId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task accepted! Go to My Tasks.')),
      );
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(context.read<TaskProvider>().error ?? 'Failed to accept')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(_error ?? 'Error')),
      );
    }

    final task = _task!;
    final isMyTask = task.posterId == auth.user?.id;
    final canAccept =
        !isMyTask && task.status == 'posted' && task.helperId == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        actions: [
          if (!isMyTask)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => context.push('/chat/${task.id}',
                  extra: {'poster_name': task.posterName}),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badge
            Row(
              children: [
                _StatusBadge(status: task.status),
                const Spacer(),
                if (task.distanceKm != null)
                  Row(
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: AppColors.gray),
                      Text(
                        ' ${task.distanceKm!.toStringAsFixed(1)} km away',
                        style: const TextStyle(
                            color: AppColors.gray, fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Title
            Text(task.title,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark)),
            const SizedBox(height: 8),

            // Category & budget
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(task.category,
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${task.budget.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.success),
                    ),
                    if (task.serviceCharge != null && task.serviceCharge! > 0)
                      Text(
                        '+ ₹${task.serviceCharge!.toStringAsFixed(0)} service',
                        style: const TextStyle(
                            color: AppColors.gray, fontSize: 11),
                      ),
                  ],
                ),
              ],
            ),

            const Divider(height: 28),

            // Description
            const Text('Description',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            Text(task.description,
                style: const TextStyle(color: AppColors.gray, height: 1.6)),

            const Divider(height: 28),

            // Location
            const Text('Location',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    color: AppColors.primary, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    task.address ?? '${task.latitude}, ${task.longitude}',
                    style: const TextStyle(color: AppColors.gray),
                  ),
                ),
              ],
            ),

            const Divider(height: 28),

            // Poster info
            const Text('Posted By',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 10),
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: task.posterAvatar != null
                      ? NetworkImage(task.posterAvatar!)
                      : null,
                  backgroundColor: AppColors.light,
                  child: task.posterAvatar == null
                      ? Text(
                          task.posterName.isNotEmpty
                              ? task.posterName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700))
                      : null,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.posterName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Row(
                      children: [
                        const Icon(Icons.star,
                            size: 14, color: AppColors.warning),
                        Text(' ${task.posterRating.toStringAsFixed(1)}',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.gray)),
                      ],
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),

      bottomNavigationBar: canAccept
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GradientButton(
                  label: 'Accept Task – Earn ₹${task.budget.toStringAsFixed(0)}',
                  onPressed: _accept,
                ),
              ),
            )
          : null,
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case 'posted':
        return AppColors.primary;
      case 'accepted':
      case 'in_progress':
        return AppColors.warning;
      case 'completed':
      case 'verified':
        return AppColors.success;
      case 'cancelled':
        return AppColors.danger;
      default:
        return AppColors.gray;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.3)),
      ),
      child: Text(
        Task(
          id: '',
          title: '',
          description: '',
          category: '',
          budget: 0,
          status: status,
          posterId: '',
          posterName: '',
          latitude: 0,
          longitude: 0,
          createdAt: DateTime.now(),
        ).statusLabel,
        style: TextStyle(
            color: _color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
