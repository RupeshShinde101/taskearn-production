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
    context.read<TaskProvider>().fetchMyTasks();
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
              _TaskList(
                tasks: tasks.myPostedTasks,
                emptyMsg: 'No posted tasks',
                onTap: (t) => context.push('/task/${t.id}'),
                onDelete: (t) => tasks.deleteTask(t.id),
              ),
              _TaskList(
                tasks: tasks.myAcceptedTasks,
                emptyMsg: 'No accepted tasks',
                onTap: (t) => context.push('/task-in-progress/${t.id}'),
              ),
              _TaskList(
                tasks: tasks.myCompletedTasks,
                emptyMsg: 'No completed tasks',
                onTap: (t) => context.push('/task/${t.id}'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  final List<Task> tasks;
  final String emptyMsg;
  final void Function(Task) onTap;
  final Future<void> Function(Task)? onDelete;

  const _TaskList({
    required this.tasks,
    required this.emptyMsg,
    required this.onTap,
    this.onDelete,
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
        itemBuilder: (_, i) => TaskCard(
          task: tasks[i],
          onTap: () => onTap(tasks[i]),
          trailing: onDelete != null && tasks[i].status == 'posted'
              ? IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete Task'),
                        content:
                            const Text('Are you sure you want to delete this task?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(true),
                              child: const Text('Delete',
                                  style:
                                      TextStyle(color: AppColors.danger))),
                        ],
                      ),
                    );
                    if (confirm == true) await onDelete!(tasks[i]);
                  },
                )
              : null,
        ),
      ),
    );
  }
}
