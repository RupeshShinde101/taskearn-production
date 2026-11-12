import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';
import '../../widgets/hero_map_background.dart';
import '../../widgets/profile_mode_switch_dialog.dart';
import '../browse/browse_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<Task>? initialNearbyTasks;
  final List<Task>? initialSuggestedTasks;
  final Map<String, int>? initialTaskMatchPct;

  const HomeScreen({
    super.key,
    this.initialNearbyTasks,
    this.initialSuggestedTasks,
    this.initialTaskMatchPct,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cityName = 'Your City';
  List<Task> _suggestedTasks = [];
  Map<String, int> _taskMatchPct = {}; // taskId -> match percentage (60-100)
  List<Task> _expiringTasks  = [];
  List<Task> _nearbyTasks    = [];
  String _nearbyFilter       = 'all'; // 'all' | 'within_2km' | 'high_pay'
  bool _loadingNearby        = true;
  double? _userLat;
  double? _userLng;
  String? _acceptingTaskId;

  @override
  void initState() {
    super.initState();
    if (widget.initialNearbyTasks != null) {
      _nearbyTasks = widget.initialNearbyTasks!;
      _loadingNearby = false;
    }
    if (widget.initialSuggestedTasks != null) {
      _suggestedTasks = widget.initialSuggestedTasks!;
      _taskMatchPct = {
        for (final t in _suggestedTasks)
          t.id: widget.initialTaskMatchPct?[t.id] ?? 88,
      };
    }
    _loadInitial();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadInitial() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Data starts loading while popup may still be visible
      context.read<NotificationProvider>().fetchNotifications();
      context.read<WalletProvider>().fetchWallet();
      context.read<TaskProvider>().fetchMyTasks().catchError((_) {});
      if (widget.initialSuggestedTasks == null) {
        _fetchSuggestedTasks();
      }
      _fetchExpiringTasks();
      if (widget.initialNearbyTasks == null) {
        _fetchNearbyTasks();
      }
    });

    // GPS runs in parallel — only needed for city name + backend location update.
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (location != null) {
      _userLat = location.latitude;
      _userLng = location.longitude;
      context.read<AuthProvider>()
          .updateUserLocation(location.latitude, location.longitude);
      _reverseGeocode(location.latitude, location.longitude);
      if (widget.initialNearbyTasks == null) {
        _fetchNearbyTasks(lat: location.latitude, lng: location.longitude);
      }
    }
  }

  Future<void> _fetchNearbyTasks({double? lat, double? lng}) async {
    if (!mounted) return;
    if (_nearbyTasks.isEmpty) {
      setState(() => _loadingNearby = true);
    }
    try {
      final currentUserId =
          context.read<AuthProvider>().user?.id.toString();
      final effectiveLat = lat ?? _userLat;
      final effectiveLng = lng ?? _userLng;

      Future<List<Task>> queryTasks({bool withLocation = true}) async {
        final params = <String, String>{
          'limit': '15',
          if (withLocation && effectiveLat != null && effectiveLng != null) ...{
            'lat': '$effectiveLat',
            'lng': '$effectiveLng',
            'radius': '15',
          },
          if (currentUserId != null && currentUserId.isNotEmpty)
            'exclude_poster_id': currentUserId,
        };
        final data = await ApiService.get('/tasks', queryParams: params);
        if (data == null) return [];
        final list = data is List ? data : (data['tasks'] as List? ?? []);
        final parsed = <Task>[];
        for (final item in list) {
          try {
            final t = Task.fromJson(item as Map<String, dynamic>);
            final isOpen = t.status == 'posted' || t.status == 'open';
            final notMine = currentUserId == null ||
                currentUserId.isEmpty ||
                t.posterId != currentUserId;
            if (isOpen && t.helperId == null && !t.isHidden && notMine) {
              parsed.add(t);
            }
          } catch (_) {}
        }
        return parsed;
      }

      var nearby = await queryTasks(withLocation: true);
      if (nearby.isEmpty && effectiveLat != null && effectiveLng != null) {
        nearby = await queryTasks(withLocation: false);
      }

      nearby.sort((a, b) {
        final da = _taskDistanceKm(a);
        final db = _taskDistanceKm(b);
        if (da != null && db != null) return da.compareTo(db);
        if (da != null) return -1;
        if (db != null) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });

      final topNearby = nearby.take(12).toList();
      if (!mounted) return;
      setState(() {
        _nearbyTasks = topNearby;
        _loadingNearby = false;
      });
      if (topNearby.isNotEmpty) {
        context.read<TaskProvider>().cacheTasksForBrowse(topNearby);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingNearby = false);
    }
  }

  double? _taskDistanceKm(Task task) {
    if (task.distanceKm != null) return task.distanceKm;
    if (_userLat == null ||
        _userLng == null ||
        (task.latitude == 0 && task.longitude == 0)) {
      return null;
    }
    const r = 6371.0;
    final dLat = _degToRad(task.latitude - _userLat!);
    final dLng = _degToRad(task.longitude - _userLng!);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(_userLat!)) *
            math.cos(_degToRad(task.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  double _degToRad(double deg) => deg * math.pi / 180.0;

  Future<void> _reverseGeocode(double lat, double lng) async {
    try {
      final places = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 6));
      if (!mounted || places.isEmpty) return;
      final city = places.first.locality ??
          places.first.subAdministrativeArea ??
          places.first.administrativeArea;
      if (city != null && city.isNotEmpty) {
        setState(() => _cityName = city);
      }
    } catch (_) {}
  }

  Future<void> _fetchExpiringTasks() async {
    try {
      final currentUserId =
          context.read<AuthProvider>().user?.id.toString();
      final params = <String, String>{
        'limit': '8',
        'sort': 'expiry',
        if (currentUserId != null && currentUserId.isNotEmpty)
          'exclude_poster_id': currentUserId,
      };
      final data = await ApiService.get('/tasks', queryParams: params);
      if (!mounted || data == null) return;
      final list = data is List ? data : (data['tasks'] as List? ?? []);
      final tasks = <Task>[];
      for (final item in list) {
        try {
          tasks.add(Task.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }
      // Show tasks expiring within 5 hours (countdown timer shows urgency)
      final cutoff = DateTime.now().add(const Duration(hours: 5));
      final expiring = tasks
          .where((t) => t.expiresAt != null && t.expiresAt!.isBefore(cutoff))
          .toList();
      if (mounted) setState(() => _expiringTasks = expiring);
    } catch (_) {}
  }

  Future<void> _fetchSuggestedTasks() async {
    try {
      final auth = context.read<AuthProvider>();
      final currentUserId = auth.user?.id.toString();
      final userSkills = (auth.user?.skills ?? [])
          .map((s) => s.toLowerCase().trim())
          .where((s) => s.isNotEmpty)
          .toList();

      // Fetch more tasks so we have enough to rank
      final params = <String, String>{
        'limit': '20',
        if (currentUserId != null && currentUserId.isNotEmpty)
          'exclude_poster_id': currentUserId,
      };
      final data = await ApiService.get('/tasks', queryParams: params);
      if (!mounted || data == null) return;
      final list = data is List ? data : (data['tasks'] as List? ?? []);
      final allTasks = <Task>[];
      for (final item in list) {
        try {
          allTasks.add(Task.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }

      // Score each task by skill overlap
      final scored = <MapEntry<Task, int>>[];
      for (final task in allTasks) {
        final text =
            '${task.category} ${task.title}'.toLowerCase();
        if (userSkills.isEmpty) {
          // No skills set: show all with base score
          scored.add(MapEntry(task, 0));
        } else {
          int hits = 0;
          for (final skill in userSkills) {
            if (text.contains(skill)) hits++;
          }
          // Only include tasks that match at least one skill
          if (hits > 0) scored.add(MapEntry(task, hits));
        }
      }

      // Sort by score descending, take top 8
      scored.sort((a, b) => b.value.compareTo(a.value));
      final top = scored.take(8).toList();

      // Compute match percentages
      final pctMap = <String, int>{};
      for (final e in top) {
        if (userSkills.isEmpty) {
          pctMap[e.key.id] = 75; // generic suggestion
        } else {
          // Normalize to 60-100% range
          final pct = (60 + (e.value / userSkills.length * 40))
              .round()
              .clamp(60, 100);
          pctMap[e.key.id] = pct;
        }
      }

      if (mounted) {
        setState(() {
          _suggestedTasks = top.map((e) => e.key).toList();
          _taskMatchPct = pctMap;
        });
        context.read<TaskProvider>().cacheTasksForBrowse(_suggestedTasks);
      }
    } catch (_) {}
  }

  Future<void> _refreshHome() async {
    await Future.wait([
      context.read<NotificationProvider>().fetchNotifications(),
      context.read<WalletProvider>().fetchWallet(),
      _fetchSuggestedTasks(),
      _fetchExpiringTasks(),
      _fetchNearbyTasks(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth          = context.watch<AuthProvider>();
    final notifications = context.watch<NotificationProvider>();
    final wallet        = context.watch<WalletProvider>();
    final firstName     = auth.user?.name.split(' ').first ?? 'there';
    final isSuspended   = auth.user?.isSuspended == true;
    final avatarProvider = avatarImage(auth.user?.avatar);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      body: RefreshIndicator(
        color: const Color(0xFF2563EB),
        onRefresh: _refreshHome,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: const Color(0xFFF4F8FF).withValues(alpha: 0.94),
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            titleSpacing: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: GestureDetector(
                onTap: () => context.go('/profile'),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: avatarProvider,
                  backgroundColor: const Color(0xFFDCEBFF),
                  child: avatarProvider == null
                      ? Text(
                          firstName.isNotEmpty
                              ? firstName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            title: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE5EDF7)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B4073).withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 14, color: Color(0xFF2563EB)),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _cityName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF102A56),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 16, color: Color(0xFF71819A)),
                  ],
                ),
              ),
            ),
            actions: [
              GestureDetector(
                onTap: () => context.push('/wallet'),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFC5DCFF)),
                  ),
                  child: Row(children: [
                    const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 14,
                        color: Color(0xFF2563EB)),
                    const SizedBox(width: 4),
                    Text(
                        '₹${wallet.balance.balance.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF102A56))),
                  ]),
                ),
              ),
              Stack(children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined,
                      color: Color(0xFF102A56)),
                  onPressed: () => context.push('/notifications'),
                ),
                if (notifications.unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle),
                      child: Text(
                          '${notifications.unreadCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ]),
            ],
          ),

          // ── Suspension banner ─────────────────────────────────────────
          if (isSuspended)
            SliverToBoxAdapter(
              child: Builder(builder: (ctx) {
                final until = auth.user?.suspendedUntil;
                final msg = (until != null &&
                        until.isAfter(DateTime.now()))
                    ? 'Account suspended until ${until.day}/${until.month}. You cannot accept tasks.'
                    : 'Your account is suspended. Contact support.';
                return Container(
                  margin:
                      const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                      color: AppColors.danger
                          .withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.danger
                              .withValues(alpha: 0.3))),
                  child: Row(children: [
                    const Icon(Icons.block,
                        color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(msg,
                            style: const TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                                height: 1.4))),
                  ]),
                );
              }),
            ),

          SliverToBoxAdapter(
            child: _buildHero(
              firstName,
              auth.user?.gender ?? StorageService.getGender(),
            ),
          ),
          SliverToBoxAdapter(child: _buildSearch()),
          SliverToBoxAdapter(child: _buildCategories()),
          SliverToBoxAdapter(child: _buildTrustedExpertsBanner()),
          if (_suggestedTasks.isNotEmpty)
            SliverToBoxAdapter(child: _buildAISuggested()),
          if (_expiringTasks.isNotEmpty)
            SliverToBoxAdapter(child: _buildExpiringSoon()),
          SliverToBoxAdapter(child: _buildLiveNearbyTasksFeed()),
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.of(context).padding.bottom + 16,
            ),
          ),
        ],
        ),
      ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────────────
  Widget _buildHero(String firstName, String? gender) {
    final avatarAsset = heroAvatarAssetForGender(gender);
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFFAFCFF),
                  Color(0xFFF4F8FF),
                ],
              ),
            ),
          ),
        ),
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 262,
          child: IgnorePointer(
            child: CustomPaint(
              painter: HeroMapBackgroundPainter(
                fadeBottom: true,
                beaconTop: 50,
                beaconRightOffset: 138,
                beaconLeftMinFactor: 0.56,
                mapCenterYFactor: 0.48,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                right: 0,
                bottom: 0,
                width: 152,
                height: 188,
                child: IgnorePointer(
                  child: Image.asset(
                    avatarAsset,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                    errorBuilder: (_, __, ___) =>
                        const SizedBox(width: 152, height: 188),
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5EDF7)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1B4073).withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded,
                          color: Color(0xFFF59E0B), size: 15),
                      SizedBox(width: 4),
                      Text('4.9',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF102A56))),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 6,
                top: 38,
                child: IgnorePointer(child: _floatingBadge('⚡', 'Fast')),
              ),
              Positioned(
                right: 4,
                bottom: 8,
                child: IgnorePointer(child: _paidBadge()),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 146, bottom: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC5DCFF)),
                      ),
                      child: const Text(
                        "India's Task App",
                        style: TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Hi $firstName! 👋',
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF102A56),
                            letterSpacing: -0.5,
                          )),
                    ),
                    const SizedBox(height: 10),
                    _bullet(
                      Icons.check_circle_rounded,
                      const Color(0xFF2563EB),
                      'Earn money locally',
                    ),
                    const SizedBox(height: 6),
                    _bullet(
                      Icons.bolt_rounded,
                      const Color(0xFFF59E0B),
                      'Get tasks done fast',
                    ),
                    const SizedBox(height: 6),
                    _bullet(
                      Icons.verified_user_rounded,
                      const Color(0xFF2563EB),
                      'Secure payments',
                    ),
                    const SizedBox(height: 14),
                    // Compact left-aligned Primary CTA button
                    Container(
                      width: double.infinity,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF347BFA), Color(0xFF0B63F6)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB)
                                .withValues(alpha: 0.24),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          final auth = context.read<AuthProvider>();
                          if (!auth.isPosterMode) {
                            final switched = await showProfileModeSwitchDialog(
                              context,
                              targetMode: 'poster',
                              title: 'Switch to Poster Profile',
                              message:
                                  'Posting tasks requires a Poster profile. Would you like to switch to Poster mode to post this task?',
                              actionLabel: 'Switch to Poster & Continue',
                            );
                            if (switched != true) return;
                          }
                          if (!mounted) return;
                          context.push('/post-task');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22)),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Post a Task'),
                              SizedBox(width: 5),
                              Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Compact left-aligned Secondary CTA button
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => context.go('/browse'),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Colors.white,
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          side: const BorderSide(
                              color: Color(0xFF2563EB), width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22)),
                          foregroundColor: const Color(0xFF2563EB),
                          textStyle: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Find Tasks'),
                              SizedBox(width: 5),
                              Icon(Icons.arrow_forward_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bullet(IconData icon, Color iconColor, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              color: Color(0xFF52627A),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _floatingBadge(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4073).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF102A56))),
        ],
      ),
    );
  }

  Widget _paidBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4073).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF8EF),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text(
              '₹',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF15803D),
              ),
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'Paid',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF102A56),
            ),
          ),
        ],
      ),
    );
  }

  // ── SEARCH ────────────────────────────────────────────────────────────────
  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5EDF7)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B4073).withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search_rounded, color: Color(0xFF71819A)),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => context.go('/browse'),
                child: const AbsorbPointer(
                  child: TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      hintText: 'Search tasks, categories...',
                      border: InputBorder.none,
                      hintStyle:
                          TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => context.go('/browse'),
              child: Container(
                margin: const EdgeInsets.all(6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF347BFA), Color(0xFF0B63F6)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Search',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── CATEGORIES ────────────────────────────────────────────────────────────
  Widget _buildCategories() {
    const cats = <(String, String, Color)>[
      ('🚛', 'Delivery', Color(0xFFEAF2FF)),
      ('🧹', 'Cleaning', Color(0xFFFFF5DF)),
      ('🔧', 'Repair', Color(0xFFEDF4FD)),
      ('🛒', 'Groceries', Color(0xFFFDF0F6)),
      ('🍳', 'Cooking', Color(0xFFFFF8E1)),
      ('👕', 'Laundry', Color(0xFFEAF2FF)),
      ('🏠', 'Household', Color(0xFFFFF2ED)),
      ('🛍️', 'Shopping', Color(0xFFEAF8EF)),
      ('⚡', 'Electrician', Color(0xFFFEFCE8)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            _catTile(cats[0]), const SizedBox(width: 10),
            _catTile(cats[1]), const SizedBox(width: 10),
            _catTile(cats[2]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _catTile(cats[3]), const SizedBox(width: 10),
            _catTile(cats[4]), const SizedBox(width: 10),
            _catTile(cats[5]),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _catTile(cats[6]), const SizedBox(width: 10),
            _catTile(cats[7]), const SizedBox(width: 10),
            _catTile(cats[8]),
          ]),
        ],
      ),
    );
  }

  Widget _catTile((String, String, Color) cat) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          BrowseScreen.jumpToCategory = cat.$2.toLowerCase();
          context.go('/browse');
        },
        child: AspectRatio(
          aspectRatio: 1.04,
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE5EDF7)),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B4073).withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cat.$3,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(cat.$1, style: const TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        cat.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF102A56),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 13,
                        color: Color(0xFF71819A),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── FEATURED TRUST BANNER ─────────────────────────────────────────────────
  Widget _buildTrustedExpertsBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFEAF2FF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4073).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          children: [
            Positioned(
              right: -4,
              bottom: 0,
              width: 242,
              height: 77,
              child: IgnorePointer(
                child: ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                    ],
                    stops: [0.0, 0.34, 1.0],
                  ).createShader(rect),
                  blendMode: BlendMode.dstIn,
                  child: Image.asset(
                    'assets/images/cat_3d_other_skyline.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomRight,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
            const Positioned(
              right: 52,
              top: 10,
              child: IgnorePointer(
                child: Icon(
                  Icons.location_on_rounded,
                  size: 28,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 132, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GET THINGS DONE',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: Color(0xFF52627A),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Trusted local experts',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF102A56),
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Quick. Safe. Near you.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF52627A),
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

  // ── EXPIRING SOON ─────────────────────────────────────────────
  Widget _buildExpiringSoon() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.timer_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expiring Soon',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('Act fast before these tasks expire!',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              //Added onTap to navigate to browse screen with expiring tasks filtered (by sakshi on 2026/07/22)
              onTap: () {
                BrowseScreen.jumpToExpirySoon = true;
                context.go('/browse');
              },
              //onTap: () => context.go('/browse'),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white54),
                ),
                child: const Text('See all',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
        SizedBox(
          height: 170,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            itemCount: _expiringTasks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) =>
                _buildExpiringCard(_expiringTasks[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildExpiringCard(Task task) {
    final expires = task.expiresAt;
    final diff = expires != null
        ? expires.difference(DateTime.now())
        : const Duration(hours: 1);
    final hours = diff.inHours;
    final mins  = diff.inMinutes.remainder(60);
    final timeLabel = hours > 0 ? '${hours}h ${mins}m left' : '${diff.inMinutes}m left';
    final urgentColor = hours < 2
        ? const Color(0xFFEF4444)
        : hours < 4
            ? const Color(0xFFF97316)
            : const Color(0xFFF59E0B);

    return GestureDetector(
      onTap: () => context.push('/task/${task.id}'),
      child: Container(
        width: 200,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: urgentColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Text(_categoryEmoji(task.category),
                    style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(task.category,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_rounded,
                        size: 10, color: urgentColor),
                    const SizedBox(width: 2),
                    Text(timeLabel,
                        style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                            color: urgentColor,
                            height: 1.2)),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(task.title,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      const Icon(Icons.person_outline,
                          size: 12, color: AppColors.gray),
                      const SizedBox(width: 3),
                      Expanded(
                          child: Text(task.posterName,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.gray),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                    ]),
                    const Spacer(),
                    Row(children: [
                      Text('₹${task.budget.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: urgentColor)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: urgentColor,
                            borderRadius: BorderRadius.circular(14)),
                        child: const Text('Apply',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI SUGGESTED ──────────────────────────────────────────────────────────
  String _buildSuggestedSubtitle(List<String> rawSkills) {
    final cleaned = rawSkills
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => s[0].toUpperCase() + (s.length > 1 ? s.substring(1) : ''))
        .toList();
    if (cleaned.isEmpty) return 'Tailored picks based on your location';
    if (cleaned.length == 1) return 'Matched to your ${cleaned.first} skill';
    return 'Matched to your ${cleaned[0]} & ${cleaned[1]} skills';
  }

  Widget _buildAISuggested() {
    final userSkills = context.watch<AuthProvider>().user?.skills ?? [];
    final subtitle = _buildSuggestedSubtitle(userSkills);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F6BFF), Color(0xFF2563EB)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Suggested for You',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                        letterSpacing: -0.35,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  if (userSkills.isNotEmpty) {
                    BrowseScreen.jumpToSearch = userSkills.first;
                  }
                  context.go('/browse');
                },
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Color(0xFF2563EB),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < _suggestedTasks.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  _buildSuggestedCard(
                    _suggestedTasks[i],
                    _taskMatchPct[_suggestedTasks[i].id] ?? 75,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _categoryEmoji(String category) {
    final c = category.toLowerCase();
    if (c.contains('deliver')) return '\u{1F69B}';
    if (c.contains('clean')) return '\u{1F9F9}';
    if (c.contains('repair') || c.contains('fix')) return '\u{1F527}';
    if (c.contains('tutor') || c.contains('teach')) return '\u{1F4DA}';
    if (c.contains('mov') || c.contains('shift')) return '\u{1F4E6}';
    if (c.contains('cook') || c.contains('food')) return '\u{1F373}';
    if (c.contains('electric')) return '\u26A1';
    if (c.contains('shop') || c.contains('groceri')) return '\u{1F6D2}';
    if (c.contains('laundry')) return '\u{1F455}';
    return '\u{1F6E0}';
  }

  (String, Color, IconData, Color) _categoryBannerVisuals(String category) {
    final c = category.toLowerCase().trim();
    if (c.contains('deliver') ||
        c.contains('mov') ||
        c.contains('shift') ||
        c.contains('transport') ||
        c.contains('pickup')) {
      return (
        'assets/images/cat_delivery.jpg',
        const Color(0xFFFFF4E6),
        Icons.local_shipping_rounded,
        const Color(0xFFEA580C),
      );
    }
    if (c.contains('grocer') ||
        c.contains('shop') ||
        c.contains('errand') ||
        c.contains('queue') ||
        c.contains('event')) {
      return (
        'assets/images/cat_shopping.jpg',
        const Color(0xFFE9FAFD),
        Icons.shopping_bag_rounded,
        const Color(0xFF0891B2),
      );
    }
    if (c.contains('clean') ||
        c.contains('cook') ||
        c.contains('laundry') ||
        c.contains('house') ||
        c.contains('garden') ||
        c.contains('beauty')) {
      return (
        'assets/images/cat_home.jpg',
        const Color(0xFFEAF3FF),
        Icons.home_rounded,
        const Color(0xFF2563EB),
      );
    }
    if (c.contains('repair') ||
        c.contains('electric') ||
        c.contains('plumb') ||
        c.contains('carpen') ||
        c.contains('vehicle') ||
        c.contains('paint')) {
      return (
        'assets/images/cat_repair.jpg',
        const Color(0xFFEEF2FF),
        Icons.build_rounded,
        const Color(0xFF4F46E5),
      );
    }
    if (c.contains('care') ||
        c.contains('pet') ||
        c.contains('child') ||
        c.contains('elder')) {
      return (
        'assets/images/cat_care.jpg',
        const Color(0xFFFFEEF3),
        Icons.favorite_rounded,
        const Color(0xFFE11D48),
      );
    }
    if (c.contains('freelanc') ||
        c.contains('tutor') ||
        c.contains('tech') ||
        c.contains('data') ||
        c.contains('design') ||
        c.contains('web') ||
        c.contains('video') ||
        c.contains('market') ||
        c.contains('business') ||
        c.contains('photo')) {
      return (
        'assets/images/cat_professional.jpg',
        const Color(0xFFECFCF4),
        Icons.laptop_mac_rounded,
        const Color(0xFF059669),
      );
    }
    return (
      'assets/images/cat_other.jpg',
      const Color(0xFFF1F5F9),
      Icons.task_alt_rounded,
      const Color(0xFF2563EB),
    );
  }

  Widget _buildSuggestedCard(Task task, int matchPct) {
    final banner = _categoryBannerVisuals(task.category);
    final distKm = _taskDistanceKm(task);
    final distLabel = _formatDistanceBadge(distKm, task);
    final timeLabel = _formatTimeBadge(task);
    final posterLabel =
        task.posterName.trim().isNotEmpty ? task.posterName.trim() : 'Verified Poster';
    final posterAvatarProvider = avatarImage(task.posterAvatar);
    final isAccepting = _acceptingTaskId == task.id;
    final categoryLabel =
        task.category.trim().isNotEmpty ? task.category.trim().toUpperCase() : 'TASK';

    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4073).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/task/${task.id}'),
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Option 1: Top Photo-Banner Image Header ───────────────────
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                child: SizedBox(
                  height: 118,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(color: banner.$2),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          child: Image.asset(
                            banner.$1,
                            fit: BoxFit.contain,
                            color: banner.$2,
                            colorBlendMode: BlendMode.modulate,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(
                                banner.$3,
                                color: banner.$4,
                                size: 44,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 46,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0x470F172A),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9F9EB)
                                .withValues(alpha: 0.95),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF0F172A)
                                    .withValues(alpha: 0.08),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                size: 11.5,
                                color: Color(0xFF059669),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$matchPct% Match',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF047857),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 10,
                        bottom: 9,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 170),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A)
                                  .withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16),
                              ),
                            ),
                            child: Text(
                              categoryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.25,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 18,
                            height: 18,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDCEBFF),
                              shape: BoxShape.circle,
                            ),
                            clipBehavior: Clip.antiAlias,
                            alignment: Alignment.center,
                            child: posterAvatarProvider != null
                                ? Image(
                                    image: posterAvatarProvider,
                                    width: 18,
                                    height: 18,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Text(
                                      posterLabel[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2563EB),
                                      ),
                                    ),
                                  )
                                : Text(
                                    posterLabel[0].toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              posterLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                          if (task.posterRating > 0) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Text(
                                '·',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.star_rounded,
                              size: 13.5,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              task.posterRating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ],
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              '·',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              distLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      const SizedBox(height: 11),
                      Container(
                        height: 1,
                        color: const Color(0xFFEEF3FA),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '\u20b9${task.budget.toStringAsFixed(0)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    timeLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: isAccepting
                                ? () {}
                                : () => _handleAcceptNearbyTask(task),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              constraints: const BoxConstraints(
                                minWidth: 74,
                                minHeight: 36,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF10B981)
                                        .withValues(alpha: 0.24),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: isAccepting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Accept',
                                      maxLines: 1,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.1,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── LIVE NEARBY TASKS FEED ────────────────────────────────────────────────
  List<Task> get _filteredNearbyTasks {
    final Iterable<Task> source = switch (_nearbyFilter) {
      'within_2km' => _nearbyTasks.where((t) {
          final km = _taskDistanceKm(t);
          return km != null && km <= 2.0;
        }),
      'high_pay' => _nearbyTasks.where((t) => t.budget >= 300),
      _ => _nearbyTasks,
    };
    return source.take(6).toList();
  }

  Widget _buildLiveNearbyTasksFeed() {
    final filteredTasks = _filteredNearbyTasks;
    final allLabel = _nearbyTasks.isNotEmpty
        ? 'All (${_nearbyTasks.length})'
        : 'All';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Live Nearby Tasks Feed',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.35,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => context.go('/browse'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(width: 3),
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 14,
                      color: Color(0xFF2563EB),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildNearbyFilterChip('all', allLabel),
                const SizedBox(width: 8),
                _buildNearbyFilterChip('within_2km', 'Within 2 km'),
                const SizedBox(width: 8),
                _buildNearbyFilterChip('high_pay', '\u20b9300+'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_loadingNearby && _nearbyTasks.isEmpty) ...[
            _buildNearbySkeletonCard(),
            const SizedBox(height: 10),
            _buildNearbySkeletonCard(),
          ] else if (_nearbyTasks.isEmpty)
            _buildNearbyEmptyCard()
          else if (filteredTasks.isEmpty)
            _buildNearbyFilteredEmptyCard()
          else
            Column(
              children: filteredTasks.map(_buildNearbyTaskCard).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildNearbyFilterChip(String id, String label) {
    final selected = _nearbyFilter == id;
    return GestureDetector(
      onTap: () {
        if (_nearbyFilter != id) {
          setState(() => _nearbyFilter = id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? const Color(0xFF2563EB)
                : const Color(0xFFDCE6F2),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: const Color(0xFF2563EB).withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF334155),
          ),
        ),
      ),
    );
  }

  Widget _buildNearbyFilteredEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EDF7)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'No nearby tasks match this filter',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => setState(() => _nearbyFilter = 'all'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Show all',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2563EB),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyTaskCard(Task task) {
    final banner = _categoryBannerVisuals(task.category);
    final distKm = _taskDistanceKm(task);
    final distLabel = _formatDistanceBadge(distKm, task);
    final timeLabel = _formatTimeBadge(task);
    final isAccepting = _acceptingTaskId == task.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4073).withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.push('/task/${task.id}'),
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: banner.$2,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFE5EDF7)),
                    ),
                    padding: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    child: Image.asset(
                      banner.$1,
                      fit: BoxFit.contain,
                      color: banner.$2,
                      colorBlendMode: BlendMode.modulate,
                      errorBuilder: (_, __, ___) => Icon(
                        banner.$3,
                        color: banner.$4,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          _nearbyMetaPill(
                            '₹${task.budget.toStringAsFixed(0)}',
                            isPrice: true,
                          ),
                          _nearbyMetaPill(distLabel),
                          _nearbyMetaPill(timeLabel),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: isAccepting
                      ? () {}
                      : () => _handleAcceptNearbyTask(task),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minWidth: 68, minHeight: 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color:
                              const Color(0xFF10B981).withValues(alpha: 0.24),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: isAccepting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Accept',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.1,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nearbyMetaPill(String text, {bool isPrice = false}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 3),
      decoration: BoxDecoration(
        color: isPrice ? const Color(0xFFEEF3FA) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: isPrice ? FontWeight.w800 : FontWeight.w600,
          color: isPrice ? const Color(0xFF0F172A) : const Color(0xFF475569),
        ),
      ),
    );
  }

  Widget _buildNearbySkeletonCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EDF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.72,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    Container(
                      height: 20,
                      width: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Container(
                      height: 20,
                      width: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Container(
                      height: 20,
                      width: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 66,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE2F7EF),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyEmptyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5EDF7)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4073).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: Color(0xFF2563EB),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No open tasks near you yet',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Explore all city tasks or refresh shortly',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => context.go('/browse'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Browse',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDistanceBadge(double? km, Task task) {
    if (km != null) {
      if (km < 1.0) {
        return '${(km * 1000).round().clamp(50, 999)} m';
      }
      return '${km.toStringAsFixed(1)} km';
    }
    final city = task.city?.trim() ?? '';
    if (city.isNotEmpty) return city;
    final addr = task.address?.trim() ?? '';
    if (addr.isNotEmpty) {
      return addr.split(RegExp(r'[\n,]')).first.trim();
    }
    return 'Nearby';
  }

  String _formatTimeBadge(Task task) {
    final now = DateTime.now();
    if (task.expiresAt != null) {
      final left = task.expiresAt!.difference(now);
      if (!left.isNegative) {
        if (left.inMinutes < 60) {
          return '${left.inMinutes.clamp(1, 59)} mins';
        }
        if (left.inHours < 24) {
          return '${left.inHours}h left';
        }
      }
    }
    final age = now.difference(task.createdAt.toLocal());
    if (age.isNegative || age.inMinutes < 2) return 'Just now';
    if (age.inMinutes < 60) return '${age.inMinutes} mins';
    if (age.inHours < 24) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }

  Future<void> _handleAcceptNearbyTask(Task task) async {
    final auth = context.read<AuthProvider>();
    if (auth.user?.isSuspended == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is suspended. You cannot accept tasks.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final taskProvider = context.read<TaskProvider>();
    if (taskProvider.hasActiveAcceptedTask) {
      final active = taskProvider.activeAcceptedTask;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Complete your active task before accepting another.'),
          action: active != null
              ? SnackBarAction(
                  label: 'View Active',
                  textColor: Colors.white,
                  onPressed: () {
                    if (mounted) context.push('/task-in-progress/${active.id}');
                  },
                )
              : null,
        ),
      );
      return;
    }

    if (!auth.isHelperMode) {
      final switched = await showProfileModeSwitchDialog(
        context,
        targetMode: 'helper',
        title: 'Switch to Helper Profile',
        message:
            'Accepting tasks requires switching to your Helper profile. Would you like to switch to Helper mode now to accept this task?',
        actionLabel: 'Switch to Helper & Accept',
      );
      if (switched != true || !mounted) return;
    }

    if (!(auth.user?.isKycVerified ?? false)) {
      showDialog<void>(
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

    setState(() => _acceptingTaskId = task.id);
    taskProvider.cacheTasksForBrowse([task, ..._nearbyTasks, ..._suggestedTasks]);
    final ok = await taskProvider.acceptTask(task.id);
    if (!mounted) return;
    setState(() => _acceptingTaskId = null);

    if (ok) {
      context.go('/task-in-progress/${task.id}');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(taskProvider.error ?? 'Failed to accept task'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }
}
