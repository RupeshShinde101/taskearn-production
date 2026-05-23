import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
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
  bool _submitting = false;  // for submit-for-verification
  bool _completing = false;  // for final mark-as-completed
  bool _abandoning = false;
  String? _proofPath;
  Timer? _pollTimer;
  StreamSubscription<Position>? _locationSub;
  bool _paymentPopupShown = false; // ensure payment popup shown only once
  bool _loaded = false;            // true after first data load; polls are silent

  // ── statuses treated as "cancelled" — helper should be redirected away
  static const _cancelledStatuses = {
    'cancelled', 'poster_cancelled', 'rejected', 'expired',
  };
  // ── statuses treated as "verification pending" (proof submitted, waiting poster)
  static const _verifyPendingStatuses = {
    'completed', 'verify_pending',
  };
  // ── status after poster verified / payment released — helper must confirm
  // 'paid' = poster has paid but helper has NOT yet clicked Mark as Completed
  static const _paymentReleasedStatuses = {
    'payment_released', 'verified', 'paid',
  };
  // ── truly finished (helper already clicked Mark as Completed)
  static const _doneStatuses = {
    'done', 'finished',
  };

  bool get _isDone =>
      _task != null && _doneStatuses.contains(_task!.status);

  // Payment released = explicit status OR isPaid flag set (backend may keep
  // old status like 'completed'/'accepted' when releasing payment).
  bool get _isPaymentReleased =>
      _task != null &&
      !_isDone &&
      (_paymentReleasedStatuses.contains(_task!.status) || _task!.isPaid);

  // Only "verify pending" when payment has NOT yet been released.
  bool get _isVerifyPending =>
      _task != null &&
      !_isPaymentReleased &&
      _verifyPendingStatuses.contains(_task!.status);

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

  bool _taskIsPaymentReleased(Task? t) =>
      t != null &&
      !_doneStatuses.contains(t.status) &&
      (_paymentReleasedStatuses.contains(t.status) || t.isPaid);

  Future<void> _load() async {
    if (!mounted) return;
    // Only show full-screen spinner on the very first load. Subsequent polls
    // update _task silently so the user never sees a spinner flash every 15 s.
    if (!_loaded) setState(() { _loading = true; });
    final prevTask = _task;
    final task = await context.read<TaskProvider>().getTaskDetail(widget.taskId);
    if (!mounted) return;

    // If posterPhone is missing on first load, refresh user tasks (which may
    // include the phone in its list response) and try the detail again once.
    // This handles the server propagation delay right after accepting a task.
    if (!_loaded && task != null &&
        (task.posterPhone == null || task.posterPhone!.trim().isEmpty)) {
      await context.read<TaskProvider>().fetchMyTasks();
      if (!mounted) return;
      final retried = await context.read<TaskProvider>().getTaskDetail(widget.taskId);
      if (!mounted) return;
      setState(() {
        _task = retried ?? task;
        _loading = false;
        _loaded = true;
      });
    } else {
      setState(() {
        _task = task;
        _loading = false;
        _loaded = true;
      });
    }

    // If task data cannot be found at all (deleted/404), release and exit.
    final status = _task?.status ?? '';
    if (_task == null) {
      _pollTimer?.cancel();
      _showTaskGoneDialog();
      return;
    }

    // If the poster cancelled, redirect.
    if (_cancelledStatuses.contains(status)) {
      _pollTimer?.cancel();
      _showCancelledDialog();
      return;
    }

    // Detect transition to payment-released state using both status AND isPaid.
    final wasPaymentReleased = _taskIsPaymentReleased(prevTask);
    final nowPaymentReleased = _taskIsPaymentReleased(_task);
    if (nowPaymentReleased && !wasPaymentReleased && !_paymentPopupShown) {
      _paymentPopupShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPaymentReceivedDialog();
      });
    }
  }

  // ── Payment received popup with earnings breakdown ────────────────────────
  Future<void> _showPaymentReceivedDialog() async {
    if (!mounted || _task == null) return;
    final task = _task!;
    final commission = task.totalAmount * task.commissionRate;
    final helperEarning = task.netEarning;
    final commissionPct = (task.commissionRate * 100).toStringAsFixed(0);

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
            Text(
              'The task poster verified your work and released your payment. Here\'s the breakdown:',
              style: const TextStyle(
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
                    value: '₹${task.totalAmount.toStringAsFixed(0)}',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _BreakdownRow(
                    label: 'Platform Commission ($commissionPct%)',
                    value: '− ₹${commission.toStringAsFixed(0)}',
                    valueColor: AppColors.danger,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1),
                  ),
                  _BreakdownRow(
                    label: 'Your Earning',
                    value: '₹${helperEarning.toStringAsFixed(0)}',
                    bold: true,
                    valueColor: AppColors.success,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '₹ credited to your wallet after you mark the task as completed.',
              style: TextStyle(
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

  /// Called when the task data returns null (task deleted or 404 on backend).
  /// Silently releases the stale server-side binding then navigates away.
  Future<void> _showTaskGoneDialog() async {
    if (!mounted) return;
    // Silently try to release the stale task binding (handles 404 gracefully).
    await context.read<TaskProvider>().abandonTask(widget.taskId);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Task Unavailable'),
        content: const Text(
          'This task is no longer available and you have been released.',
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
    if (mounted) context.go('/my-tasks');
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

  Future<void> _openDropNavigation() async {
    if (_task == null) return;
    final dropLat = _task!.dropLatitude;
    final dropLng = _task!.dropLongitude;
    final dropAddr = _task!.dropAddress;

    Uri uri;
    if (dropLat != null && dropLng != null) {
      // Prefer precise coordinates
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=$dropLat,$dropLng'
          '&travelmode=driving');
    } else if (dropAddr != null && dropAddr.trim().isNotEmpty) {
      // Fall back to address text search
      uri = Uri.parse(
          'https://www.google.com/maps/dir/?api=1'
          '&destination=${Uri.encodeComponent(dropAddr.trim())}'
          '&travelmode=driving');
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drop location not available')),
        );
      }
      return;
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
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
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open dialler.')),
        );
      }
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
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp.')),
        );
      }
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
      // Show rating dialog so helper can rate the poster before leaving
      await _showRatePosterDialog();
      if (!mounted) return;
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
      // Refresh — backend error likely means our cached status was stale
      // (e.g. payment not yet released on server despite local flag showing paid).
      _load();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to complete task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  /// Show a rating dialog so the helper can rate the task poster.
  /// Called after successful mark-complete. Safe to skip (barrierDismissible=false
  /// but has a Skip button).
  Future<void> _showRatePosterDialog() async {
    if (!mounted) return;
    double selectedRating = 5.0;
    final commentCtrl = TextEditingController();
    bool submitted = false;
    final posterName = _task?.posterName ?? 'the poster';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Rate the Task Poster',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How was your experience with $posterName?',
                style: const TextStyle(color: AppColors.gray, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  5,
                  (i) => GestureDetector(
                    onTap: () =>
                        setDialog(() => selectedRating = (i + 1).toDouble()),
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
              const SizedBox(height: 14),
              TextField(
                controller: commentCtrl,
                decoration: const InputDecoration(
                  labelText: 'Comment (optional)',
                  hintText: 'Leave a review...',
                  border: OutlineInputBorder(),
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
                Navigator.pop(ctx);
              },
              child: const Text('Submit Rating'),
            ),
          ],
        ),
      ),
    );

    commentCtrl.dispose();
    if (submitted && mounted) {
      await context.read<TaskProvider>().rateTask(
            widget.taskId,
            selectedRating,
            null,
          );
    }
  }

  Future<void> _releaseTask() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Task'),
        content: const Text(
            'Releasing a task without completing it may result in a penalty.\n\n'
            'More than 3 releases may trigger a 48-hour account suspension.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Release',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _abandoning = true);
    final ok = await context.read<TaskProvider>().abandonTask(widget.taskId);
    if (!mounted) return;
    setState(() => _abandoning = false);
    if (ok) {
      context.go('/my-tasks');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.read<TaskProvider>().error ?? 'Failed to release task'),
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
    final netEarning = task.netEarning;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task In Progress'),
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

              const SizedBox(height: 14),

              // ── Navigate to Location (only while actively working) ───
              if (!_isVerifyPending && !_isDone)
                _SectionCard(
                  title: 'Task Location',
                  icon: Icons.location_on_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delivery task (delivery / transport / pickup / moving):
                      // show pickup and drop addresses with navigation buttons.
                      if (task.isDeliveryType) ...[
                        if (task.pickupAddress != null) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.radio_button_checked,
                                  color: AppColors.primary, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Pickup',
                                        style: TextStyle(
                                            color: AppColors.gray,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600)),
                                    Text(task.pickupAddress!,
                                        style: const TextStyle(
                                            color: AppColors.dark,
                                            fontSize: 13,
                                            height: 1.3)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                        // Drop address row (always shown for delivery tasks;
                        // shows placeholder when poster hasn't set drop yet)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.location_on,
                                color: AppColors.danger, size: 16),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Drop',
                                      style: TextStyle(
                                          color: AppColors.gray,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                    task.dropAddress ?? 'Drop location not set by poster',
                                    style: TextStyle(
                                        color: task.dropAddress != null
                                            ? AppColors.dark
                                            : AppColors.grayLight,
                                        fontSize: 13,
                                        height: 1.3),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Navigate to pickup location
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openNavigation,
                            icon: const Icon(Icons.navigation_rounded, size: 18),
                            label: const Text('Navigate to Pickup'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        if (task.dropAddress != null || task.dropLatitude != null) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: task.dropAddress != null || task.dropLatitude != null
                                  ? _openDropNavigation
                                  : null,
                              icon: const Icon(Icons.flag_outlined, size: 18),
                              label: const Text('Navigate to Drop Location'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ] else ...[
                        // Non-delivery task: single location
                        if (task.address != null && task.address!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              task.address!,
                              style: const TextStyle(
                                  color: AppColors.gray,
                                  fontSize: 13,
                                  height: 1.4),
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openNavigation,
                            icon: const Icon(Icons.navigation_rounded, size: 18),
                            label: const Text('Navigate to Task Location'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              if (!_isVerifyPending && !_isDone) const SizedBox(height: 12),

              // ── Poster Contact ───────────────────────────────────────
              _SectionCard(
                title: 'Task Poster',
                icon: Icons.person_outline,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Poster info row
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.12),
                          backgroundImage: (task.posterAvatar != null &&
                                  task.posterAvatar!.isNotEmpty)
                              ? NetworkImage(task.posterAvatar!)
                              : null,
                          onBackgroundImageError:
                              (task.posterAvatar != null &&
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
                                      fontWeight: FontWeight.w700,
                                      fontSize: 18),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (task.posterName.isNotEmpty &&
                                        task.posterName != 'Anonymous')
                                    ? task.posterName
                                    : 'Task Poster',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.dark),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                              if (task.posterRating > 0) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.star,
                                        size: 13, color: AppColors.warning),
                                    const SizedBox(width: 2),
                                    Text(
                                      task.posterRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                          color: AppColors.gray, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                              if (hasPhone)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    task.posterPhone!.trim(),
                                    style: const TextStyle(
                                        color: AppColors.gray, fontSize: 12),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Contact buttons stacked to avoid overflow
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _callPoster,
                        icon: const Icon(Icons.call, size: 17),
                        label: Text(
                          hasPhone ? 'Call Poster' : 'Call (no number)',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              hasPhone ? AppColors.success : AppColors.grayLight,
                          side: BorderSide(
                              color: hasPhone
                                  ? AppColors.success
                                  : AppColors.grayLight),
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _whatsappPoster,
                        icon: const Icon(Icons.chat_bubble_outline, size: 17),
                        label: Text(
                          hasPhone ? 'WhatsApp Poster' : 'WhatsApp (no number)',
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: hasPhone
                              ? const Color(0xFF25D366)
                              : AppColors.grayLight,
                          side: BorderSide(
                              color: hasPhone
                                  ? const Color(0xFF25D366)
                                  : AppColors.grayLight),
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),

                    if (!hasPhone)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Contact number was not provided by the poster.',
                          style:
                              TextStyle(color: AppColors.grayLight, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Task Details ─────────────────────────────────────────
              _SectionCard(
                title: 'Task Details',
                icon: Icons.description_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailRow('Category', task.category),
                    const Divider(height: 14),
                    _DetailRow(
                        'Net Earning', '₹${netEarning.toStringAsFixed(0)}'),
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
              else if (_isVerifyPending) ...[
                _buildWaitingBanner(task),
              ]

              // ── Phase 1: Actively working → Upload proof & submit ─────
              else if (!_isDone) ...[
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

                // Proof preview
                if (_proofPath != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _proofPath!.startsWith('http')
                        ? Image.network(
                            _proofPath!,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _proofErrorWidget(),
                          )
                        : Image.file(
                            File(_proofPath!),
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Net Earning',
                  style: TextStyle(color: Colors.white70, fontSize: 10)),
              Text(
                '₹${task.netEarning.toStringAsFixed(0)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800),
              ),
            ],
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
              task.completionProof!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                task.completionProof!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
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

  Widget _proofErrorWidget() => Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(12),
        ),
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
                Icon(icon, size: 15, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.dark),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
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
