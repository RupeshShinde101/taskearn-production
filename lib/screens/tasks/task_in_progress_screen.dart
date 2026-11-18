import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../models/grocery_item.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/task_released_dialog.dart';

class TaskInProgressScreen extends StatefulWidget {
  final String taskId;
  const TaskInProgressScreen({super.key, required this.taskId});

  @override
  State<TaskInProgressScreen> createState() => _TaskInProgressScreenState();
}

class _TaskInProgressScreenState extends State<TaskInProgressScreen> {
  Task? _task;
  bool _loading = true;
  bool _initialLoad = true; // show spinner only on first load; polls are silent
  bool _proofSubmitted = false; // lock Phase 1 after successful proof upload
  bool _submitting = false;  // for submit-for-verification
  bool _completing = false;  // for final mark-as-completed
  bool _abandoning = false;
  String? _proofPath;
  String? _submittedProofPath; // local path kept after submit for proof preview fallback
  Timer? _pollTimer;
  StreamSubscription<Position>? _locationSub;
  String? _prevStatus;          // tracks last-known status to detect transitions
  bool _paymentPopupShown = false; // ensure payment popup shown only once
  String? _cachedProofValue;
  Uint8List? _cachedProofBytes;

  // ── statuses treated as "cancelled" — helper should be redirected away
  static const _cancelledStatuses = {
    'cancelled', 'poster_cancelled', 'rejected', 'expired',
  };
  // ── statuses treated as "verification pending" (proof submitted, waiting poster)
  static const _verifyPendingStatuses = {
    'completed', 'verify_pending',
  };
  // ── status after poster paid (both flows: new = payment_released, legacy = paid)
  static const _paymentReleasedStatuses = {
    'payment_released', 'paid',
  };
  // ── truly finished (helper already clicked Mark as Completed)
  static const _doneStatuses = {
    'verified', 'done', 'finished',
  };

  bool get _isVerifyPending =>
      _task != null && _verifyPendingStatuses.contains(_task!.status);
  bool get _isPaymentReleased =>
      _task != null && _paymentReleasedStatuses.contains(_task!.status);
  bool get _isDone =>
      _task != null && _doneStatuses.contains(_task!.status);

