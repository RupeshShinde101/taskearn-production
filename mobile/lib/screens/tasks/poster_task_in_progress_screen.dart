import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/grocery_item.dart';
import '../../models/task.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/confirm_payment_dialog.dart';

/// Task Poster's Live Tracking / Task In Progress screen (Design 4).
/// Displays live emerald status hero with ETA, docked interactive mini-map
/// polling helper GPS, helper contact card (Call & Message), segmented tabs
/// ("Items & Route" | "Proof & Pay" with 4:3 proof verification), and cancel.
class PosterTaskInProgressScreen extends StatefulWidget {
  final String taskId;
  const PosterTaskInProgressScreen({super.key, required this.taskId});

  @override
  State<PosterTaskInProgressScreen> createState() =>
      _PosterTaskInProgressScreenState();
}

class _PosterTaskInProgressScreenState
    extends State<PosterTaskInProgressScreen> {
  Task? _task;
  bool _loading = true;
  bool _initialLoad = true;
  int _selectedTab = 0; // 0 = Items & Route, 1 = Proof & Pay

  // Live helper tracking & authoritative helper profile state
  LatLng? _helperLatLng;
  String? _helperName;
  String? _helperPhone;
  double? _helperRating;
  String? _etaText;
  String? _distanceText;
  String? _proofUrl;
  Uint8List? _cachedProofBytes;
  String? _cachedProofSource;
  bool _cancelling = false;
  bool _paying = false;
  bool _mapReady = false;
  bool _hasCenteredOnHelper = false;

  Timer? _pollTimer;
  final MapController _mapController = MapController();

  static bool _isPlaceholderName(String? name) {
    final s = (name ?? '').trim().toLowerCase();
    return s.isEmpty ||
        s == 'helper' ||
        s == 'assigned helper' ||
        s == 'waiting for helper' ||
        s == 'anonymous' ||
        s == 'user';
  }

  String get _resolvedHelperName {
    if (!_isPlaceholderName(_helperName)) return _helperName!.trim();
    if (!_isPlaceholderName(_task?.helperName)) return _task!.helperName!.trim();
    return 'Assigned Helper';
  }

  String? get _resolvedHelperPhone {
    final p1 = _helperPhone?.trim();
    if (p1 != null && p1.isNotEmpty) return p1;
    final p2 = _task?.helperPhone?.trim();
    if (p2 != null && p2.isNotEmpty) return p2;
    return null;
  }

  double? get _resolvedHelperRating {
    if (_helperRating != null && _helperRating! > 0) return _helperRating;
    if (_task?.helperRating != null && _task!.helperRating! > 0) {
      return _task!.helperRating;
    }
    return null;
  }

  static const _verifyPendingStatuses = {'completed', 'verify_pending'};
  static const _paidStatuses = {
    'payment_released',
    'paid',
    'verified',
    'done',
    'finished',
  };
  static const _cancelledStatuses = {
    'cancelled',
    'poster_cancelled',
    'rejected',
    'expired',
  };

  bool get _needsVerify =>
      _task != null && _verifyPendingStatuses.contains(_task!.status);
  bool get _isPaidOrDone =>
      _task != null && _paidStatuses.contains(_task!.status);
  bool get _isCancelled =>
      _task != null && _cancelledStatuses.contains(_task!.status);
  bool get _canCancel =>
      _task != null &&
      !_needsVerify &&
      !_isPaidOrDone &&
      !_isCancelled;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) {
        if (mounted) _pollTrackingAndStatus();
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    if (_initialLoad) setState(() => _loading = true);

    final provider = context.read<TaskProvider>();
    final task = await provider.getTaskDetail(widget.taskId);
    if (!mounted) return;

    if (task != null) {
      // Seed helper name/phone from task or myPostedTasks cache immediately
      String? seedName = task.helperName;
      String? seedPhone = task.helperPhone;
      double? seedRating = task.helperRating;
      for (final posted in provider.myPostedTasks) {
        if (posted.id == task.id) {
          if (_isPlaceholderName(seedName) &&
              !_isPlaceholderName(posted.helperName)) {
            seedName = posted.helperName;
          }
          if ((seedPhone == null || seedPhone.trim().isEmpty) &&
              posted.helperPhone != null &&
              posted.helperPhone!.trim().isNotEmpty) {
            seedPhone = posted.helperPhone;
          }
          if ((seedRating == null || seedRating <= 0) &&
              posted.helperRating != null &&
              posted.helperRating! > 0) {
            seedRating = posted.helperRating;
          }
          break;
        }
      }

      final wasNeedsVerify = _needsVerify;
      setState(() {
        _task = task;
        if (!_isPlaceholderName(seedName)) _helperName = seedName;
        if (seedPhone != null && seedPhone.trim().isNotEmpty) {
          _helperPhone = seedPhone.trim();
        }
        if (seedRating != null && seedRating > 0) _helperRating = seedRating;
        _loading = false;
        _initialLoad = false;
        if (!wasNeedsVerify && _verifyPendingStatuses.contains(task.status)) {
          _selectedTab = 1; // Auto-switch to Proof & Pay when proof arrives
        }
      });
      _syncProof(task);
      await _fetchTrackingInfo();
      await _fetchLiveLocation();
    } else {
      setState(() {
        _loading = false;
        _initialLoad = false;
      });
    }
  }

  Future<void> _pollTrackingAndStatus() async {
    await _fetchLiveLocation();
    if (!mounted) return;
    if (_isPlaceholderName(_helperName) || _resolvedHelperPhone == null) {
      await _fetchTrackingInfo();
      if (!mounted) return;
    }
    final provider = context.read<TaskProvider>();
    final fresh = await provider.getTaskDetail(widget.taskId);
    if (!mounted || fresh == null) return;
    final wasNeedsVerify = _needsVerify;
    setState(() {
      _task = fresh;
      if (_isPlaceholderName(_helperName) &&
          !_isPlaceholderName(fresh.helperName)) {
        _helperName = fresh.helperName;
      }
      if ((_helperPhone == null || _helperPhone!.isEmpty) &&
          fresh.helperPhone != null &&
          fresh.helperPhone!.trim().isNotEmpty) {
        _helperPhone = fresh.helperPhone!.trim();
      }
      if (!wasNeedsVerify && _verifyPendingStatuses.contains(fresh.status)) {
        _selectedTab = 1;
      }
    });
    _syncProof(fresh);
  }

  /// Fetches authoritative helper name, phone, rating, and latest GPS from
  /// GET /api/tracking/<task_id> (joined directly with users table).
  Future<void> _fetchTrackingInfo() async {
    try {
      final res = await ApiService.get('/tracking/${widget.taskId}');
      if (!mounted) return;
      final tracking =
          res['tracking'] is Map ? res['tracking'] as Map : (res is Map ? res : null);
      if (tracking == null) return;

      final helper = tracking['helper'] is Map ? tracking['helper'] as Map : null;
      final hLoc = tracking['helperLocation'] is Map
          ? tracking['helperLocation'] as Map
          : null;

      LatLng? parsedLoc;
      if (hLoc != null) {
        final lat = (hLoc['lat'] as num?)?.toDouble();
        final lng = (hLoc['lng'] as num?)?.toDouble();
        if (lat != null && lng != null && (lat != 0 || lng != 0)) {
          parsedLoc = LatLng(lat, lng);
        }
      }

      setState(() {
        if (helper != null) {
          final name = helper['name']?.toString().trim();
          if (!_isPlaceholderName(name)) _helperName = name;
          final phone = helper['phone']?.toString().trim();
          if (phone != null && phone.isNotEmpty) _helperPhone = phone;
          final rating = (helper['rating'] as num?)?.toDouble();
          if (rating != null && rating > 0) _helperRating = rating;
        }
        if (parsedLoc != null) {
          _helperLatLng = parsedLoc;
        }
        final eta = tracking['eta']?.toString();
        if (eta != null && eta.isNotEmpty) _etaText = eta;
        final dist = tracking['distance']?.toString();
        if (dist != null && dist.isNotEmpty) _distanceText = dist;
      });

      if (parsedLoc != null) {
        _centerMapOnHelper(force: !_hasCenteredOnHelper);
      }
    } catch (_) {}
  }

  Future<void> _syncProof(Task task) async {
    String? url = (task.completionProof != null &&
            task.completionProof!.trim().isNotEmpty)
        ? task.completionProof!.trim()
        : null;

    if (url == null &&
        (_verifyPendingStatuses.contains(task.status) ||
            _paidStatuses.contains(task.status))) {
      try {
        final urls =
            await context.read<TaskProvider>().fetchTaskProofs(task.id);
        if (urls.isNotEmpty) url = urls.first;
      } catch (_) {}
    }

    if (!mounted || url == null) return;
    if (_cachedProofSource != url) {
      Uint8List? bytes;
      if (url.startsWith('data:')) {
        final comma = url.indexOf(',');
        if (comma != -1) {
          try {
            bytes = base64Decode(url.substring(comma + 1));
          } catch (_) {}
        }
      }
      setState(() {
        _proofUrl = url;
        _cachedProofSource = url;
        _cachedProofBytes = bytes;
      });
    }
  }

  Future<void> _fetchLiveLocation() async {
    if (_task == null || _isPaidOrDone || _isCancelled) return;
    try {
      final res = await ApiService.get('/tracking/${widget.taskId}/location');
      if (!mounted) return;
      final loc = res['location'];
      if (loc is Map) {
        final lat = (loc['lat'] as num?)?.toDouble();
        final lng = (loc['lng'] as num?)?.toDouble();
        if (lat != null && lng != null && (lat != 0 || lng != 0)) {
          final updated = LatLng(lat, lng);
          final moved = _helperLatLng == null ||
              _haversineKm(_helperLatLng!, updated) > 0.01;
          setState(() {
            _helperLatLng = updated;
            _etaText = res['eta']?.toString();
            _distanceText = res['distance']?.toString();
          });
          if (moved || !_hasCenteredOnHelper) {
            _centerMapOnHelper(force: !_hasCenteredOnHelper);
          }
          return;
        }
      }
    } catch (_) {}
  }

  void _centerMapOnHelper({bool force = false}) {
    if (!_mapReady || _helperLatLng == null) return;
    try {
      final pts = <LatLng>[
        _helperLatLng!,
        if (_pickupLatLng != null) _pickupLatLng!,
        if (_dropLatLng != null) _dropLatLng!,
      ];
      // If helper is close enough to route points (< 15 km), fit all pins cleanly;
      // otherwise center directly on the helper's exact live GPS pin.
      if (!force && pts.length >= 2) {
        final maxKm = pts
            .map((p) => _haversineKm(_helperLatLng!, p))
            .reduce(math.max);
        if (maxKm > 0.05 && maxKm < 15.0) {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds.fromPoints(pts),
              padding: const EdgeInsets.all(36),
            ),
          );
          _hasCenteredOnHelper = true;
          return;
        }
      }
      _mapController.move(_helperLatLng!, 15.8);
      _hasCenteredOnHelper = true;
    } catch (_) {}
  }

  LatLng? get _pickupLatLng {
    final t = _task;
    if (t == null || (t.latitude == 0 && t.longitude == 0)) return null;
    return LatLng(t.latitude, t.longitude);
  }

  LatLng? get _dropLatLng {
    final t = _task;
    if (t == null ||
        t.dropLatitude == null ||
        t.dropLongitude == null ||
        (t.dropLatitude == 0 && t.dropLongitude == 0)) {
      return null;
    }
    return LatLng(t.dropLatitude!, t.dropLongitude!);
  }

  bool get _hasPhysicalMap {
    final t = _task;
    if (t == null) return false;
    if (Task.isFreelancerCategory(t.category)) return false;
    return _pickupLatLng != null || _dropLatLng != null || _helperLatLng != null;
  }

  LatLng get _mapCenter {
    if (_helperLatLng != null) return _helperLatLng!;
    if (_pickupLatLng != null && _dropLatLng != null) {
      return LatLng(
        (_pickupLatLng!.latitude + _dropLatLng!.latitude) / 2,
        (_pickupLatLng!.longitude + _dropLatLng!.longitude) / 2,
      );
    }
    return _pickupLatLng ?? _dropLatLng ?? const LatLng(18.5204, 73.8567);
  }

  /// Computes a clean numeric ETA badge ("8" / "mins") or fallback status badge.
  ({String top, String bottom}) get _etaBox {
    if (_isPaidOrDone) return (top: '✓', bottom: 'Done');
    if (_needsVerify) return (top: '✓', bottom: 'Verify');
    if (_isCancelled) return (top: '—', bottom: 'Closed');

    if (_etaText != null && _etaText!.isNotEmpty) {
      final match = RegExp(r'(\d+)').firstMatch(_etaText!);
      if (match != null) {
        return (top: match.group(1)!, bottom: 'mins');
      }
      if (_etaText!.toLowerCase().contains('arriv')) {
        return (top: '1', bottom: 'min');
      }
    }

    // Fallback: estimate from helper → pickup if coords available
    if (_helperLatLng != null && _pickupLatLng != null) {
      final km = _haversineKm(_helperLatLng!, _pickupLatLng!);
      final mins = math.max(1, (km / 20.0 * 60).round());
      return (top: '$mins', bottom: mins == 1 ? 'min' : 'mins');
    }

    return (top: 'LIVE', bottom: 'GPS');
  }

  String get _liveDistanceLabel {
    if (_distanceText != null &&
        _distanceText!.isNotEmpty &&
        !_distanceText!.toLowerCase().contains('calc')) {
      return 'Live GPS • $_distanceText';
    }
    if (_helperLatLng != null && _pickupLatLng != null) {
      final km = _haversineKm(_helperLatLng!, _pickupLatLng!);
      return 'Live GPS • ${km.toStringAsFixed(1)} km';
    }
    return 'Live GPS • Tracking active';
  }

  static double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(a.latitude * math.pi / 180) *
            math.cos(b.latitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  String get _headerTitle {
    if (_isCancelled) return 'Task Cancelled';
    if (_isPaidOrDone) return 'Task Completed';
    if (_needsVerify) return 'Proof Submitted!';
    return 'Helper on the way';
  }

  String get _headerSubtitle {
    final t = _task;
    if (t == null) return '';
    if (_isCancelled) return 'This task has been cancelled';
    if (_isPaidOrDone) return 'Payment released — thank you!';
    if (_needsVerify) return 'Review proof photo & release payment';
    final dest = GroceryCatalog.unescapeHtml(
      t.effectivePickupAddress.isNotEmpty
          ? t.effectivePickupAddress
          : (t.address ?? t.title),
    );
    return 'Heading to $dest';
  }

  Future<void> _callHelper() async {
    var phone = _resolvedHelperPhone;
    if (phone == null || phone.isEmpty) {
      await _fetchTrackingInfo();
      phone = _resolvedHelperPhone;
    }
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Helper phone number is not available.'),
          ),
        );
      }
      return;
    }
    final clean = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$clean');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open dialer.')),
          );
        }
      }
    }
  }

  void _openChat() {
    final t = _task;
    if (t == null) return;
    context.push(
      '/chat/${t.id}',
      extra: {
        'taskId': t.id,
        'taskTitle': t.title,
        'otherName': _resolvedHelperName,
        'otherRole': 'Helper',
        'otherPhone': _resolvedHelperPhone,
        'category': t.category,
        'budget': t.budget,
        'status': t.status,
        'isPoster': true,
      },
    );
  }

  void _openFullscreenMap() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.88,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            _buildFlutterMap(interactive: true),
            Positioned(
              top: 14,
              left: 14,
              right: 14,
              child: Row(
                children: [
                  Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF0F172A)),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _liveDistanceLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    final t = _task;
    if (t == null || _cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Task?'),
        content: const Text(
          'A helper is already assigned to this task. Are you sure you want to cancel it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Task'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Task'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _cancelling = true);
    final ok = await context.read<TaskProvider>().cancelTask(t.id);
    if (!mounted) return;
    setState(() => _cancelling = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Task cancelled.'),
          backgroundColor: AppColors.success,
        ),
      );
      if (GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/my-tasks');
      }
    } else {
      final err = context.read<TaskProvider>().error ?? 'Failed to cancel task';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _verifyAndPay() async {
    final t = _task;
    if (t == null || _paying) return;
    setState(() => _paying = true);
    final wallet = context.read<WalletProvider>();
    await wallet.fetchWallet();
    if (!mounted) return;
    setState(() => _paying = false);

    final budget = t.budget;
    final charge = t.serviceCharge ?? 0;
    final posterFee = t.posterFee;
    final total = t.totalPosterCost;

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
    final ok = await ConfirmPaymentDialog.show(
      context: context,
      budget: budget,
      serviceCharge: charge,
      posterFee: posterFee,
      totalCost: total,
      currentWalletBalance: wallet.balance.balance,
      onConfirm: () => context.read<TaskProvider>().payHelper(t.id),
    );
    if (!mounted) return;

    if (ok == true) {
      wallet.fetchWallet();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment released to helper successfully!'),
          backgroundColor: AppColors.success,
        ),
      );
      _loadAll();
    } else if (ok == false) {
      final err =
          context.read<TaskProvider>().error ?? 'Payment failed. Try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: AppColors.danger),
      );
    }
  }

  Widget _buildFlutterMap({bool interactive = false}) {
    final pickup = _pickupLatLng;
    final drop = _dropLatLng;
    final helper = _helperLatLng;

    final routePoints = <LatLng>[
      if (helper != null) helper,
      if (pickup != null) pickup,
      if (drop != null) drop,
    ];

    final markers = <Marker>[
      if (pickup != null)
        Marker(
          point: pickup,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A8A),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(
              Task.isGroceryCategory(_task?.category ?? '')
                  ? Icons.storefront_rounded
                  : Icons.location_on_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      if (drop != null)
        Marker(
          point: drop,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: const Icon(
              Icons.home_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      if (helper != null)
        Marker(
          point: helper,
          width: 72,
          height: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669).withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.delivery_dining_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF059669),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: const Text(
                  'Helper',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    return FlutterMap(
      mapController: interactive ? null : _mapController,
      options: MapOptions(
        initialCenter: _mapCenter,
        initialZoom: 15.2,
        onMapReady: interactive
            ? null
            : () {
                _mapReady = true;
                _centerMapOnHelper(force: true);
              },
        interactionOptions: InteractionOptions(
          flags: interactive
              ? InteractiveFlag.all
              : InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.workmate4u.workmate4u',
        ),
        if (routePoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                color: const Color(0xFF334155),
                strokeWidth: 3.5,
              ),
            ],
          ),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildProofContent(Task task) {
    if (_isPaidOrDone) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFA7F3D0)),
        ),
        child: Column(
          children: [
            const Icon(Icons.verified_rounded,
                color: Color(0xFF059669), size: 44),
            const SizedBox(height: 10),
            const Text(
              'Payment Released & Verified',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFF065F46),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Thank you for using WorkMate4U!',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
            ),
            if (_proofUrl != null) ...[
              const SizedBox(height: 14),
              _buildProofPhotoFrame(),
            ],
          ],
        ),
      );
    }

    if (_needsVerify) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Completion Proof Photo',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            if (_proofUrl != null)
              _buildProofPhotoFrame()
            else
              Container(
                width: double.infinity,
                height: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'Loading proof photo...',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                ),
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _paying ? null : _verifyAndPay,
                icon: _paying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified_user_rounded, size: 19),
                label: Text(
                  'Verify & Release Payment (₹${task.totalPosterCost.toStringAsFixed(0)})',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Active — waiting for helper to finish and upload proof
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: const Column(
        children: [
          Icon(Icons.hourglass_top_rounded,
              color: Color(0xFF0D9488), size: 36),
          SizedBox(height: 10),
          Text(
            'Waiting for Completion Proof',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF0F172A),
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Once your helper finishes and captures a proof photo, it will appear right here so you can verify and release payment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProofPhotoFrame() {
    final url = _proofUrl!;
    Widget img;
    if (url.startsWith('data:') && _cachedProofBytes != null) {
      img = Image.memory(
        _cachedProofBytes!,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      img = Image.network(
        url,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image_outlined,
              size: 36, color: Color(0xFF94A3B8)),
        ),
      );
    }
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
        child: img,
      ),
    );
  }

  Widget _buildItemsAndRouteTab(Task task) {
    final isGrocery = Task.isGroceryCategory(task.category);
    final groceryItems = isGrocery
        ? ((task.groceryItems != null && task.groceryItems!.isNotEmpty)
            ? task.groceryItems!
            : GroceryCatalog.parseGroceryItems(null, task.description))
        : const <SelectedGroceryItem>[];

    final pickupAddr = GroceryCatalog.unescapeHtml(
      task.effectivePickupAddress.isNotEmpty
          ? task.effectivePickupAddress
          : (task.address ?? 'Location'),
    );
    final dropAddr = task.effectiveDropAddress != null
        ? GroceryCatalog.unescapeHtml(task.effectiveDropAddress!)
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isGrocery && groceryItems.isNotEmpty) ...[
            Text(
              'Grocery Items (${groceryItems.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
            ...groceryItems.map((item) {
              final detailParts = <String>[
                if (item.package.trim().isNotEmpty) item.package.trim(),
                if (item.qty.trim().isNotEmpty) 'Qty ${item.qty.trim()}',
                if (item.kg.trim().isNotEmpty) '${item.kg.trim()} kg',
                if (item.gram.trim().isNotEmpty) '${item.gram.trim()} g',
                if (item.litr.trim().isNotEmpty) '${item.litr.trim()} L',
              ];
              final line = detailParts.isEmpty
                  ? item.name
                  : '${item.name} • ${detailParts.join(' · ')}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: item.imageUrl.isNotEmpty
                          ? Image.network(
                              item.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text(item.emoji,
                                    style: const TextStyle(fontSize: 22)),
                              ),
                            )
                          : Center(
                              child: Text(item.emoji,
                                  style: const TextStyle(fontSize: 22)),
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        line,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0F172A),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Divider(height: 18, color: Color(0xFFF1F5F9)),
          ] else ...[
            Text(
              task.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.5,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${task.category} • ₹${task.budget.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Divider(height: 18, color: Color(0xFFF1F5F9)),
          ],

          // Route strip (Store -> Delivery OR single Task Location)
          if (task.isDeliveryCategory && dropAddr != null)
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      pickupAddr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.arrow_forward_rounded,
                      size: 15, color: Color(0xFF64748B)),
                ),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      dropAddr,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 16, color: Color(0xFF0D9488)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pickupAddr,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4F6FA),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final task = _task;
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task Tracking')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load task details.'),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _loadAll, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final helperName = _resolvedHelperName;
    final hasPhone = _resolvedHelperPhone != null;
    final helperRating = _resolvedHelperRating;
    final eta = _etaBox;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top Emerald-to-Teal Status Header (Original Design 4) ──
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF059669), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 16, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () {
                                if (GoRouter.of(context).canPop()) {
                                  context.pop();
                                } else {
                                  context.go('/my-tasks');
                                }
                              },
                              icon: const Icon(Icons.arrow_back_rounded,
                                  color: Colors.white, size: 24),
                            ),
                            IconButton(
                              onPressed: _loadAll,
                              icon: const Icon(Icons.refresh_rounded,
                                  color: Colors.white, size: 22),
                              tooltip: 'Refresh',
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _headerTitle,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _headerSubtitle,
                                      style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.92),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        height: 1.3,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Compact white boxed ETA / LIVE GPS badge
                              Container(
                                constraints: const BoxConstraints(minWidth: 50),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      eta.top,
                                      style: TextStyle(
                                        color: const Color(0xFF0F172A),
                                        fontWeight: FontWeight.w900,
                                        fontSize:
                                            eta.top.length > 2 ? 11.5 : 16,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      eta.bottom,
                                      style: const TextStyle(
                                        color: Color(0xFF475569),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 9.5,
                                      ),
                                    ),
                                  ],
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

              // ── Docked Rounded Mini-Map ──────────────────────────────
              if (_hasPhysicalMap)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Container(
                    height: 205,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        _buildFlutterMap(interactive: false),
                        // Compact Recenter + Small Live GPS & Expand overlay
                        Positioned(
                          right: 8,
                          bottom: 8,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_helperLatLng != null) ...[
                                Material(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  shape: const CircleBorder(),
                                  elevation: 2,
                                  child: InkWell(
                                    onTap: () =>
                                        _centerMapOnHelper(force: true),
                                    customBorder: const CircleBorder(),
                                    child: const SizedBox(
                                      width: 26,
                                      height: 26,
                                      child: Icon(Icons.my_location_rounded,
                                          size: 14, color: Color(0xFF059669)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              InkWell(
                                onTap: _openFullscreenMap,
                                borderRadius: BorderRadius.circular(7),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A)
                                        .withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _liveDistanceLabel,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.open_in_full_rounded,
                                          color: Colors.white, size: 11),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // ── Helper Contact Card ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
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
                        radius: 23,
                        backgroundColor: const Color(0xFF059669)
                            .withValues(alpha: 0.14),
                        child: Text(
                          helperName[0].toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF047857),
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              helperName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded,
                                    size: 14, color: Color(0xFF0F172A)),
                                const SizedBox(width: 2),
                                Text(
                                  (helperRating != null && helperRating > 0)
                                      ? '${helperRating.toStringAsFixed(1)} • Verified'
                                      : 'Verified Helper',
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Call button
                      Material(
                        color: hasPhone
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFE2E8F0),
                        shape: const CircleBorder(),
                        elevation: hasPhone ? 2 : 0,
                        child: InkWell(
                          onTap: _callHelper,
                          customBorder: const CircleBorder(),
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.phone_in_talk_rounded,
                              color: hasPhone
                                  ? Colors.white
                                  : const Color(0xFF94A3B8),
                              size: 21,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Chat button
                      Material(
                        color: const Color(0xFF3730A3),
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          onTap: _openChat,
                          customBorder: const CircleBorder(),
                          child: const SizedBox(
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.forum_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Segmented Control Pill Tabs ("Items & Route" | "Proof & Pay")
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTab == 0
                                  ? const Color(0xFF3730A3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'Items & Route',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _selectedTab == 0
                                    ? Colors.white
                                    : const Color(0xFF475569),
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedTab = 1),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _selectedTab == 1
                                  ? const Color(0xFF3730A3)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Proof & Pay',
                                  style: TextStyle(
                                    color: _selectedTab == 1
                                        ? Colors.white
                                        : const Color(0xFF475569),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13.5,
                                  ),
                                ),
                                if (_needsVerify) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF22C55E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Active Tab Body ──────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: _selectedTab == 0
                    ? _buildItemsAndRouteTab(task)
                    : _buildProofContent(task),
              ),

              // ── Subtle Footer Cancel Action (Original Design 4) ──────
              if (_canCancel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                  child: Center(
                    child: GestureDetector(
                      onTap: _cancelling ? null : _confirmCancel,
                      child: RichText(
                        text: TextSpan(
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13.5,
                          ),
                          children: [
                            const TextSpan(text: 'Need help? '),
                            TextSpan(
                              text: _cancelling
                                  ? 'Cancelling...'
                                  : 'Cancel Task',
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
