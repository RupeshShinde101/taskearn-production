import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/task.dart';
import '../../models/grocery_item.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/confirm_payment_dialog.dart';
import '../../widgets/profile_mode_switch_dialog.dart';
import '../../widgets/hero_map_background.dart';
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
  int _autoRetryCount = 0;
  static const _maxAutoRetries = 3;

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  Future<void> _loadTask({bool isAutoRetry = false}) async {
    if (!isAutoRetry) _autoRetryCount = 0;
    setState(() { _loading = true; _error = null; });
    final provider = context.read<TaskProvider>();
    final task = await provider.getTaskDetail(widget.taskId);
    if (!mounted) return;

    if (task == null && _autoRetryCount < _maxAutoRetries) {
      _autoRetryCount++;
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) _loadTask(isAutoRetry: true);
      return;
    }

    setState(() {
      _task = task;
      _loading = false;
      _error = task == null
          ? (provider.error?.isNotEmpty == true
              ? provider.error
              : 'Task not found or no longer available.')
          : null;
    });
    if (task != null && mounted) {
      final currentUserId = context.read<AuthProvider>().user?.id;
      final isPosterUser = currentUserId != null && task.posterId == currentUserId;
      final hasHelperAssigned =
          (task.helperId != null && task.helperId!.isNotEmpty) ||
              task.status == 'accepted' ||
              task.status == 'in_progress' ||
              task.status == 'completed' ||
              task.status == 'verify_pending';
      if (isPosterUser && hasHelperAssigned) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.pushReplacement('/poster-task-in-progress/${task.id}');
          }
        });
        return;
      }
      context.read<TaskProvider>().fetchMyTasks().catchError((_) {});
    }
  }

  Future<void> _accept() async {
    // KYC must be verified to accept a task
    final auth = context.read<AuthProvider>();
    if (!auth.isHelperMode) {
      final switched = await showProfileModeSwitchDialog(
        context,
        targetMode: 'helper',
        title: 'Switch to Helper Profile',
        message:
            'Accepting tasks requires switching to your Helper profile. Would you like to switch to Helper mode now to accept this task?',
        actionLabel: 'Switch to Helper & Accept',
      );
      if (switched != true) return;
    }
    if (!mounted) return;
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
                if (mounted) context.push('/kyc');
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
    final taskProvider = context.read<TaskProvider>();
    final ok = await taskProvider.acceptTask(widget.taskId);
    if (!mounted) return;
    setState(() => _accepting = false);
    if (ok) {
      try {
        context
            .read<NotificationProvider>()
            .removeTaskNotifications(widget.taskId);
      } catch (_) {}
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
    final posterFee = task.posterFee;
    final total  = task.totalPosterCost;

    // Step 1: Check wallet balance
    final wallet = context.read<WalletProvider>();
    await wallet.fetchWallet();
    if (!mounted) return;

    if (wallet.balance.balance < total) {
      await ConfirmPaymentDialog.showInsufficientBalance(
        context: context,
        totalCost: total,
        currentBalance: wallet.balance.balance,
        budget: budget,
        serviceCharge: charge,
        posterFee: posterFee,
      );
      return;
    }
    if (!mounted) return;

    // Step 2: Confirm payment amount (Helper receives removed, modern price breakdown)
    setState(() => _verifying = true);
    final ok = await ConfirmPaymentDialog.show(
      context: context,
      budget: budget,
      serviceCharge: charge,
      posterFee: posterFee,
      totalCost: total,
      currentWalletBalance: wallet.balance.balance,
      onConfirm: () => context.read<TaskProvider>().payHelper(widget.taskId),
    );

    if (mounted) setState(() => _verifying = false);
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment released to helper successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      await _loadTask();
      if (mounted) _showRatingDialog(rateHelper: true);
    } else if (ok == false && mounted) {
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
          content: SingleChildScrollView(
            child: Column(
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
      final requiresLiveGps = !Task.isFreelancerCategory(task.category);
      bottomBar = SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (requiresLiveGps) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDCFCE7),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.gps_fixed_rounded,
                        size: 14,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'By accepting, you agree to share your live GPS location with the Task Poster while this task is active.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _accepting ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0066FF),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: const Color(0xFF0066FF).withValues(alpha: 0.35),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: EdgeInsets.zero,
                  ),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0066FF), Color(0xFF0052CC)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      child: _accepting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline_rounded,
                                  color: Colors.white,
                                  size: 21,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Accept Task – ₹${task.budget.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
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
      backgroundColor: const Color(0xFFF8FAFC),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF).withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Color(0xFF1D4ED8),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        title: const Text(
          'Task Details',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
        actions: [
          if (canEdit)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: InkWell(
                  onTap: () async {
                    final updated = await Navigator.of(context, rootNavigator: true).push<bool>(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => EditTaskScreen(task: task),
                      ),
                    );
                    if (updated == true && mounted) _loadTask();
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF).withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_outlined,
                      color: Color(0xFF1D4ED8),
                      size: 19,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Subtle Hero Map Background at the top
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 240,
            child: IgnorePointer(
              child: CustomPaint(
                painter: HeroMapBackgroundPainter(
                  fadeBottom: true,
                  beaconTop: 45,
                  beaconRightOffset: 120,
                  beaconLeftMinFactor: 0.5,
                  mapCenterYFactor: 0.45,
                ),
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _loadTask,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Active-task warning banner (helper only) ──────────────
                    if (hasActiveTask && !isPoster && !isAssignedHelper) ...[
                      GestureDetector(
                        onTap: activeTask != null
                            ? () => context.push('/task-in-progress/${activeTask.id}')
                            : null,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.warning, Color(0xFFD97706)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.assignment_late_outlined, color: Colors.white, size: 22),
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
                                        fontSize: 13,
                                      ),
                                    ),
                                    if (activeTask != null)
                                      Text(
                                        activeTask.title,
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: Colors.white70, size: 22),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Card 1: Task Overview Card ──
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.7)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left side
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Status badge (e.g. Open)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE0EDFF),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _getStatusLabel(task.status),
                                    style: const TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                // Task Title
                                Text(
                                  task.title,
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.4,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Category badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _getCategoryIcon(task.category),
                                        size: 16,
                                        color: const Color(0xFF2563EB),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        task.category.toLowerCase(),
                                        style: const TextStyle(
                                          color: Color(0xFF2563EB),
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Subtle Vertical Divider
                          Container(
                            height: 70,
                            width: 1,
                            color: const Color(0xFFF1F5F9),
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          // Right side: Task Budget
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text(
                                'Task Budget',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '₹${task.budget.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0284C7),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Card 2: Description Card ──
                    if (!Task.isGroceryCategory(task.category)) ...[
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(top: 14),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE2E8F0).withValues(alpha: 0.7)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                              blurRadius: 18,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEFF6FF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.article_outlined,
                                    size: 20,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Description',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            // Tinted Inner Container
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFEDF2F7)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ..._buildDescriptionBullets(task.description, task.distanceKm),
                                  const SizedBox(height: 12),
                                  _buildBulletRow(
                                    RichText(
                                      text: TextSpan(
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          color: Color(0xFF64748B),
                                          height: 1.45,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text: 'Posted: ',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                          TextSpan(
                                            text: _TimelineRow.format(task.createdAt),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF0F172A),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (task.acceptedAt != null) ...[
                                    const SizedBox(height: 12),
                                    _buildBulletRow(
                                      RichText(
                                        text: TextSpan(
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            color: Color(0xFF64748B),
                                            height: 1.45,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: 'Accepted: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            TextSpan(
                                              text: _TimelineRow.format(task.acceptedAt!),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (task.completedAt != null) ...[
                                    const SizedBox(height: 12),
                                    _buildBulletRow(
                                      RichText(
                                        text: TextSpan(
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            color: Color(0xFF64748B),
                                            height: 1.45,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: 'Completed: ',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            TextSpan(
                                              text: _TimelineRow.format(task.completedAt!),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Grocery Items Card (if grocery task)
                    Builder(builder: (context) {
                      final isGrocery = Task.isGroceryCategory(task.category);
                      if (!isGrocery) return const SizedBox.shrink();
                      final groceryItems = (task.groceryItems != null && task.groceryItems!.isNotEmpty)
                          ? task.groceryItems!
                          : GroceryCatalog.parseGroceryItems(null, task.description);
                      if (groceryItems.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.shopping_basket_rounded,
                                      size: 19, color: Color(0xFF15803D)),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Grocery Items',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 19,
                                      color: Color(0xFF102A56),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF86EFAC)),
                                  ),
                                  child: Text(
                                    '${groceryItems.length} ${groceryItems.length == 1 ? 'Item' : 'Items'}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _GroceryItemsCard(items: groceryItems),
                          ],
                        ),
                      );
                    }),

                    // Helper Info (if assigned)
                    if (task.helperName != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Assigned Helper',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: Color(0xFF102A56),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _UserRow(
                              name: task.helperName!,
                              rating: task.helperRating,
                              avatarColor: AppColors.success,
                            ),
                            if (isPoster && task.helperPhone != null && task.helperPhone!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.call, size: 18),
                                      label: const Text('Call'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.success,
                                        side: const BorderSide(color: AppColors.success),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () async {
                                        final uri = Uri(scheme: 'tel', path: task.helperPhone);
                                        try {
                                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                                        } catch (_) {}
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                                      label: const Text('Chat'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF6366F1),
                                        side: const BorderSide(color: Color(0xFF6366F1)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      onPressed: () {
                                        context.push(
                                          '/chat/${task.id}',
                                          extra: {
                                            'taskId': task.id,
                                            'taskTitle': task.title,
                                            'otherName': task.helperName ?? 'Helper',
                                            'otherRole': 'Helper',
                                            'otherPhone': task.helperPhone,
                                            'category': task.category,
                                            'budget': task.budget,
                                            'status': task.status,
                                            'isPoster': true,
                                          },
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    // Completion proof (if any)
                    if (task.completionProof != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Completion Proof',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: Color(0xFF102A56),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: AspectRatio(
                                aspectRatio: 4 / 3,
                                child: Image.network(
                                  task.completionProof!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Container(
                                    color: AppColors.light,
                                    child: const Center(
                                      child: Text('Proof submitted', style: TextStyle(color: AppColors.gray)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: bottomBar,
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'open':
      case 'posted':
        return 'Open';
      case 'accepted':
        return 'Accepted';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
      case 'verify_pending':
        return 'Completed';
      case 'verified':
      case 'paid':
      case 'done':
        return 'Verified';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.isNotEmpty ? status[0].toUpperCase() + status.substring(1) : 'Open';
    }
  }

  IconData _getCategoryIcon(String category) {
    final cat = category.toLowerCase();
    if (cat.contains('laundry') || cat.contains('cloth')) return Icons.dry_cleaning_outlined;
    if (cat.contains('clean')) return Icons.cleaning_services_outlined;
    if (cat.contains('cook')) return Icons.restaurant_outlined;
    if (cat.contains('grocer') || cat.contains('shop')) return Icons.shopping_bag_outlined;
    if (cat.contains('deliver') || cat.contains('transport') || cat.contains('tempo') || cat.contains('truck')) {
      return Icons.local_shipping_outlined;
    }
    if (cat.contains('plumb')) return Icons.plumbing_outlined;
    if (cat.contains('electr')) return Icons.electrical_services_outlined;
    if (cat.contains('carpent')) return Icons.carpenter_outlined;
    if (cat.contains('paint')) return Icons.format_paint_outlined;
    if (cat.contains('garden')) return Icons.yard_outlined;
    if (cat.contains('pet')) return Icons.pets_outlined;
    if (cat.contains('tutor')) return Icons.school_outlined;
    if (cat.contains('photo') || cat.contains('video')) return Icons.camera_alt_outlined;
    if (cat.contains('move') || cat.contains('pack')) return Icons.inventory_2_outlined;
    return Icons.work_outline_rounded;
  }

  Widget _buildBulletRow(Widget content) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 6),
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF2563EB),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: content),
      ],
    );
  }

  List<Widget> _buildDescriptionBullets(String rawDescription, double? distanceKm) {
    final cleanText = rawDescription
        .replaceAll(RegExp(r'\[GROCERY_ITEMS\].*?\[/GROCERY_ITEMS\]', dotAll: true), '')
        .replaceAll(RegExp(r'\[ROUTE\].*?\[/ROUTE\]', dotAll: true), '')
        .trim();

    final lines = cleanText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final widgets = <Widget>[];

    for (final line in lines) {
      Widget content;
      final qMarkIdx = line.indexOf('?');
      if (qMarkIdx != -1 && qMarkIdx < line.length - 1) {
        final qPart = line.substring(0, qMarkIdx + 1).trim();
        final aPart = line.substring(qMarkIdx + 1).replaceFirst(RegExp(r'^[:\s]+'), '').trim();
        if (aPart.isNotEmpty) {
          content = RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.45),
              children: [
                TextSpan(text: '$qPart '),
                TextSpan(
                  text: aPart,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                ),
              ],
            ),
          );
        } else {
          content = Text(
            line,
            style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.45, fontWeight: FontWeight.w500),
          );
        }
      } else if (line.contains(':') && !line.startsWith('http')) {
        final colonIdx = line.indexOf(':');
        final kPart = line.substring(0, colonIdx).trim();
        final vPart = line.substring(colonIdx + 1).trim();
        content = RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.45),
            children: [
              TextSpan(text: '$kPart: ', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              TextSpan(
                text: vPart,
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
        );
      } else {
        content = Text(
          line.replaceFirst(RegExp(r'^[-•*→]\s*'), ''),
          style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.45, fontWeight: FontWeight.w500),
        );
      }

      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
      }
      widgets.add(_buildBulletRow(content));
    }

    if (distanceKm != null) {
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 12));
      }
      widgets.add(_buildBulletRow(
        RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), height: 1.45),
            children: [
              const TextSpan(text: 'Distance: ', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
              TextSpan(
                text: '${distanceKm.toStringAsFixed(1)} km away',
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
              ),
            ],
          ),
        ),
      ));
    }

    return widgets;
  }
}

// ── Smart grocery items card ──────────────────────────────────────────────────

class _GroceryItemsCard extends StatelessWidget {
  final List<SelectedGroceryItem> items;
  const _GroceryItemsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: items.map((item) {
        final pkg = item.package.trim();
        final qty = item.qty.trim();
        final kg = item.kg.trim();
        final gram = item.gram.trim();
        final litr = item.litr.trim();
        final brand = item.brand.trim();
        final rupee = item.rupee.trim();

        final tags = <Widget>[
          if (pkg.isNotEmpty)
            _buildTag(pkg, const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
          if (qty.isNotEmpty)
            _buildTag('Qty: $qty', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
          if (kg.isNotEmpty)
            _buildTag('$kg kg', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
          if (gram.isNotEmpty)
            _buildTag('$gram g', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
          if (litr.isNotEmpty)
            _buildTag('$litr L', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
          if (brand.isNotEmpty)
            _buildTag('Brand: $brand', const Color(0xFFFAF5FF), const Color(0xFF9333EA)),
          if (rupee.isNotEmpty)
            _buildTag('Est. ₹$rupee', const Color(0xFFFFFBEB), const Color(0xFFD97706)),
        ];

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF102A56).withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Item Thumbnail / Emoji
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: item.imageUrl.isNotEmpty
                      ? Image.network(
                          item.imageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(item.emoji, style: const TextStyle(fontSize: 28)),
                          ),
                        )
                      : Center(
                          child: Text(item.emoji, style: const TextStyle(fontSize: 28)),
                        ),
                ),
              ),
              const SizedBox(width: 14),

              // All Item Info in one full-width row card
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFF102A56),
                        height: 1.25,
                      ),
                      maxLines: 2,
                      softWrap: true,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.category.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.category.trim(),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tags,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  static Widget _buildTag(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textCol.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: textCol,
        ),
      ),
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

  static String format(DateTime d) {
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
          Text(format(time), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

