import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class TaskInProgressScreen extends StatefulWidget {
  final String taskId;
  const TaskInProgressScreen({super.key, required this.taskId});

  @override
  State<TaskInProgressScreen> createState() => _TaskInProgressScreenState();
}

class _TaskInProgressScreenState extends State<TaskInProgressScreen> {
  Task? _task;
  bool _loading = true;
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _load();
    _startLocationUpdates();
  }

  Future<void> _load() async {
    final task =
        await context.read<TaskProvider>().getTaskDetail(widget.taskId);
    if (mounted) setState(() { _task = task; _loading = false; });
  }

  void _startLocationUpdates() {
    LocationService.getLocationStream().listen((position) async {
      if (!mounted) return;
      try {
        await ApiService.post('/tracking/update-location', body: {
          'task_id': widget.taskId,
          'latitude': position.latitude,
          'longitude': position.longitude,
        });
      } catch (_) {}
    });
  }

  Future<void> _markComplete() async {
    setState(() => _completing = true);
    final ok = await context.read<TaskProvider>().markCompleted(widget.taskId);
    if (!mounted) return;
    setState(() => _completing = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marked as complete! Waiting for poster to verify.')),
      );
      context.go('/my-tasks');
    }
  }

  Future<void> _abandon() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Abandon Task'),
        content: const Text(
            'Abandoning a task may incur a penalty. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abandon',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final ok = await context.read<TaskProvider>().abandonTask(widget.taskId);
    if (!mounted) return;
    if (ok) context.go('/my-tasks');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_task == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Task not found')));
    }

    final task = _task!;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task In Progress'),
        actions: [
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
            // Active indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.gradient),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Task Active',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        Text(task.title,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                  Text(
                    '₹${task.budget.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Task info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow('Category', task.category),
                    const Divider(height: 16),
                    _InfoRow('Poster', task.posterName),
                    if (task.address != null) ...[
                      const Divider(height: 16),
                      _InfoRow('Location', task.address!),
                    ],
                    const Divider(height: 16),
                    _InfoRow('Status', task.statusLabel),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Description
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Description',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(task.description,
                        style: const TextStyle(
                            color: AppColors.gray, height: 1.6)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            GradientButton(
              label: 'Mark as Completed',
              loading: _completing,
              onPressed: _markComplete,
              icon: Icons.check_circle_outline,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _abandon,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.danger),
              ),
              child: const Text('Abandon Task'),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: AppColors.dark, fontSize: 13)),
      ],
    );
  }
}
