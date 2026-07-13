import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';
import '../../widgets/gradient_button.dart';
import '../tasks/edit_task_screen.dart';

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
    // Refresh user’s task list in the background so hasActiveAcceptedTask is
    // accurate (needed when arriving from a notification without prior browse).
    if (task != null && mounted) {
      context.read<TaskProvider>().fetchMyTasks().catchError((_) {});
    }
  }

  Future<void> _accept() async {
    // KYC must be verified to accept a task
    final auth = context.read<AuthProvider>();
    if (!(auth.user?.isKycVerified ?? false)) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('KYC Verification Required'),
          content: const Text(
            'Complete KYC verification before accepting tasks.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/kyc');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Verify KYC'),
            ),
          ],
        ),
      );
      return;
    }

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
    if (_task == null) return;
    final task = _task!;
    final budget = task.budget;
    final charge = task.serviceCharge ?? 0;
    final total  = budget + charge;

    // Step 1: Check wallet balance
    final wallet = context.read<WalletProvider>();
    await wallet.fetchWallet();
    if (!mounted) return;

    if (wallet.balance.balance < total) {
      final shortfall = total - wallet.balance.balance;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insufficient Wallet Balance'),
          content: Text(
            'You need ₹${total.toStringAsFixed(0)} to pay for this task '
            '(budget ₹${budget.toStringAsFixed(0)}'
            '${charge > 0 ? ' + service charge ₹${charge.toStringAsFixed(0)}' : ''}).\n\n'
            'Current balance: ₹${wallet.balance.balance.toStringAsFixed(0)}\n'
            'Add at least ₹${shortfall.ceil()} to continue.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Money'),
            ),
          ],
        ),
      );
      if (go == true && mounted) context.push('/wallet');
      return;
    }

    // Step 2: Confirm payment amount
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The following will be deducted from your wallet to pay the helper:',
              style: TextStyle(color: AppColors.gray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            _DetailRow('Task Budget', '₹${budget.toStringAsFixed(0)}'),
            if (charge > 0) _DetailRow('Service Charge', '₹${charge.toStringAsFixed(0)}'),
            const Divider(height: 20),
            _DetailRow('Total Payment', '₹${total.toStringAsFixed(0)}', bold: true),
            const SizedBox(height: 6),
            Text(
              'Wallet after payment: ₹${(wallet.balance.balance - total).toStringAsFixed(0)}',
              style: const TextStyle(color: AppColors.gray, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Pay Now'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Step 3: Call pay-helper (no OTP required)
    setState(() => _verifying = true);
    final ok = await context.read<TaskProvider>().payHelper(widget.taskId);
    if (!mounted) return;
    setState(() => _verifying = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment released to helper successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadTask();
      if (mounted) _showRatingDialog(rateHelper: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<TaskProvider>().error ?? 'Payment failed. Please try again.'),
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
      final comment = commentCtrl.text.trim();
      final ok = await context.read<TaskProvider>().rateTask(
            widget.taskId,
            selectedRating,
            comment.isNotEmpty ? comment : null,
          );
      if (mounted) {
        setState(() => _rating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok
              ? 'Rated successfully!'
              : (context.read<TaskProvider>().error ?? 'Failed to submit rating')),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ));
        if (ok) {
          context.read<AuthProvider>().refreshUser();
          await _loadTask();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

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
    final taskProvider = context.watch<TaskProvider>();

    // Show edit button only for the poster's own unaccepted posted tasks
    final canEdit = isPoster &&
        (task.status == 'posted' || task.status == 'open') &&
        task.helperId == null;

    // One-task-at-a-time: check if helper already has an active accepted task
    final hasActiveTask = !isPoster && taskProvider.hasActiveAcceptedTask;
    final activeTask = !isPoster ? taskProvider.activeAcceptedTask : null;

    // What action buttons to show
    final isSuspended = auth.user?.isSuspended ?? false;
    final canAccept = !isSuspended &&
        !isPoster &&
        !isAssignedHelper &&
        (task.status == 'posted' || task.status == 'open') &&
        task.helperId == null &&
        !hasActiveTask;  // one task at a time
    final canCancel = isPoster && task.status == 'posted' && task.helperId == null;
    final canVerify = isPoster &&
        (task.status == 'completed' || task.status == 'verify_pending');
    final canRateHelper = isPoster &&
        (task.status == 'verified' || task.status == 'payment_released' ||
            task.status == 'done' || task.status == 'paid' ||
            task.status == 'completed') &&
        !task.posterHasRatedHelper &&
        task.helperId != null;
    final canRatePoster = isAssignedHelper &&
        (task.status == 'verified' || task.status == 'payment_released' ||
            task.status == 'done' || task.status == 'paid' ||
            task.status == 'completed') &&
        !task.helperHasRatedPoster;
    Widget? bottomBar;
    if (canAccept) {
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GradientButton(
            label: 'Accept Task \u2013 Earn \u20b9${task.netEarning.toStringAsFixed(0)}',
            loading: _accepting,
            onPressed: _accepting ? () {} : _accept,
            icon: Icons.check_circle_outline,
          ),
        ),
      );
    } else if (hasActiveTask &&
        !isPoster &&
        !isAssignedHelper &&
        (task.status == 'posted' || task.status == 'open') &&
        task.helperId == null &&
        !isSuspended) {
      // Helper already has an active accepted task — enforce one at a time
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activeTask != null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('Go to My Active Task'),
                    onPressed: () =>
                        context.push('/task-in-progress/${activeTask.id}'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ],
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
                        'Helper marked this task as complete. Pay now to release payment.',
                        style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GradientButton(
                label: 'Pay Now',
                loading: _verifying,
                onPressed: _verifying ? () {} : _verify,
                icon: Icons.payments_outlined,
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
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Task',
              onPressed: () async {
                final updated = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditTaskScreen(task: task),
                  ),
                );
                if (updated == true && mounted) _loadTask();
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTask,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Active-task warning banner (helper only) ──────────────
              if (hasActiveTask && !isPoster && !isAssignedHelper) ...[
                GestureDetector(
                  onTap: activeTask != null
                      ? () => context
                          .push('/task-in-progress/${activeTask.id}')
                      : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.warning,
                          Color(0xFFD97706),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.assignment_late_outlined,
                            color: Colors.white, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'You have an active task',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                              if (activeTask != null)
                                Text(
                                  activeTask.title,
                                  style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: Colors.white70, size: 22),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],

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
                      const Text(
                        'Total Value',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.gray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text('₹${task.totalAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.dark)),
                      const SizedBox(height: 4),
                      const Text(
                        'Net Earning',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.gray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text('₹${task.netEarning.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.success)),
                      const Text(
                        '− 15% platform fee',
                        style: TextStyle(color: AppColors.gray, fontSize: 11),
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
              // Delivery tasks: show pickup + drop separately
              if (task.pickupAddress != null || task.dropAddress != null) ...[
                if (task.pickupAddress != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.radio_button_checked,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Pickup',
                                style: TextStyle(
                                    color: AppColors.gray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            Text(task.pickupAddress!,
                                style: const TextStyle(color: AppColors.gray)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (task.dropAddress != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on, color: AppColors.danger, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Drop / Destination',
                                style: TextStyle(
                                    color: AppColors.gray,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                            Text(task.dropAddress!,
                                style: const TextStyle(color: AppColors.gray)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ] else
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
              _UserRow(
                name: (task.posterName.isEmpty || task.posterName == 'Anonymous') && isPoster
                    ? (auth.user?.name ?? task.posterName)
                    : task.posterName,
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
                // Contact buttons — shown to poster only when helper phone is available
                if (isPoster && task.helperPhone != null && task.helperPhone!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.call, size: 18),
                          label: const Text('Call'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                          ),
                          onPressed: () async {
                            final uri = Uri(scheme: 'tel', path: task.helperPhone);
                            try {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            } catch (_) {}
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.chat, size: 18),
                          label: const Text('WhatsApp'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF25D366),
                            side: const BorderSide(color: Color(0xFF25D366)),
                          ),
                          onPressed: () async {
                            final phone = task.helperPhone!.replaceAll(RegExp(r'[^\d]'), '');
                            final number = phone.startsWith('91') ? phone : '91$phone';
                            final uri = Uri.parse('https://wa.me/$number');
                            try {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            } catch (_) {}
                          },
                        ),
                      ),
                    ],
                  ),
                ],
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
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      final total = loadingProgress.expectedTotalBytes;
                      final received = loadingProgress.cumulativeBytesLoaded;
                      return Container(
                        height: 200,
                        width: double.infinity,
                        color: AppColors.light,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: total != null ? received / total : null,
                                color: AppColors.primary,
                                strokeWidth: 3,
                              ),
                              const SizedBox(height: 10),
                              const Text('Loading proof image…',
                                  style: TextStyle(color: AppColors.gray, fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    },
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
          backgroundImage: avatarImage(avatar),
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

  String _format(DateTime d) {
    // Convert to IST using the absolute epoch value.
    // microsecondsSinceEpoch is always UTC-based regardless of isUtc flag
    // or device timezone — this prevents any double-conversion on MIUI devices.
    final ist = DateTime.fromMicrosecondsSinceEpoch(
      d.microsecondsSinceEpoch,
      isUtc: true,
    ).add(const Duration(hours: 5, minutes: 30));
    final nowIst = DateTime.fromMicrosecondsSinceEpoch(
      DateTime.now().microsecondsSinceEpoch,
      isUtc: true,
    ).add(const Duration(hours: 5, minutes: 30));

    // 12-hour AM/PM time
    final hour12 = ist.hour == 0 ? 12 : (ist.hour > 12 ? ist.hour - 12 : ist.hour);
    final amPm = ist.hour < 12 ? 'AM' : 'PM';
    final timeStr = '${hour12.toString()}:${ist.minute.toString().padLeft(2, '0')} $amPm';

    final diff = nowIst.difference(ist);

    // Very recent → relative label
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';

    final sameYear = ist.year == nowIst.year;
    final sameDay = ist.year == nowIst.year && ist.month == nowIst.month && ist.day == nowIst.day;
    final yesterday = ist.year == nowIst.year &&
        ist.month == nowIst.subtract(const Duration(days: 1)).month &&
        ist.day == nowIst.subtract(const Duration(days: 1)).day;

    if (sameDay) return 'Today, $timeStr';
    if (yesterday) return 'Yesterday, $timeStr';

    // Within last 6 days → show weekday name
    if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[ist.weekday - 1]}, $timeStr';
    }

    // Older → date + time
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = sameYear
        ? '${ist.day} ${months[ist.month - 1]}'
        : '${ist.day} ${months[ist.month - 1]} ${ist.year}';
    return '$dateStr, $timeStr';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 8, color: AppColors.primary),
          const SizedBox(width: 10),
          Text('$label: ', style: const TextStyle(color: AppColors.gray, fontSize: 13)),
          Text(_format(time), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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

/// Simple two-column label + value row used in payment dialogs.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _DetailRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      color: bold ? AppColors.dark : AppColors.gray,
      fontSize: bold ? 14 : 13,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}
