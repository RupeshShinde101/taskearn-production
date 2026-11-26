import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'proof_camera_screen.dart';
import '../../providers/task_provider.dart';
import '../../models/task.dart';
import '../../models/grocery_item.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/task_released_dialog.dart';

class TaskInProgressScreen extends StatefulWidget {
  final String taskId;
  const TaskInProgressScreen({super.key, required this.taskId});

  @override
  State<TaskInProgressScreen> createState() => _TaskInProgressScreenState();
}

class _TaskInProgressScreenState extends State<TaskInProgressScreen>
    with WidgetsBindingObserver {
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
  Timer? _gpsHeartbeatTimer;
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<Map<String, dynamic>>? _cancelSub;
  bool _cancelledDialogShown = false;
  String? _prevStatus;          // tracks last-known status to detect transitions
  bool _paymentPopupShown = false; // ensure payment popup shown only once
  String? _cachedProofValue;
  Uint8List? _cachedProofBytes;
  final Set<int> _pickedItemIndices = {}; // tracks checked-off grocery items

  // ── statuses treated as "cancelled" — helper should be redirected away
  static const _cancelledStatuses = {
    'cancelled', 'poster_cancelled', 'rejected', 'expired', 'deleted', 'removed',
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

  bool _locationUpdatesStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Listen for real-time task cancellation notification
    _cancelSub = NotificationService.onTaskCancelled.stream.listen((data) {
      final cancelTaskId = data['task_id']?.toString() ?? '';
      if (cancelTaskId.isEmpty || cancelTaskId == widget.taskId) {
        final body = data['body']?.toString();
        _showCancelledDialog(body);
      }
    });
    _load();
    // Poll for status changes every 4 s so the helper is redirected
    // automatically if the poster cancels or payment is released.
    _pollTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) { if (mounted) _load(); },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Push an immediate fresh GPS fix whenever helper returns from Google Maps / background.
    if (state == AppLifecycleState.resumed &&
        _task != null &&
        !Task.isFreelancerCategory(_task!.category)) {
      _sendFreshGpsFix();
    }
  }

  Future<void> _load() async {
    if (!mounted || _cancelledDialogShown) return;
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

    if (!mounted || _cancelledDialogShown) return;

    // If the poster cancelled (or task expired/rejected/not found), redirect immediately.
    final currentTask = task;
    if (currentTask == null || _cancelledStatuses.contains(currentTask.status)) {
      _pollTimer?.cancel();
      _showCancelledDialog();
      return;
    }

    _syncProofCache(currentTask.completionProof);

    final oldStatus = _prevStatus;
    setState(() {
      _task = currentTask;
      _prevStatus = currentTask.status;
      _loading = false;
      _initialLoad = false;
    });

    final status = currentTask.status;

    // Start live GPS sharing once task is loaded (non-Professional categories only).
    if (!_locationUpdatesStarted &&
        _task != null &&
        !Task.isFreelancerCategory(_task!.category)) {
      _locationUpdatesStarted = true;
      _startLocationUpdates();
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
    final commissionRate = task.commissionRate;                  // 12% across all categories
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
                    label: 'Platform Fee ($commissionPct%)',
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

  Future<void> _showCancelledDialog([String? customMessage]) async {
    if (!mounted || _cancelledDialogShown) return;
    _cancelledDialogShown = true;
    _pollTimer?.cancel();
    _gpsHeartbeatTimer?.cancel();
    _locationSub?.cancel();

    try {
      context.read<TaskProvider>().clearTaskFromCache(widget.taskId);
    } catch (_) {}

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        title: const Row(
          children: [
            Icon(Icons.cancel_outlined, color: AppColors.danger, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Poster Cancelled Task',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          customMessage ??
              'The task poster has cancelled this task. You have been released and can accept new tasks.',
          style: const TextStyle(fontSize: 14, color: AppColors.dark, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (mounted) context.go('/home');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelSub?.cancel();
    _pollTimer?.cancel();
    _gpsHeartbeatTimer?.cancel();
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _pushHelperLatLng(
    double lat,
    double lng, {
    double? accuracy,
    double? heading,
    double? speed,
  }) async {
    if (!mounted) return;
    // Professional / Freelancer tasks are remote work-from-home tasks and
    // are strictly exempt from live GPS tracking.
    if (_task == null || Task.isFreelancerCategory(_task!.category)) {
      return;
    }
    if (_verifyPendingStatuses.contains(_task!.status) ||
        _paymentReleasedStatuses.contains(_task!.status) ||
        _doneStatuses.contains(_task!.status)) {
      return;
    }
    try {
      await ApiService.post('/tracking/update-location', body: {
        'taskId': int.tryParse(widget.taskId) ?? widget.taskId,
        'location': {
          'lat': lat,
          'lng': lng,
          if (accuracy != null) 'accuracy': accuracy,
          if (heading != null) 'heading': heading,
          if (speed != null) 'speed': speed,
        },
      });
    } catch (_) {}
  }

  Future<void> _sendFreshGpsFix() async {
    final pos = await LocationService.getAccuratePosition();
    if (pos != null) {
      await _pushHelperLatLng(
        pos.latitude,
        pos.longitude,
        accuracy: pos.accuracy,
        heading: pos.heading,
        speed: pos.speed,
      );
    }
  }

  void _startLocationUpdates() {
    // Immediate fresh GPS fix + 10-second heartbeat so poster always gets accurate GPS
    // even when helper is stationary at store/doorstep.
    _sendFreshGpsFix();
    _gpsHeartbeatTimer?.cancel();
    _gpsHeartbeatTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) {
        if (mounted) _sendFreshGpsFix();
      },
    );

    _locationSub = LocationService.getLocationStream().listen((position) async {
      await _pushHelperLatLng(
        position.latitude,
        position.longitude,
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
      );
    });
  }

  Future<void> _openNavigationTo(double? lat, double? lng, String? query, {bool isStorePickup = false}) async {
    Uri uri;
    final cleanQuery = query?.trim() ?? '';
    final hasValidQuery = cleanQuery.isNotEmpty &&
        cleanQuery != 'Store location' &&
        cleanQuery != 'Pickup location' &&
        cleanQuery != 'Delivery Location' &&
        cleanQuery != 'Local Area' &&
        cleanQuery != 'Selected Store';

    // If pickup coordinates mistakenly match drop coordinates (e.g. poster's home),
    // they are invalid for the store -> must use store address query!
    final bool coordsMatchDrop = _task != null &&
        _task!.dropLatitude != null &&
        _task!.dropLongitude != null &&
        lat != null &&
        lng != null &&
        (lat - _task!.dropLatitude!).abs() < 0.001 &&
        (lng - _task!.dropLongitude!).abs() < 0.001;

    if (coordsMatchDrop && hasValidQuery) {
      // Coords corrupted/identical to drop location -> navigate strictly to store address!
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${Uri.encodeComponent(cleanQuery)}'
          '&travelmode=driving');
    } else if (isStorePickup && hasValidQuery) {
      // For grocery/store pickup: navigating by store name & address directs helper
      // directly to the named shop/supermarket on Google Maps instead of a residential house.
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${Uri.encodeComponent(cleanQuery)}'
          '&travelmode=driving');
    } else if (lat != null && lng != null && lat != 0 && lng != 0 && !coordsMatchDrop) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=$lat,$lng'
          '&travelmode=driving');
    } else if (hasValidQuery) {
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${Uri.encodeComponent(cleanQuery)}'
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
    final cleanAddr = _task!.address?.trim() ?? '';
    final hasValidAddr = cleanAddr.isNotEmpty &&
        cleanAddr != 'Local Area' &&
        cleanAddr != 'Task Location';

    final uri = (hasValidAddr)
        ? Uri.parse(
            'https://www.google.com/maps/dir/?api=1'
            '&destination=${Uri.encodeComponent(cleanAddr)}'
            '&travelmode=driving')
        : Uri.parse(
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

  Future<void> _pickProof() async {
    final capturedPath =
        await Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => const ProofCameraScreen()),
    );
    if (mounted && capturedPath != null && capturedPath.isNotEmpty) {
      setState(() => _proofPath = capturedPath);
    }
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

    final isActivePhase =
        !_isPaymentReleased && !_isVerifyPending && !_proofSubmitted && !_isDone;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      bottomNavigationBar: _isPaymentReleased
          ? Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(
                  top: BorderSide(color: Color(0xFFE2E8F0)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: GradientButton(
                    label: 'Mark as Completed',
                    loading: _completing,
                    icon: Icons.check_circle_outline,
                    onPressed: _completing ? () {} : _finalMarkComplete,
                  ),
                ),
              ),
            )
          : isActivePhase
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: const Border(
                      top: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 12,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: busy ? null : _submitForVerification,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.verified_outlined,
                                      size: 19),
                              label: const Text(
                                'Submit for Verification',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.1,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B43E6),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: busy ? null : _releaseTask,
                              icon: _abandoning
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFFDC2626),
                                      ),
                                    )
                                  : const Icon(Icons.exit_to_app_outlined,
                                      size: 18),
                              label: const Text(
                                'Release Task',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFDC2626),
                                side: const BorderSide(
                                    color: Color(0xFFFCA5A5), width: 1.3),
                                backgroundColor: const Color(0xFFFEF2F2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : null,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        ),
        title: const Text(
          'Task In Progress',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: Color(0xFF0F172A),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF0F172A), size: 20),
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
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF0F172A)),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Completed status banner (only shown when truly done) ──
              if (_isDone) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: Color(0xFF15803D), size: 22),
                      SizedBox(width: 10),
                      Text(
                        'Task Completed',
                        style: TextStyle(
                          color: Color(0xFF166534),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Enlarged Single-Row Task Poster Card (Top) ───────────
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.05),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFC7D2FE),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFF5B4BDB),
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
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 20,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
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
                              fontSize: 17.5,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Text(
                                'Task Poster',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (task.posterRating > 0) ...[
                                const Text(
                                  '  •  ',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 13,
                                  ),
                                ),
                                const Icon(Icons.star_rounded,
                                    size: 16, color: AppColors.warning),
                                const SizedBox(width: 2),
                                Text(
                                  task.posterRating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Color(0xFF334155),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Improved Call icon button
                    Tooltip(
                      message: hasPhone ? 'Call Poster' : 'Phone not available',
                      child: Material(
                        color: hasPhone
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(14),
                        elevation: hasPhone ? 2 : 0,
                        shadowColor:
                            const Color(0xFF16A34A).withValues(alpha: 0.35),
                        child: InkWell(
                          onTap: _callPoster,
                          borderRadius: BorderRadius.circular(14),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.phone_in_talk_rounded,
                              size: 23,
                              color: hasPhone
                                  ? Colors.white
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Improved Message icon button
                    Tooltip(
                      message: 'Message Poster',
                      child: Material(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(14),
                        elevation: 2,
                        shadowColor:
                            const Color(0xFF4F46E5).withValues(alpha: 0.35),
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
                          borderRadius: BorderRadius.circular(14),
                          child: const SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.forum_rounded,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Concept A Connected Route Timeline Card ──────────────
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

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: task.isDeliveryCategory
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // STEP 1 • STORE / PICKUP
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: isGrocery
                                          ? const Color(0xFFDCFCE7)
                                          : const Color(0xFFE0E7FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isGrocery
                                          ? Icons.storefront_rounded
                                          : Icons.my_location_rounded,
                                      size: 18,
                                      color: isGrocery
                                          ? const Color(0xFF15803D)
                                          : AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isGrocery
                                              ? 'STEP 1 • STORE'
                                              : 'STEP 1 • PICKUP',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          pickupAddr,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                            height: 1.3,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _NavigatePillButton(
                                    bgColor: isGrocery
                                        ? const Color(0xFFDCFCE7)
                                        : const Color(0xFFE0E7FF),
                                    fgColor: isGrocery
                                        ? const Color(0xFF15803D)
                                        : AppColors.primary,
                                    onTap: () => _openNavigationTo(
                                      task.latitude,
                                      task.longitude,
                                      pickupAddr,
                                      isStorePickup: isGrocery,
                                    ),
                                  ),
                                ],
                              ),

                              // Vertical dotted connector + divider
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  children: [
                                    const SizedBox(
                                      width: 34,
                                      child: Center(
                                        child: _DottedVerticalConnector(),
                                      ),
                                    ),
                                    const SizedBox(width: 11),
                                    const Expanded(
                                      child: Divider(
                                        height: 1,
                                        color: Color(0xFFF1F5F9),
                                        thickness: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // STEP 2 • DELIVERY / DROP
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFEE2E2),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isGrocery
                                          ? Icons.location_on_rounded
                                          : Icons.flag_rounded,
                                      size: 18,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isGrocery
                                              ? 'STEP 2 • DELIVERY'
                                              : 'STEP 2 • DROP',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dropAddr,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                            height: 1.3,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _NavigatePillButton(
                                    bgColor: const Color(0xFFFEE2E2),
                                    fgColor: const Color(0xFFDC2626),
                                    onTap: () => _openNavigationTo(
                                      task.dropLatitude,
                                      task.dropLongitude,
                                      task.effectiveDropAddress != null
                                          ? GroceryCatalog.unescapeHtml(
                                              task.effectiveDropAddress!)
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : (Task.isFreelancerCategory(task.category) ||
                                (task.latitude == 0 && task.longitude == 0))
                            ? const Row(
                                children: [
                                  Icon(Icons.public_rounded,
                                      color: AppColors.primary, size: 19),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Remote / Online Service — No physical location needed',
                                      style: TextStyle(
                                        color: Color(0xFF475569),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE0E7FF),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      size: 18,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'TASK LOCATION',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.6,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          (task.address != null &&
                                                  task.address!.isNotEmpty)
                                              ? GroceryCatalog.unescapeHtml(
                                                  task.address!)
                                              : 'Pinned task location',
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                            height: 1.3,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _NavigatePillButton(
                                    bgColor: const Color(0xFFE0E7FF),
                                    fgColor: AppColors.primary,
                                    onTap: _openNavigation,
                                  ),
                                ],
                              ),
                  );
                }),

              if (!_isVerifyPending && !_isDone) const SizedBox(height: 12),

              // ── Concept A Interactive Grocery Items Card ─────────────
              if (Task.isGroceryCategory(task.category))
                Builder(builder: (context) {
                  final groceryItems = (task.groceryItems != null &&
                          task.groceryItems!.isNotEmpty)
                      ? task.groceryItems!
                      : GroceryCatalog.parseGroceryItems(
                          null, task.description);
                  if (groceryItems.isEmpty) return const SizedBox.shrink();
                  final pickedCount = _pickedItemIndices
                      .where((i) => i >= 0 && i < groceryItems.length)
                      .length;
                  final allPicked = pickedCount == groceryItems.length;

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shopping_bag_outlined,
                                size: 20, color: Color(0xFF0F172A)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Grocery Items',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: allPicked
                                    ? const Color(0xFFDCFCE7)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '$pickedCount/${groceryItems.length} Picked',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: allPicked
                                      ? const Color(0xFF15803D)
                                      : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _InProgressGroceryItemsList(
                          items: groceryItems,
                          pickedIndices: _pickedItemIndices,
                          onTogglePicked: (idx) {
                            setState(() {
                              if (_pickedItemIndices.contains(idx)) {
                                _pickedItemIndices.remove(idx);
                              } else {
                                _pickedItemIndices.add(idx);
                              }
                            });
                          },
                        ),
                      ],
                    ),
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

              const SizedBox(height: 14),

              // ═══════════════════════════════════════════════════════════
              // PHASE-BASED ACTION / PROOF AREA
              // ═══════════════════════════════════════════════════════════

              // ── Phase 3: Payment released → Helper clicks Mark Completed
              if (_isPaymentReleased) ...[
                _buildPaymentReleasedBanner(),
              ]

              // ── Phase 2: Waiting for poster to verify ─────────────────
              else if (_isVerifyPending || _proofSubmitted) ...[
                _buildWaitingBanner(task),
              ]

              // ── Phase 1: Actively working → Dashed 4:3 Proof Dropzone ─
              else if (!_isDone && !_proofSubmitted) ...[
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
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : _pickProof,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('Retake Proof Photo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF3B43E6),
                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                        minimumSize: const Size(double.infinity, 42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  InkWell(
                    onTap: busy ? null : _pickProof,
                    borderRadius: BorderRadius.circular(14),
                    child: _DashedBorderBox(
                      borderRadius: 14,
                      color: const Color(0xFF94A3B8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.photo_camera_outlined,
                                size: 22,
                                color: Color(0xFF3B43E6),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Capture Proof Photo',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Tap to open camera and take a photo',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
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
  final Set<int> pickedIndices;
  final ValueChanged<int> onTogglePicked;

  const _InProgressGroceryItemsList({
    required this.items,
    required this.pickedIndices,
    required this.onTogglePicked,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: List.generate(items.length, (idx) {
        final item = items[idx];
        final isPicked = pickedIndices.contains(idx);
        final pkg = item.package.trim();
        final qty = item.qty.trim();
        final kg = item.kg.trim();
        final gram = item.gram.trim();
        final litr = item.litr.trim();
        final brand = item.brand.trim();
        final rupee = item.rupee.trim();

        final tags = <Widget>[
          if (pkg.isNotEmpty)
            _tag(pkg, const Color(0xFFF1F5F9), const Color(0xFF334155)),
          if (qty.isNotEmpty)
            _tag('Qty: $qty', const Color(0xFFEFF6FF), const Color(0xFF1D4ED8)),
          if (kg.isNotEmpty)
            _tag('$kg kg', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
          if (gram.isNotEmpty)
            _tag('$gram g', const Color(0xFFF0FDF4), const Color(0xFF15803D)),
          if (litr.isNotEmpty)
            _tag('$litr L', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
          if (brand.isNotEmpty)
            _tag(brand, const Color(0xFFFAF5FF), const Color(0xFF7E22CE)),
          if (rupee.isNotEmpty)
            _tag('Est. ₹$rupee', const Color(0xFFFFFBEB),
                const Color(0xFFB45309)),
        ];

        return GestureDetector(
          onTap: () => onTogglePicked(idx),
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: idx == items.length - 1 ? 0 : 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPicked ? const Color(0xFFF0FDF4) : Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: isPicked
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFE2E8F0),
                width: 1.1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: item.imageUrl.isNotEmpty
                        ? Image.network(
                            item.imageUrl,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(item.emoji,
                                  style: const TextStyle(fontSize: 24)),
                            ),
                          )
                        : Center(
                            child: Text(item.emoji,
                                style: const TextStyle(fontSize: 24)),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: isPicked
                              ? const Color(0xFF64748B)
                              : const Color(0xFF0F172A),
                          decoration: isPicked
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (tags.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(spacing: 5, runSpacing: 4, children: tags),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isPicked
                        ? const Color(0xFF16A34A)
                        : Colors.transparent,
                    border: Border.all(
                      color: isPicked
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF94A3B8),
                      width: 1.8,
                    ),
                  ),
                  child: isPicked
                      ? const Icon(Icons.check_rounded,
                          size: 15, color: Colors.white)
                      : null,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  static Widget _tag(String text, Color bg, Color textCol) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
            fontSize: 11.5, fontWeight: FontWeight.w700, color: textCol),
      ),
    );
  }
}

class _NavigatePillButton extends StatelessWidget {
  final Color bgColor;
  final Color fgColor;
  final VoidCallback onTap;

  const _NavigatePillButton({
    required this.bgColor,
    required this.fgColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Navigate',
                style: TextStyle(
                  color: fgColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.north_east_rounded, size: 14, color: fgColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _DottedVerticalConnector extends StatelessWidget {
  const _DottedVerticalConnector();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        4,
        (i) => Container(
          width: 3,
          height: 3,
          margin: EdgeInsets.only(bottom: i == 3 ? 0 : 3.5),
          decoration: const BoxDecoration(
            color: Color(0xFF94A3B8),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderBox extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final Color color;

  const _DashedBorderBox({
    required this.child,
    this.borderRadius = 14,
    this.color = const Color(0xFF94A3B8),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        borderRadius: borderRadius,
        color: color,
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final double borderRadius;
  final Color color;

  _DashedRRectPainter({required this.borderRadius, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderRadius != borderRadius;
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