  @override
  void initState() {
    super.initState();
    _load();
    _startLocationUpdates();
    // Poll for status changes every 30 s so the helper is redirected
    // automatically if the poster cancels or payment is released.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) { if (mounted) _load(); },
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (_initialLoad) setState(() { _loading = true; });
    final provider = context.read<TaskProvider>();
    var task = await provider.getTaskDetail(widget.taskId);

    // If first open and phone is still null, refresh accepted list and retry once.
    if (_initialLoad &&
        task != null &&
        (task.posterPhone == null || task.posterPhone!.trim().isEmpty)) {
      await provider.fetchMyTasks().catchError((_) {});
      if (mounted) task = await provider.getTaskDetail(widget.taskId) ?? task;
    }

    if (!mounted) return;

    _syncProofCache(task?.completionProof);

    final oldStatus = _prevStatus;
    setState(() {
      // During background polls keep the old task if the network returns null
      if (task != null) {
        _task = task;
        _prevStatus = task.status;
      }
      _loading = false;
      _initialLoad = false;
    });

    // If the poster cancelled (or task expired/rejected/not found), redirect.
    final status = _task?.status ?? '';
    if (_task == null || _cancelledStatuses.contains(status)) {
      _pollTimer?.cancel();
      _showCancelledDialog();
      return;
    }

    // When status first transitions to payment_released, show earnings popup.
    if (_paymentReleasedStatuses.contains(status) &&
        !_paymentReleasedStatuses.contains(oldStatus) &&
        !_paymentPopupShown) {
      _paymentPopupShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPaymentReceivedDialog();
      });
    }
  }

  void _syncProofCache(String? rawProof) {
    final proof = rawProof?.trim();
    if (proof == _cachedProofValue) return;
    _cachedProofValue = proof;
    _cachedProofBytes = null;

    if (proof != null && proof.startsWith('data:')) {
      final comma = proof.indexOf(',');
      if (comma != -1) {
        try {
          _cachedProofBytes = base64Decode(proof.substring(comma + 1));
        } catch (_) {
          _cachedProofBytes = null;
        }
      }
    }
  }

  // ── Payment received popup with earnings breakdown ────────────────────────
  Future<void> _showPaymentReceivedDialog() async {
    if (!mounted || _task == null) return;
    final task = _task!;
    final taskTotal = task.totalTaskValue;                       // budget + service_charge
    final commissionRate = task.commissionRate;                  // 20% across all categories
    final commissionAmt = taskTotal * commissionRate;
    final helperEarning = task.netEarning;                       // taskTotal × (1 − rate)
    final commissionPct = (commissionRate * 100).round();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        contentPadding:
            const EdgeInsets.fromLTRB(20, 16, 20, 0),
        titlePadding:
            const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.payments_outlined,
                  color: AppColors.success, size: 26),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Payment Received!',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The task poster verified your work and released your payment. Here\'s the breakdown:',
              style: TextStyle(
                  color: AppColors.gray, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 16),
            // ── Earnings breakdown card ───────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F6F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _BreakdownRow(
                    label: 'Task Total',
                    value: '₹${taskTotal.toStringAsFixed(0)}',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _BreakdownRow(
                    label: 'Platform Commission ($commissionPct%)',
                    value: '− ₹${commissionAmt.toStringAsFixed(0)}',
                    valueColor: AppColors.danger,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _BreakdownRow(
                    label: 'You Receive',
                    value: '₹${helperEarning.toStringAsFixed(0)}',
                    bold: true,
                    valueColor: AppColors.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '₹${helperEarning.toStringAsFixed(0)} will be credited to your wallet after you mark the task as completed.',
              style: const TextStyle(
                  color: AppColors.gray, fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark as Completed'),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _finalMarkComplete();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCancelledDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Task Cancelled'),
        content: const Text(
          'The task poster has cancelled this task. You have been released and any held payment will be refunded to the poster.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (mounted) context.go('/browse');
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  void _startLocationUpdates() {
    _locationSub = LocationService.getLocationStream().listen((position) async {
      if (!mounted) return;
      // Only send location updates while task is still active
      if (_task != null &&
          !_verifyPendingStatuses.contains(_task!.status) &&
          !_paymentReleasedStatuses.contains(_task!.status) &&
          !_doneStatuses.contains(_task!.status)) {
        try {
          await ApiService.post('/tracking/update-location', body: {
            'taskId': widget.taskId,
            'latitude': position.latitude,
            'longitude': position.longitude,
          });
        } catch (_) {}
      }
    });
  }

  Future<void> _openNavigationTo(double? lat, double? lng, String? query) async {
    Uri uri;
    if (lat != null && lng != null && lat != 0 && lng != 0) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=$lat,$lng'
          '&travelmode=driving');
    } else if (query != null && query.trim().isNotEmpty) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${Uri.encodeComponent(query.trim())}'
          '&travelmode=driving');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location coordinates/address not available yet')),
        );
      }
      return;
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
    }
  }

  Future<void> _openNavigation() async {
    if (_task == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1'
        '&destination=${_task!.latitude},${_task!.longitude}'
        '&travelmode=driving');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
    }
  }

  Future<void> _callPoster() async {
    final phone = _task?.posterPhone;
    if (phone == null || phone.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone number not available for this poster.')),
        );
      }
      return;
    }
    final uri = Uri.parse('tel:${phone.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open dialler.')),
      );
    }
  }

  Future<void> _whatsappPoster() async {
    final raw = _task?.posterPhone?.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw == null || raw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Phone number not available for this poster.')),
        );
      }
      return;
    }
    final full = raw.startsWith('91') ? raw : '91$raw';
    final uri = Uri.parse('https://wa.me/$full');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp.')),
      );
    }
  }

  Future<void> _pickProof() async {
    final picker = ImagePicker();
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Add Completion Proof',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(ctx);
                final f = await picker.pickImage(
                    source: ImageSource.camera, imageQuality: 70);
                if (mounted && f != null) setState(() => _proofPath = f.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(ctx);
                final f = await picker.pickImage(
                    source: ImageSource.gallery, imageQuality: 70);
                if (mounted && f != null) setState(() => _proofPath = f.path);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Step 1: Helper submits proof for verification ─────────────────────────
  Future<void> _submitForVerification() async {
    if (_proofPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add a proof photo before submitting.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final ok = await context
        .read<TaskProvider>()
        .markCompleted(widget.taskId, proofPath: _proofPath);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      setState(() {
        _proofSubmitted = true; // lock Phase 1 immediately, before network refresh
        _submittedProofPath = _proofPath; // keep local path for proof preview fallback
        _proofPath = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Proof submitted! Poster will verify and release payment.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
      // Reload to reflect new status (completed / verify_pending)
      await _load();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to submit proof'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ── Step 3: Helper confirms task after receiving payment ───────────────────
  Future<void> _finalMarkComplete() async {
    setState(() => _completing = true);
    final ok = await context
        .read<TaskProvider>()
        .finalMarkComplete(widget.taskId);
    if (!mounted) return;
    setState(() => _completing = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task completed! You can now accept a new task.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
      // Navigate to Browse so the helper can immediately find a new task.
      context.go('/browse');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to complete task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _releaseTask() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
            SizedBox(width: 8),
            Text('Release Task?', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Releasing a task without completing it may result in a 10% penalty deducted from your wallet.\n\n'
          'Releasing more than 3 tasks today will trigger an automatic 48-hour account suspension.',
          style: TextStyle(height: 1.45, color: AppColors.darkLight, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.gray, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Release Task', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Immediately stop polling timer and location stream to prevent background conflict
    _pollTimer?.cancel();
    _pollTimer = null;
    _locationSub?.cancel();
    _locationSub = null;

    setState(() => _abandoning = true);
    final provider = context.read<TaskProvider>();
    final taskTitle = _task?.title ?? 'Task #${widget.taskId}';
    final ok = await provider.abandonTask(widget.taskId);
    if (!mounted) return;
    setState(() => _abandoning = false);

    if (ok) {
      final res = provider.lastAbandonResult;
      final penalty = (res?['releasePenalty'] as num?)?.toDouble() ?? 0.0;
      final dailyCount = (res?['dailyReleaseCount'] as num?)?.toInt() ?? 0;
      final isSuspended = res?['suspended'] == true;
      final message = res?['message']?.toString();

      await TaskReleasedDialog.show(
        context: context,
        taskTitle: taskTitle,
        releasePenalty: penalty,
        dailyReleasesUsed: dailyCount,
        isSuspended: isSuspended,
        message: message,
        onHome: () {
          if (mounted) context.go('/home');
        },
      );

      if (mounted) {
        context.go('/home');
      }
    } else {
      // Re-enable polling timer and location if release failed
      _pollTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) { if (mounted) _load(); },
      );
      _startLocationUpdates();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              provider.error ?? 'Failed to release task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task In Progress')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 56, color: AppColors.grayLight),
              const SizedBox(height: 12),
              const Text('Task not found',
                  style: TextStyle(color: AppColors.gray, fontSize: 15)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final task = _task!;
    final hasPhone = task.posterPhone != null && task.posterPhone!.trim().isNotEmpty;
    final busy = _submitting || _completing || _abandoning;

    return Scaffold(
      bottomNavigationBar: _isPaymentReleased
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: GradientButton(
                  label: 'Mark as Completed',
                  loading: _completing,
                  icon: Icons.check_circle_outline,
                  onPressed: _completing ? () {} : _finalMarkComplete,
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: const Text('Task In Progress'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () {
            if (GoRouter.of(context).canPop()) {
              context.pop();
            } else {
              context.go('/my-tasks');
            }
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status header banner ─────────────────────────────────
              _buildStatusBanner(task),

              const SizedBox(height: 12),

              // ── Compact Single-Row Task Poster Card (Top) ────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                      backgroundImage: (task.posterAvatar != null &&
                              task.posterAvatar!.isNotEmpty)
                          ? NetworkImage(task.posterAvatar!)
                          : null,
                      onBackgroundImageError: (task.posterAvatar != null &&
                              task.posterAvatar!.isNotEmpty)
                          ? (_, __) {}
                          : null,
                      child: (task.posterAvatar == null ||
                              task.posterAvatar!.isEmpty)
                          ? Text(
                              (task.posterName.isNotEmpty &&
                                      task.posterName != 'Anonymous')
                                  ? task.posterName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            (task.posterName.isNotEmpty &&
                                    task.posterName != 'Anonymous')
                                ? task.posterName
                                : 'Task Poster',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Text(
                                'Task Poster',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (task.posterRating > 0) ...[
                                const Text(
                                  '  •  ',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                                const Icon(Icons.star_rounded,
                                    size: 14, color: AppColors.warning),
                                const SizedBox(width: 2),
                                Text(
                                  task.posterRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Color(0xFF475569),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Call icon button
                    Tooltip(
                      message: hasPhone ? 'Call Poster' : 'Phone not available',
                      child: InkWell(
                        onTap: _callPoster,
                        borderRadius: BorderRadius.circular(11),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: hasPhone
                                ? const Color(0xFFECFDF5)
                                : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: hasPhone
                                  ? const Color(0xFFA7F3D0)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: Icon(
                            Icons.call_rounded,
                            size: 20,
                            color: hasPhone
                                ? const Color(0xFF15803D)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Message icon button
                    Tooltip(
                      message: 'Message Poster',
                      child: InkWell(
                        onTap: () {
                          if (_task == null) return;
                          context.push(
                            '/chat/${_task!.id}',
                            extra: {
                              'taskId': _task!.id,
                              'taskTitle': _task!.title,
                              'otherName': _task!.posterName,
                              'otherRole': 'Task Poster',
                              'otherPhone': _task!.posterPhone,
                              'category': _task!.category,
                              'budget': _task!.budget,
                              'status': _task!.status,
                              'isPoster': false,
                            },
                          );
                        },
                        borderRadius: BorderRadius.circular(11),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: const Color(0xFFC7D2FE)),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_rounded,
                            size: 19,
                            color: Color(0xFF4F46E5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Navigate to Location (only while actively working) ───
              if (!_isVerifyPending && !_isDone)
                Builder(builder: (context) {
                  final isGrocery = Task.isGroceryCategory(task.category);
                  final pickupAddr = GroceryCatalog.unescapeHtml(
                    task.effectivePickupAddress.isNotEmpty
                        ? task.effectivePickupAddress
                        : (task.address ??
                            (isGrocery ? 'Store location' : 'Pickup location')),
                  );
                  final dropAddr = GroceryCatalog.unescapeHtml(
                    task.effectiveDropAddress ??
                        (isGrocery
                            ? 'Delivery location specified by poster'
                            : 'Drop location specified by poster'),
                  );
                  final accentStore =
                      isGrocery ? const Color(0xFF15803D) : AppColors.primary;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
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
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: isGrocery
                                    ? const Color(0xFFDCFCE7)
                                    : AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                task.isDeliveryCategory
                                    ? Icons.alt_route_rounded
                                    : Icons.location_on_rounded,
                                size: 19,
                                color: accentStore,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isGrocery
                                    ? 'Store & Delivery Locations'
                                    : (task.isDeliveryCategory
                                        ? 'Pickup & Drop Locations'
                                        : 'Task Location'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (task.isDeliveryCategory) ...[
                          // ── Box 1: Store / Pickup Location ───────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isGrocery
                                  ? const Color(0xFFF0FDF4)
                                  : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isGrocery
                                    ? const Color(0xFFBBF7D0)
                                    : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: accentStore,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                        isGrocery
                                            ? Icons.storefront_rounded
                                            : Icons.my_location_rounded,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isGrocery
                                                ? 'STEP 1 • STORE LOCATION'
                                                : 'STEP 1 • PICKUP LOCATION',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                              letterSpacing: 0.6,
                                              color: accentStore,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            pickupAddr,
                                            style: const TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              height: 1.38,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openNavigationTo(
                                      task.latitude,
                                      task.longitude,
                                      pickupAddr,
                                    ),
                                    icon: const Icon(Icons.directions_rounded,
                                        size: 19),
                                    label: Text(
                                      isGrocery
                                          ? 'Navigate to Store Location'
                                          : 'Navigate to Pickup Location',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: accentStore,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Route connector arrow
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Center(
                              child: Icon(
                                Icons.south_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),

                          // ── Box 2: Delivery / Drop Location ──────────
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFFECACA),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Icon(
                                        isGrocery
                                            ? Icons.home_rounded
                                            : Icons.location_on_rounded,
                                        color: Colors.white,
                                        size: 17,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            isGrocery
                                                ? 'STEP 2 • DELIVERY LOCATION'
                                                : 'STEP 2 • DROP LOCATION',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 11,
                                              letterSpacing: 0.6,
                                              color: Color(0xFFDC2626),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            dropAddr,
                                            style: const TextStyle(
                                              color: Color(0xFF0F172A),
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              height: 1.38,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  height: 46,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _openNavigationTo(
                                      task.dropLatitude,
                                      task.dropLongitude,
                                      task.effectiveDropAddress != null
                                          ? GroceryCatalog.unescapeHtml(
                                              task.effectiveDropAddress!)
                                          : null,
                                    ),
                                    icon: const Icon(Icons.directions_rounded,
                                        size: 19),
                                    label: Text(
                                      isGrocery
                                          ? 'Navigate to Delivery Location'
                                          : 'Navigate to Drop Location',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFDC2626),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (Task.isFreelancerCategory(task.category) ||
                            (task.latitude == 0 && task.longitude == 0)) ...[
                          const Row(
                            children: [
                              Icon(Icons.public_rounded,
                                  color: AppColors.primary, size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Remote / Online Service — No physical location needed',
                                  style: TextStyle(
                                      color: AppColors.gray,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                      height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          if (task.address != null && task.address!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                GroceryCatalog.unescapeHtml(task.address!),
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: ElevatedButton.icon(
                              onPressed: _openNavigation,
                              icon:
                                  const Icon(Icons.directions_rounded, size: 19),
                              label: const Text(
                                'Navigate to Task Location',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                }),

              if (!_isVerifyPending && !_isDone) const SizedBox(height: 12),

              // ── Grocery Items List (replaces Task Details for grocery tasks) ─
              if (Task.isGroceryCategory(task.category))
                Builder(builder: (context) {
                  final groceryItems = (task.groceryItems != null && task.groceryItems!.isNotEmpty)
                      ? task.groceryItems!
                      : GroceryCatalog.parseGroceryItems(null, task.description);
                  if (groceryItems.isEmpty) return const SizedBox.shrink();
                  return Column(
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
                      _InProgressGroceryItemsList(items: groceryItems),
                    ],
                  );
                })
              else
                // ── Task Details (non-grocery tasks) ─────────────────────
                _SectionCard(
                  title: 'Task Details',
                  icon: Icons.description_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DetailRow('Category', task.category),
                      const Divider(height: 14),
                      _DetailRow(
                          'Earning', '₹${task.budget.toStringAsFixed(0)}'),
                      const Divider(height: 14),
                      _DetailRow('Status', task.statusLabel),
                      const Divider(height: 14),
                      const Text('Description',
                          style: TextStyle(
                              color: AppColors.gray, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        task.description,
                        style: const TextStyle(
                            color: AppColors.dark,
                            fontSize: 13,
                            height: 1.5),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // ═══════════════════════════════════════════════════════════
              // PHASE-BASED ACTION AREA
              // ═══════════════════════════════════════════════════════════

              // ── Phase 3: Payment released → Helper clicks Mark Completed
              if (_isPaymentReleased) ...[
                _buildPaymentReleasedBanner(),
                const SizedBox(height: 16),
                GradientButton(
                  label: 'Mark as Completed',
                  loading: _completing,
                  onPressed: busy ? () {} : _finalMarkComplete,
                  icon: Icons.check_circle_outline,
                ),
              ]

              // ── Phase 2: Waiting for poster to verify ─────────────────
              else if (_isVerifyPending || _proofSubmitted) ...[
                _buildWaitingBanner(task),
              ]

              // ── Phase 1: Actively working → Upload proof & submit ─────
              else if (!_isDone && !_proofSubmitted) ...[
                // Proof upload section
                const Text('Completion Proof',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.dark)),
                const SizedBox(height: 4),
                const Text(
                  'Upload a photo as proof of work. The poster will verify it and release your payment.',
                  style: TextStyle(
                      color: AppColors.gray, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 10),

                // Proof preview (4:3 ratio, uncropped)
                if (_proofPath != null) ...[
                  _buildProofFrame(
                    child: _proofPath!.startsWith('http')
                        ? Image.network(
                            _proofPath!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => _proofErrorWidget(),
                          )
                        : Image.file(
                            File(_proofPath!),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => _proofErrorWidget(),
                          ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Add / change photo button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _pickProof,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(
                        _proofPath == null ? 'Add Proof Photo' : 'Change Photo'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Submit for verification
                GradientButton(
                  label: 'Submit for Verification',
                  loading: _submitting,
                  onPressed: busy ? () {} : _submitForVerification,
                  icon: Icons.verified_outlined,
                ),
                const SizedBox(height: 10),

                // Release task
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _releaseTask,
                    icon: _abandoning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.danger),
                          )
                        : const Icon(Icons.exit_to_app_outlined, size: 18),
                    label: const Text('Release Task'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Builds the top status banner ─────────────────────────────────────────
  Widget _buildStatusBanner(Task task) {
    final IconData icon;
    final String label;
    final List<Color> colors;

    if (_isDone) {
      icon = Icons.check_circle;
      label = 'Task Completed';
      colors = [AppColors.success, const Color(0xFF059669)];
    } else if (_isPaymentReleased) {
      icon = Icons.payments_outlined;
      label = 'Payment Released – Please Mark Completed';
      colors = [AppColors.success, const Color(0xFF059669)];
    } else if (_isVerifyPending) {
      icon = Icons.hourglass_top_rounded;
      label = 'Proof Submitted – Awaiting Poster Verification';
      colors = [AppColors.warning, const Color(0xFFD97706)];
    } else {
      icon = Icons.flash_on;
      label = 'Task Active';
      colors = AppColors.gradient;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                Text(
                  task.title,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
    );
  }

  // ── Banner shown while waiting for poster to verify ───────────────────────
  Widget _buildWaitingBanner(Task task) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_empty_rounded,
                    color: AppColors.warning, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Waiting for Verification',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.dark),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Your proof has been submitted. The poster will review it and release your payment.',
                      style: TextStyle(
                          color: AppColors.gray,
                          fontSize: 12,
                          height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (task.completionProof != null &&
              task.completionProof!.isNotEmpty) ...[  // proof stored as base64 data URI or URL
            const SizedBox(height: 12),
            _buildProofFrame(
              child: _buildProofImage(task.completionProof!),
            ),
            const SizedBox(height: 6),
            const Text('Submitted proof photo',
                style:
                    TextStyle(color: AppColors.gray, fontSize: 11)),
          ] else if (_submittedProofPath != null) ...[
            const SizedBox(height: 12),
            _buildProofFrame(
              child: Image.file(
                File(_submittedProofPath!),
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => _proofErrorWidget(),
              ),
            ),
            const SizedBox(height: 6),
            const Text('Submitted proof photo',
                style:
                    TextStyle(color: AppColors.gray, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  // ── Banner shown when payment has been released ───────────────────────────
  Widget _buildPaymentReleasedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.payments_outlined,
                color: AppColors.success, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Payment Released!',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.success),
                ),
                SizedBox(height: 2),
                Text(
                  'Your payment has been released. Click "Mark as Completed" to finish the task.',
                  style: TextStyle(
                      color: AppColors.gray, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Wraps proof photos in a fixed 4:3 frame without cropping the image.
  Widget _buildProofFrame({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: child,
      ),
    );
  }

  /// Renders a proof image from either an HTTPS URL or a base64 data URI.
  Widget _buildProofImage(String proof) {
    final trimmed = proof.trim();
    if (trimmed.startsWith('data:')) {
      if (_cachedProofValue != trimmed) {
        _syncProofCache(trimmed);
      }
      if (_cachedProofBytes != null) {
        return Image.memory(_cachedProofBytes!,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => _proofErrorWidget());
      }
      return _proofErrorWidget();
    }
    return Image.network(trimmed,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _proofErrorWidget());
  }

  Widget _proofErrorWidget() => Container(
        color: AppColors.light,
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined,
              size: 40, color: AppColors.grayLight),
        ),
      );
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  const _BreakdownRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: bold ? AppColors.dark : AppColors.gray,
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? (bold ? AppColors.dark : AppColors.gray),
            fontSize: 13,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 19, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17.5,
                      color: Color(0xFF102A56),
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _InProgressGroceryItemsList extends StatelessWidget {
  final List<SelectedGroceryItem> items;
  const _InProgressGroceryItemsList({required this.items});

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
          if (pkg.isNotEmpty) _tag(pkg, const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
          if (qty.isNotEmpty) _tag('Qty: $qty', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
          if (kg.isNotEmpty) _tag('$kg kg', const Color(0xFFF0FDF4), const Color(0xFF16A34A)),
          if (gram.isNotEmpty) _tag('$gram g', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
          if (litr.isNotEmpty) _tag('$litr L', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
          if (brand.isNotEmpty) _tag('Brand: $brand', const Color(0xFFFAF5FF), const Color(0xFF9333EA)),
          if (rupee.isNotEmpty) _tag('Est. ₹$rupee', const Color(0xFFFFFBEB), const Color(0xFFD97706)),
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
                      Wrap(spacing: 6, runSpacing: 6, children: tags),
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

  static Widget _tag(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textCol.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: textCol),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.gray, fontSize: 13)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.dark,
                fontSize: 13),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}
