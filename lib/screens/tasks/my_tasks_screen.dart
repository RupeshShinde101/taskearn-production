import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../models/task.dart';
import '../../theme/app_theme.dart';
import '../../widgets/task_card.dart';
import '../../services/notification_service.dart';
import 'edit_task_screen.dart';

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
          final canEdit = !hasHelper &&
              (t.status == 'posted' || t.status == 'open' || t.status == 'active');

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
                          child: Center(child: Text(TaskCategory.iconFor(t.category),
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
                    // Contact buttons for helper (when helper phone available)
                    if (hasHelper && t.helperPhone != null && t.helperPhone!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.call, size: 16),
                              label: const Text('Call'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.success,
                                side: const BorderSide(color: AppColors.success),
                                minimumSize: const Size(double.infinity, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () async {
                                final uri = Uri(scheme: 'tel', path: t.helperPhone);
                                try {
                                  await launchUrl(uri,
                                      mode: LaunchMode.externalApplication);
                                } catch (_) {}
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.chat, size: 16),
                              label: const Text('WhatsApp'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF25D366),
                                side: const BorderSide(color: Color(0xFF25D366)),
                                minimumSize: const Size(double.infinity, 36),
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              onPressed: () async {
                                final phone = t.helperPhone!
                                    .replaceAll(RegExp(r'[^\d]'), '');
                                final number =
                                    phone.startsWith('91') ? phone : '91$phone';
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

                    if (canEdit || canCancel) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // Edit button (only when no helper assigned)
                          if (canEdit) ...[
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.edit_outlined, size: 16),
                                label: const Text('Edit'),
                                onPressed: () async {
                                  final updated =
                                      await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EditTaskScreen(task: t),
                                    ),
                                  );
                                  if (updated == true &&
                                      context.mounted) {
                                    context
                                        .read<TaskProvider>()
                                        .fetchMyTasks();
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  side: const BorderSide(
                                      color: AppColors.primary),
                                  minimumSize:
                                      const Size(double.infinity, 38),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                ),
                              ),
                            ),
                            if (canCancel) const SizedBox(width: 8),
                          ],
                          // Cancel button
                          if (canCancel)
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.cancel_outlined,
                                    size: 16),
                                label: Text(hasHelper
                                    ? 'Cancel'
                                    : 'Cancel Task'),
                                onPressed: () =>
                                    _confirmCancel(context, t, hasHelper),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(
                                      color: AppColors.danger),
                                  minimumSize:
                                      const Size(double.infinity, 38),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],

                    // ── Verify / Pay Now action buttons ────────────────
                    if (needsVerify) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.remove_red_eye_outlined,
                                  size: 16),
                              label: const Text('Verify'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFFF6B35),
                                side: const BorderSide(
                                    color: Color(0xFFFF6B35)),
                                minimumSize:
                                    const Size(double.infinity, 38),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                              ),
                              onPressed: () =>
                                  _showProofDialog(context, t),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.payments_outlined,
                                  size: 16),
                              label: const Text('Pay Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B35),
                                foregroundColor: Colors.white,
                                minimumSize:
                                    const Size(double.infinity, 38),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                              ),
                              onPressed: () =>
                                  _showPayNowDialog(context, t),
                            ),
                          ),
                        ],
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
    if (ok && hasHelper) {
      // Show a local notification immediately — doesn't depend on FCM round-trip
      await NotificationService.showCancellationNotification(t.title);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'Task cancelled.' : 'Failed to cancel task.'),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ));
    }
  }

  // ── Shows completion proof photo + Pay Now entry point ──────────────────
  void _showProofDialog(BuildContext context, Task t) async {
    // Show a non-dismissible loading dialog while fetching the proof image URL
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('Loading proof image…',
                    style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
    // Fetch proof images the helper uploaded for this task
    final proofs = await context.read<TaskProvider>().fetchTaskProofs(t.id);
    if (!context.mounted) return;
    // Dismiss the loading dialog before showing the proof dialog
    Navigator.of(context, rootNavigator: true).pop();
    final proofUrl = proofs.isNotEmpty ? proofs.first : null;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              color: AppColors.primary.withValues(alpha: 0.07),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.task_alt,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Completion Proof',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: const Icon(Icons.close,
                        size: 20, color: AppColors.gray),
                  ),
                ],
              ),
            ),
            // Proof image — supports both base64 data URIs and https URLs
            if (proofUrl != null && proofUrl.isNotEmpty)
              Builder(builder: (ctx) {
                if (proofUrl.startsWith('data:image')) {
                  // Strip the data:image/xxx;base64, prefix
                  final commaIdx = proofUrl.indexOf(',');
                  final b64 = commaIdx >= 0 ? proofUrl.substring(commaIdx + 1) : proofUrl;
                  try {
                    return Image.memory(
                      base64Decode(b64),
                      height: 240,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    );
                  } catch (_) {
                    return const SizedBox.shrink();
                  }
                }
                return Image.network(
                  proofUrl,
                  height: 240,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : const SizedBox(
                          height: 240,
                          child: Center(child: CircularProgressIndicator())),
                  errorBuilder: (_, __, ___) => Container(
                    height: 100,
                    color: AppColors.light,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.broken_image_outlined,
                              color: AppColors.gray, size: 36),
                          SizedBox(height: 4),
                          Text('Could not load image',
                              style: TextStyle(
                                  color: AppColors.gray, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                );
              })
            else
              Container(
                height: 100,
                color: AppColors.light,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_not_supported_outlined,
                          color: AppColors.gray, size: 36),
                      SizedBox(height: 4),
                      Text('No proof photo submitted yet.',
                          style: TextStyle(
                              color: AppColors.gray, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            // Task + helper info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (t.helperName != null)
                    Text('Submitted by: ${t.helperName}',
                        style: const TextStyle(
                            color: AppColors.gray, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(t.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            // Verified button — confirms proof is accepted; pay separately via Pay Now card button
            Padding(
              padding: const EdgeInsets.all(16),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Verified'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Wallet check + price breakdown + payment ─────────────────────────────
  void _showPayNowDialog(BuildContext context, Task t) async {
    final wallet = context.read<WalletProvider>();
    await wallet.fetchWallet();
    if (!context.mounted) return;

    final budget = t.budget;
    final charge = t.serviceCharge ?? 0;
    final total = budget + charge;

    // Insufficient balance check
    if (wallet.balance.balance < total) {
      final shortfall = total - wallet.balance.balance;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Insufficient Wallet Balance'),
          content: Text(
            'You need ₹${total.toStringAsFixed(0)} to pay for this task.\n\n'
            'Current balance: ₹${wallet.balance.balance.toStringAsFixed(0)}\n'
            'Add at least ₹${shortfall.ceil()} to continue.',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white),
              child: const Text('Add Money'),
            ),
          ],
        ),
      );
      if (go == true && context.mounted) context.push('/wallet');
      return;
    }
    if (!context.mounted) return;

    // Commission calculation (same rates as backend)
    const deliveryCategories = {'delivery', 'pickup', 'transport', 'moving'};
    final commissionRate =
        deliveryCategories.contains(t.category) ? 0.15 : 0.17;
    final helperReceives = total * (1 - commissionRate);

    bool paying = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateInner) => AlertDialog(
          title: const Text('Confirm Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will be deducted from your wallet:',
                style: TextStyle(
                    color: AppColors.gray, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              _AmountRow('Task Budget', '₹${budget.toStringAsFixed(0)}'),
              if (charge > 0)
                _AmountRow(
                    'Service Charge', '₹${charge.toStringAsFixed(0)}'),
              const Divider(height: 20),
              _AmountRow('Total Payment', '₹${total.toStringAsFixed(0)}',
                  bold: true),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Helper receives',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.success)),
                    Text('₹${helperReceives.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.success,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Wallet after: ₹${(wallet.balance.balance - total).toStringAsFixed(0)}',
                style: const TextStyle(color: AppColors.gray, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: paying ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: paying
                  ? null
                  : () async {
                      setStateInner(() => paying = true);
                      bool ok = false;
                      try {
                        ok = await context
                            .read<TaskProvider>()
                            .payHelper(t.id);
                      } catch (_) {
                        // payHelper catches all exceptions internally.
                      } finally {
                        // Always close using the dialog's own context (ctx)
                        // — the outer `context` may become unmounted when
                        // fetchMyTasks() triggers a rebuild of the screen.
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok
                                ? 'Payment released to helper!'
                                : (context
                                        .read<TaskProvider>()
                                        .error ??
                                    'Payment failed. Try again.')),
                            backgroundColor:
                                ok ? AppColors.success : AppColors.danger,
                          ),
                        );
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: paying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Pay'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _AmountRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: bold ? AppColors.dark : AppColors.gray,
                  fontWeight:
                      bold ? FontWeight.w700 : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.dark)),
        ],
      ),
    );
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
    // Filter: only show tasks completed within the last 48 h.
    // If completedAt is null (backend didn't return the field yet),
    // fall back to createdAt so the task still expires rather than staying forever.
    final now = DateTime.now();
    final visible = tasks.where((t) {
      final ref = t.completedAt ?? t.createdAt;
      return ref.add(const Duration(hours: 48)).isAfter(now);
    }).toList();

    if (visible.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 64, color: AppColors.grayLight),
            SizedBox(height: 12),
            Text('No completed tasks',
                style: TextStyle(color: AppColors.gray, fontSize: 15)),
            SizedBox(height: 6),
            Text('Completed tasks are kept for 48 hours',
                style: TextStyle(color: AppColors.grayLight, fontSize: 12)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<TaskProvider>().fetchMyTasks(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: visible.length,
        itemBuilder: (_, i) {
          final t = visible[i];
          final expiry = _expiryLabel(t.completedAt);
          final expiryClr = _expiryColor(t.completedAt);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: InkWell(
                onTap: () => onTap(t),
                borderRadius: BorderRadius.circular(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Task info ──────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Category icon
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    TaskCategory.iconFor(t.category),
                                    style: const TextStyle(fontSize: 19),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                        color: AppColors.dark,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      t.category,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.gray),
                                    ),
                                  ],
                                ),
                              ),
                              // Budget
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '₹${t.budget.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppColors.success,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.success
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'Completed',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (t.description.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              t.description,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.gray,
                                  height: 1.4),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),

                          // ── Poster info row ──────────────────────────────
                          Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 15, color: AppColors.gray),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      t.posterName.isNotEmpty
                                          ? t.posterName
                                          : 'Unknown Poster',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.dark,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (t.posterId.isNotEmpty)
                                      Text(
                                        'ID: ${t.posterId.length > 12 ? '${t.posterId.substring(0, 12)}…' : t.posterId}',
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors.grayLight,
                                            fontFamily: 'monospace'),
                                      ),
                                  ],
                                ),
                              ),
                              if (t.completedAt != null)
                                Text(
                                  _formatDate(t.completedAt!),
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.gray),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Expiry bar ─────────────────────────────────────────
                    if (expiry != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: expiryClr.withValues(alpha: 0.07),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(14),
                            bottomRight: Radius.circular(14),
                          ),
                          border: Border(
                            top: BorderSide(
                                color: expiryClr.withValues(alpha: 0.2)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.access_time_rounded,
                                size: 13, color: expiryClr),
                            const SizedBox(width: 5),
                            Text(
                              expiry,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: expiryClr,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year % 100}';

  /// Returns a human-readable expiry string based on completedAt + 48 h.
  /// Returns null if no completedAt is available.
  String? _expiryLabel(DateTime? completedAt) {
    if (completedAt == null) return 'Visible for 48 h after completion';
    final expireAt = completedAt.add(const Duration(hours: 48));
    final remaining = expireAt.difference(DateTime.now());
    if (remaining.isNegative) return null; // filtered out above, shouldn't reach
    final h = remaining.inHours;
    final m = remaining.inMinutes % 60;
    if (h >= 1) return 'Disappears in ${h}h ${m}m';
    return 'Disappears in ${remaining.inMinutes} min';
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

