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
  bool _accepting = false;
  bool _cancelling = false;
  bool _verifying = false;
  bool _rating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  Future<void> _loadTask() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final task = await context.read<TaskProvider>().getTaskDetail(widget.taskId);
    if (!mounted) return;
    setState(() {
      _task = task;
      _loading = false;
      _error = task == null ? 'Task not found' : null;
    });
  }

  Future<void> _accept() async {
    setState(() => _accepting = true);
    final ok = await context.read<TaskProvider>().acceptTask(widget.taskId);
    if (!mounted) return;
    setState(() => _accepting = false);
    if (ok) {
      // Navigate directly to the in-progress screen so helper can start immediately
      context.go('/task-in-progress/${widget.taskId}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<TaskProvider>().error ?? 'Failed to accept task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Task'),
        content: const Text('Are you sure you want to cancel this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _cancelling = true);
    final ok = await context.read<TaskProvider>().cancelTask(widget.taskId);
    if (!mounted) return;
    setState(() => _cancelling = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task cancelled.')),
      );
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<TaskProvider>().error ?? 'Failed to cancel'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _verify() async {
    final otpCtrl = TextEditingController();
    final otp = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Verify Completion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the OTP sent to your registered email/phone to confirm task completion and release payment.',
              style: TextStyle(color: AppColors.gray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Enter OTP',
                prefixIcon: Icon(Icons.lock_outline),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, otpCtrl.text.trim()),
            child: const Text('Verify & Release Payment'),
          ),
        ],
      ),
    );
    if (otp == null || otp.isEmpty || !mounted) return;

    setState(() => _verifying = true);
    final ok = await context.read<TaskProvider>().verifyTask(widget.taskId, otp);
    if (!mounted) return;
    setState(() => _verifying = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task verified! Payment released to helper.'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadTask();
      if (mounted) _showRatingDialog(rateHelper: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<TaskProvider>().error ?? 'Invalid OTP. Try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showRatingDialog({required bool rateHelper}) async {
    if (_task == null) return;
    double selectedRating = 5.0;
    final commentCtrl = TextEditingController();
    final name = rateHelper ? (_task!.helperName ?? 'the helper') : _task!.posterName;
    bool submitted = false;

    // Collect all inputs inside the dialog; do async work AFTER it closes
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('Rate ${rateHelper ? "Helper" : "Poster"}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How was your experience with $name?',
                style: const TextStyle(color: AppColors.gray, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () => setDialog(() => selectedRating = (i + 1).toDouble()),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        i < selectedRating ? Icons.star : Icons.star_border,
                        color: AppColors.warning,
                        size: 36,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  hintText: 'Leave a review...',
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () {
                submitted = true;
                Navigator.pop(ctx); // just close; rateTask runs after dialog
              },
              child: const Text('Submit Rating'),
            ),
          ],
        ),
      ),
    );

    // Dialog is now fully closed — safe to setState
    if (submitted && mounted) {
      setState(() => _rating = true);
      await context.read<TaskProvider>().rateTask(
            widget.taskId,
            selectedRating,
            commentCtrl.text.trim().isNotEmpty ? commentCtrl.text.trim() : null,
          );
      if (mounted) setState(() => _rating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null || _task == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56, color: AppColors.grayLight),
              const SizedBox(height: 12),
              Text(_error ?? 'Something went wrong',
                  style: const TextStyle(color: AppColors.gray)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadTask,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final task = _task!;
    final userId = auth.user?.id ?? '';
    final isPoster = task.posterId == userId;
    final isAssignedHelper = task.helperId == userId;

    // What action buttons to show
    final isSuspended = auth.user?.isSuspended ?? false;
    final canAccept = !isSuspended &&
        !isPoster &&
        !isAssignedHelper &&
        (task.status == 'posted' || task.status == 'open') &&
        task.helperId == null;
    final canCancel = isPoster && task.status == 'posted' && task.helperId == null;
    final canVerify = isPoster && task.status == 'completed';
    final canRateHelper = isPoster &&
        task.status == 'verified' &&
        task.helperRating == null &&
        task.helperId != null;
    final canRatePoster = isAssignedHelper &&
        task.status == 'verified' &&
        task.helperRating == null;
    Widget? bottomBar;
    if (canAccept) {
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GradientButton(
            label: 'Accept Task – Earn ₹${task.budget.toStringAsFixed(0)}',
            loading: _accepting,
            onPressed: _accepting ? () {} : _accept,
            icon: Icons.check_circle_outline,
          ),
        ),
      );
    } else if (isSuspended && !isPoster && task.helperId == null) {
      // Helper is suspended — show warning instead of accept button
      final until = auth.user?.suspendedUntil;
      final msg = (until != null && until.isAfter(DateTime.now()))
          ? 'Suspended until ${until.day}/${until.month} ${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}. Cannot accept tasks.'
          : 'Account suspended. Contact support.';
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.block, color: AppColors.danger, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(msg,
                    style: const TextStyle(
                        color: AppColors.danger, fontSize: 12, height: 1.4)),
              ),
            ]),
          ),
        ),
      );
    } else if (canVerify) {
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Helper marked this task as complete. Verify to release payment.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GradientButton(
                label: 'Verify & Release Payment',
                loading: _verifying,
                onPressed: _verifying ? () {} : _verify,
                icon: Icons.verified_outlined,
              ),
            ],
          ),
        ),
      );
    } else if (canCancel) {
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: _cancelling ? null : _cancel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size(double.infinity, 50),
            ),
            child: _cancelling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger),
                  )
                : const Text('Cancel Task'),
          ),
        ),
      );
    } else if (canRateHelper || canRatePoster) {
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GradientButton(
            label: canRateHelper ? 'Rate the Helper' : 'Rate the Poster',
            loading: _rating,
            onPressed: _rating ? () {} : () => _showRatingDialog(rateHelper: canRateHelper),
            icon: Icons.star_outline,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        actions: const [],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTask,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status & distance row
              Row(
                children: [
                  _StatusBadge(status: task.status),
                  const Spacer(),
                  if (task.distanceKm != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: AppColors.gray),
                        Text(
                          ' ${task.distanceKm!.toStringAsFixed(1)} km',
                          style: const TextStyle(color: AppColors.gray, fontSize: 12),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Title
              Text(task.title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.dark)),
              const SizedBox(height: 10),

              // Category & budget
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
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
                      Text('₹${task.budget.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.success)),
                      if (task.serviceCharge != null && task.serviceCharge! > 0)
                        Text(
                          '+ ₹${task.serviceCharge!.toStringAsFixed(0)} service fee',
                          style: const TextStyle(color: AppColors.gray, fontSize: 11),
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
                  const Icon(Icons.location_on_outlined, color: AppColors.primary, size: 18),
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
              _UserRow(
                name: task.posterName,
                avatar: task.posterAvatar,
                rating: task.posterRating,
                avatarColor: AppColors.primary,
              ),

              // Helper info (if assigned)
              if (task.helperName != null) ...[
                const Divider(height: 28),
                const Text('Assigned Helper',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                _UserRow(
                  name: task.helperName!,
                  rating: task.helperRating,
                  avatarColor: AppColors.success,
                ),
              ],

              // Completion proof
              if (task.completionProof != null) ...[
                const Divider(height: 28),
                const Text('Completion Proof',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    task.completionProof!,
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 80,
                      color: AppColors.light,
                      child: const Center(
                        child: Text('Proof submitted', style: TextStyle(color: AppColors.gray)),
                      ),
                    ),
                  ),
                ),
              ],

              // Timeline info
              const Divider(height: 28),
              const Text('Timeline',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              _TimelineRow('Posted', task.createdAt),
              if (task.acceptedAt != null) _TimelineRow('Accepted', task.acceptedAt!),
              if (task.completedAt != null) _TimelineRow('Completed', task.completedAt!),

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
      bottomNavigationBar: bottomBar,
    );
  }
}

class _UserRow extends StatelessWidget {
  final String name;
  final String? avatar;
  final double? rating;
  final Color avatarColor;

  const _UserRow({
    required this.name,
    this.avatar,
    this.rating,
    required this.avatarColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundImage: avatar != null ? NetworkImage(avatar!) : null,
          backgroundColor: AppColors.light,
          child: avatar == null
              ? Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(color: avatarColor, fontWeight: FontWeight.w700),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
              if (rating != null && rating! > 0)
                Row(
                  children: [
                    const Icon(Icons.star, size: 14, color: AppColors.warning),
                    Text(' ${rating!.toStringAsFixed(1)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final DateTime time;
  const _TimelineRow(this.label, this.time);

  @override
  Widget build(BuildContext context) {
    final d = time.toLocal();
    final formatted =
        '${d.day}/${d.month}/${d.year}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.primary),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(color: AppColors.gray, fontSize: 13)),
          Text(formatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case 'posted':
      case 'open':
        return AppColors.primary;
      case 'accepted':
      case 'in_progress':
        return AppColors.warning;
      case 'completed':
        return const Color(0xFFFF6B35);
      case 'verified':
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
      case 'open':
        return 'Open';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Awaiting Verification';
      case 'verified':
        return 'Verified ✓';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _label,
        style: TextStyle(color: _color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
