import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/task.dart';
import '../../models/grocery_item.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/confirm_payment_dialog.dart';
import '../../widgets/profile_mode_switch_dialog.dart';
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
            label: 'Accept Task – ₹${task.budget.toStringAsFixed(0)}',
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
                final updated = await Navigator.of(context, rootNavigator: true).push<bool>(
                  MaterialPageRoute(
                    fullscreenDialog: true,
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
                        'Task Budget',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.gray,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text('₹${task.budget.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),

              const Divider(height: 28),

              // Description
              const Text('Description',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 10),
              _DescriptionCard(text: task.description),

              if (task.groceryItems != null && task.groceryItems!.isNotEmpty) ...[
                const Divider(height: 28),
                Row(
                  children: [
                    const Text('Grocery Items',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF86EFAC)),
                      ),
                      child: Text(
                        '${task.groceryItems!.length} items',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF166534),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _GroceryItemsCard(items: task.groceryItems!),
              ],

              const Divider(height: 28),

              // Location
              const Text('Location',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              // Delivery tasks: show pickup + drop clearly separated with dedicated cards
              if (task.isDeliveryCategory) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      // Pickup Location
                      Builder(builder: (context) {
                        final isGrocery = Task.isGroceryCategory(task.category);
                        final pickupTitle = isGrocery ? 'Store / Supermarket Location' : 'Pickup Location';
                        final pickupIcon = isGrocery ? Icons.storefront_rounded : Icons.radio_button_checked;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(pickupIcon,
                                  color: AppColors.primary, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(pickupTitle,
                                      style: const TextStyle(
                                          color: AppColors.gray,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(
                                    task.effectivePickupAddress.isNotEmpty
                                        ? task.effectivePickupAddress
                                        : (task.address ?? 'Pickup location specified by poster'),
                                    style: const TextStyle(
                                        color: AppColors.dark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Divider(height: 1),
                      ),
                      // Drop / Destination Location
                      Builder(builder: (context) {
                        final isGrocery = Task.isGroceryCategory(task.category);
                        final dropTitle = isGrocery ? 'Delivery Location' : 'Drop / Destination Location';
                        final dropIcon = isGrocery ? Icons.home_rounded : Icons.location_on;
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(dropIcon,
                                  color: AppColors.danger, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(dropTitle,
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                    task.effectiveDropAddress ?? 'Drop location specified by poster',
                                    style: const TextStyle(
                                        color: AppColors.dark,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ] else
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        (task.address != null && task.address!.trim().isNotEmpty)
                            ? task.address!
                            : ((Task.isFreelancerCategory(task.category) ||
                                    (task.latitude == 0 && task.longitude == 0))
                                ? 'Remote / Online'
                                : '${task.latitude}, ${task.longitude}'),
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
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                          label: const Text('Chat'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6366F1),
                            side: const BorderSide(color: Color(0xFF6366F1)),
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

// ── Smart grocery items card ──────────────────────────────────────────────────

class _GroceryItemsCard extends StatelessWidget {
  final List<SelectedGroceryItem> items;
  const _GroceryItemsCard({required this.items});

  @override
  Widget build(BuildContext context) {
    double totalEstCost = 0;
    for (final item in items) {
      final r = double.tryParse(item.rupee.trim());
      if (r != null) {
        final q = double.tryParse(item.qty.trim()) ?? 1.0;
        totalEstCost += r * (q > 0 ? q : 1.0);
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A56).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Items list - 1 item card per row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: items.map((item) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5EDF7)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item Image / emoji with rounded card
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: item.imageUrl.isNotEmpty
                              ? Image.network(
                                  item.imageUrl,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
                                  ),
                                )
                              : Center(
                                  child: Text(item.emoji, style: const TextStyle(fontSize: 24)),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Name, Category, and Details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: Color(0xFF102A56),
                              ),
                              maxLines: 2,
                              softWrap: true,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.category,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // Requirements Chips (Package, QTY, kg, gram, litr, rupee, brand)
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (item.package.trim().isNotEmpty)
                                  _buildTag(item.package.trim(), const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
                                if (item.package.trim().isEmpty && item.qty.trim().isNotEmpty)
                                  _buildTag('Qty: ${item.qty.trim()}', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
                                if (item.package.trim().isEmpty && item.kg.trim().isNotEmpty)
                                  _buildTag('${item.kg.trim()} kg', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
                                if (item.package.trim().isEmpty && item.gram.trim().isNotEmpty)
                                  _buildTag('${item.gram.trim()} g', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
                                if (item.package.trim().isEmpty && item.litr.trim().isNotEmpty)
                                  _buildTag('${item.litr.trim()} L', const Color(0xFFEFF6FF), const Color(0xFF0284C7)),
                                if (item.brand.trim().isNotEmpty)
                                  _buildTag('Brand: ${item.brand.trim()}', const Color(0xFFFAF5FF), const Color(0xFF9333EA)),
                                if (item.rupee.trim().isNotEmpty)
                                  _buildTag('₹${item.rupee.trim()}', const Color(0xFFFFFBEB), const Color(0xFFD97706)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Total cost banner if estimated
          if (totalEstCost > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF0FDF4),
                border: Border(top: BorderSide(color: Color(0xFFDCFCE7))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Estimated Items Total:',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF15803D),
                    ),
                  ),
                  Text(
                    '₹${totalEstCost.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ),

          // Policy notice
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF64748B)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Grocery item cost is paid separately by poster directly to helper/store.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildTag(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textCol.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textCol,
        ),
      ),
    );
  }
}

// ── Smart description card ───────────────────────────────────────────────────

class _DescriptionCard extends StatelessWidget {
  final String text;
  const _DescriptionCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cleanText = text.replaceAll(RegExp(r'\[GROCERY_ITEMS\].*?\[/GROCERY_ITEMS\]', dotAll: true), '').trim();
    final lines = cleanText.split('\n').map((l) => l.trim()).toList();
    final widgets = <Widget>[];
    int i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.isEmpty) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 6));
        i++; continue;
      }
      // Q: pattern
      final qm = RegExp(r'^[Qq](uestion)?[:.] *(.+)').firstMatch(line);
      if (qm != null) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 14));
        widgets.add(_DRow(badge: 'Q', color: AppColors.primary, text: qm.group(2)!.trim(), bold: true));
        if (i + 1 < lines.length) {
          final am = RegExp(r'^[Aa](nswer)?[:.] *(.+)').firstMatch(lines[i + 1].trim());
          if (am != null) {
            widgets.add(const SizedBox(height: 6));
            widgets.add(Padding(
              padding: const EdgeInsets.only(left: 28),
              child: _DRow(badge: 'A', color: AppColors.success, text: am.group(2)!.trim(), bold: false),
            ));
            i += 2; continue;
          }
        }
        i++; continue;
      }
      // A: standalone
      final am = RegExp(r'^[Aa](nswer)?[:.] *(.+)').firstMatch(line);
      if (am != null) {
        widgets.add(const SizedBox(height: 6));
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 28),
          child: _DRow(badge: 'A', color: AppColors.success, text: am.group(2)!.trim(), bold: false),
        ));
        i++; continue;
      }
      // Bullet
      if (RegExp(r'^[-•*→] +').hasMatch(line)) {
        widgets.add(const SizedBox(height: 4));
        widgets.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 5), child: Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))),
            const SizedBox(width: 8),
            Expanded(child: Text(line.replaceFirst(RegExp(r'^[-•*→] +'), ''), style: const TextStyle(color: Color(0xFF374151), fontSize: 13.5, height: 1.6))),
          ],
        ));
        i++; continue;
      }
      // Key: Value
      final kv = RegExp(r'^([A-Za-z][A-Za-z /]{0,28}): +(.+)$').firstMatch(line);
      if (kv != null) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 7));
        widgets.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${kv.group(1)!}:', style: const TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(width: 5),
            Expanded(child: Text(kv.group(2)!, style: const TextStyle(color: Color(0xFF4B5563), fontSize: 13, height: 1.55))),
          ],
        ));
        i++; continue;
      }
      widgets.add(Text(line, style: const TextStyle(color: Color(0xFF374151), fontSize: 13.5, height: 1.65)));
      i++;
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets),
    );
  }
}

class _DRow extends StatelessWidget {
  final String badge, text;
  final Color color;
  final bool bold;
  const _DRow({required this.badge, required this.color, required this.text, required this.bold});
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(5)), child: Text(badge, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800))),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(color: bold ? const Color(0xFF111827) : const Color(0xFF4B5563), fontSize: 13.5, fontWeight: bold ? FontWeight.w600 : FontWeight.w400, height: 1.55))),
    ],
  );
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
      case 'done':
      case 'paid':
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
      case 'done':
      case 'paid':
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

