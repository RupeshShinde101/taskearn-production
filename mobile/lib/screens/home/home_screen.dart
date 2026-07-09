import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/task.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  String _cityName = 'Your City';
  List<Task> _suggestedTasks = [];

  // ── Fade-in ─────────────────────────────────────────────────────────────
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  // ── Platform stats (real-time) ───────────────────────────────────────────
  late AnimationController _statsCtrl;
  int _dispUsers  = 0;
  int _dispTasks  = 0;
  int _dispEarned = 0;
  int _tgtUsers   = 5200;
  int _tgtTasks   = 18500;
  int _tgtEarned  = 6200000; // ₹62 Lakh in rupees

  // ── How-it-works animated stepper ───────────────────────────────────────
  late AnimationController _stepCtrl;
  int _howTab     = 0; // 0 = poster, 1 = tasker
  int _activeStep = 0;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _statsCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));
    _statsCtrl.addListener(() {
      if (!mounted) return;
      final v = Curves.easeOut.transform(_statsCtrl.value);
      setState(() {
        _dispUsers  = (_tgtUsers  * v).toInt();
        _dispTasks  = (_tgtTasks  * v).toInt();
        _dispEarned = (_tgtEarned * v).toInt();
      });
    });

    _stepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800));
    _stepCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _activeStep = (_activeStep + 1) % 3);
        _stepCtrl.forward(from: 0);
      }
    });
    _stepCtrl.forward();

    _loadInitial();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _statsCtrl.dispose();
    _stepCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;
    if (location != null) {
      context.read<AuthProvider>()
          .updateUserLocation(location.latitude, location.longitude);
      _reverseGeocode(location.latitude, location.longitude);
    }
    context.read<NotificationProvider>().fetchNotifications();
    context.read<WalletProvider>().fetchWallet();
    _fetchSuggestedTasks();
    _fetchStats();
  }

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

  Future<void> _fetchSuggestedTasks() async {
    try {
      final data = await ApiService.get('/tasks',
          queryParams: {'limit': '8', 'status': 'open'});
      if (!mounted || data == null) return;
      final list = data is List ? data : (data['tasks'] as List? ?? []);
      final tasks = <Task>[];
      for (final item in list) {
        try {
          tasks.add(Task.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }
      if (mounted) setState(() => _suggestedTasks = tasks);
    } catch (_) {}
  }

  Future<void> _fetchStats() async {
    try {
      final data = await ApiService.get('/platform-stats');
      if (!mounted) return;
      if (data != null) {
        setState(() {
          _tgtUsers  = (data['users']          as num?)?.toInt() ?? _tgtUsers;
          _tgtTasks  = (data['completedTasks'] as num?)?.toInt() ?? _tgtTasks;
          _tgtEarned = (data['totalEarned']    as num?)?.toInt() ?? _tgtEarned;
        });
      }
    } catch (_) {}
    if (mounted) _statsCtrl.forward(from: 0);
  }

  String _fmtUsers(int v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K+';
    return '$v+';
  }

  String _fmtTasks(int v) {
    if (v >= 1000) return '${v ~/ 1000}K+';
    return '$v+';
  }

  String _fmtEarned(int v) {
    if (v >= 10000000) {
      final c = v / 10000000;
      return '₹${c.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}Cr+';
    }
    if (v >= 100000) {
      final l = v / 100000;
      return '₹${l.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')}L+';
    }
    if (v >= 1000) return '₹${v ~/ 1000}K+';
    return '₹$v+';
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
      backgroundColor: const Color(0xFFF1F2F8),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
        slivers: [
          // ── App Bar ──────────────────────────────────────────────────────
          SliverAppBar(
            floating: true,
            snap: true,
            backgroundColor: Colors.white,
            elevation: 0,
            titleSpacing: 0,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: GestureDetector(
                onTap: () => context.go('/profile'),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: avatarProvider,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: avatarProvider == null
                      ? Text(
                          firstName.isNotEmpty
                              ? firstName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
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
                  color: const Color(0xFFF1F2F8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      _cityName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down,
                        size: 16, color: AppColors.gray),
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
                      color: const Color(0xFFEEF0FF),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 14,
                        color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                        '₹${wallet.balance.balance.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                  ]),
                ),
              ),
              Stack(children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
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
                          color: AppColors.danger,
                          shape: BoxShape.circle),
                      child: Text(
                          '${notifications.unreadCount}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10)),
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

          SliverToBoxAdapter(child: _buildHero(firstName, auth.user?.gender)),
          SliverToBoxAdapter(child: _buildSearch()),
          SliverToBoxAdapter(child: _buildCategories()),
          if (_suggestedTasks.isNotEmpty)
            SliverToBoxAdapter(child: _buildAISuggested()),
          SliverToBoxAdapter(child: _buildStats()),
          SliverToBoxAdapter(child: _buildAbout()),
          SliverToBoxAdapter(child: _buildHowItWorks()),
          SliverToBoxAdapter(child: _buildEarnSection()),
          SliverToBoxAdapter(child: _buildWhyUs()),
          SliverToBoxAdapter(child: _buildTestimonials()),
          SliverToBoxAdapter(child: _buildCTA()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
        ),
      ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────────────
  Widget _buildHero(String firstName, String? gender) {
    final heroEmoji = gender == 'male' ? '👦' : gender == 'female' ? '👧' : '🧑';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badge + rating row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "India's Task App",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded,
                        color: Color(0xFFF59E0B), size: 13),
                    SizedBox(width: 3),
                    Text('4.9',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Content row: left text + right illustration
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hi $firstName! 👋',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.dark,
                        )),
                    const SizedBox(height: 10),
                    _bullet('✅', 'Earn money locally'),
                    const SizedBox(height: 4),
                    _bullet('⚡', 'Get tasks done fast'),
                    const SizedBox(height: 4),
                    _bullet('🔒', 'Secure payments'),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.push('/post-task'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B6B),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 42),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22)),
                          elevation: 0,
                          textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Post a Task'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.go('/browse'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 42),
                          side: const BorderSide(
                              color: AppColors.primary, width: 1.5),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22)),
                          foregroundColor: AppColors.primary,
                          textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                        ),
                        child: const Text('Find Tasks'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right: illustration with floating badges
              SizedBox(
                width: 110,
                height: 130,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ⚡ Fast badge (top left)
                    Positioned(
                      top: 0,
                      left: -10,
                      child: _floatingBadge('⚡', 'Fast'),
                    ),
                    // Character circle
                    Positioned(
                      top: 20,
                      left: 10,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F2F8),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.border, width: 2),
                        ),
                        child: Center(
                          child: Text(heroEmoji,
                              style: const TextStyle(fontSize: 40)),
                        ),
                      ),
                    ),
                    // ₹ Paid badge (bottom right)
                    Positioned(
                      bottom: 6,
                      right: -6,
                      child: _floatingBadge('₹', 'Paid'),
                    ),
                    // 📍 Near badge (bottom left)
                    Positioned(
                      bottom: 6,
                      left: -10,
                      child: _floatingBadge('📍', 'Near'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bullet(String icon, String text) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 6),
        Text(text,
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.dark,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _floatingBadge(String icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.10), blurRadius: 6)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dark)),
        ],
      ),
    );
  }

  // ── SEARCH ────────────────────────────────────────────────────────────────
  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8)
          ],
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            const Icon(Icons.search, color: AppColors.gray),
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
                          TextStyle(color: AppColors.gray, fontSize: 14),
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
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B),
                  borderRadius: BorderRadius.circular(10),
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
    const cats = <(String, String)>[
      ('🚛', 'Delivery'),
      ('🧹', 'Cleaning'),
      ('🔧', 'Repair'),
      ('🛒', 'Groceries'),
      ('🍳', 'Cooking'),
      ('👕', 'Laundry'),
      ('🏠', 'Household'),
      ('🛍️', 'Shopping'),
      ('⚡', 'Electrician'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cats.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.05,
        ),
        itemBuilder: (ctx, i) {
          final cat = cats[i];
          return GestureDetector(
            onTap: () => context.go('/browse'),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8)
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(cat.$1,
                      style: const TextStyle(fontSize: 30)),
                  const SizedBox(height: 6),
                  Text(cat.$2,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── AI SUGGESTED ──────────────────────────────────────────────────────────
  Widget _buildAISuggested() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, Color(0xFF7C3AED)],
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
              child: const Text('\u2728', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Suggested for You',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  Text('Based on your skills & location',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => context.go('/browse'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            itemCount: _suggestedTasks.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) => _buildSuggestedCard(_suggestedTasks[i]),
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

  Widget _buildSuggestedCard(Task task) {
    return GestureDetector(
      onTap: () => context.push('/task/${task.id}'),
      child: Container(
        width: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.06), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.success,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(16)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                      child: Text(_categoryEmoji(task.category),
                          style: const TextStyle(fontSize: 20))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(task.category,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                      if (task.address != null && task.address!.isNotEmpty)
                        Text(task.address!.split('\n').first,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('85%\nmatch',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                          height: 1.2)),
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
                      if (task.posterRating > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(task.posterRating.toStringAsFixed(1),
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.gray)),
                      ],
                    ]),
                    const Spacer(),
                    Row(children: [
                      Text('\u20b9${task.budget.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.success)),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => context.push('/task/${task.id}'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color: AppColors.success,
                              borderRadius: BorderRadius.circular(20)),
                          child: const Text('Apply',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700)),
                        ),
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

  // ── TESTIMONIALS ──────────────────────────────────────────────────────────
  Widget _buildTestimonials() {
    const testimonials = [
      (5.0, '"Got my house cleaned within 2 hours. Super fast and reliable!"',
          'Priya M.', 'Task Poster'),
      (4.5, '"Earning \u20b9800 doing deliveries. Flexible time, great platform."',
          'Rahul S.', 'Tasker'),
      (5.0, '"Found a reliable repair person within minutes. Highly recommended!"',
          'Anita K.', 'Task Poster'),
      (5.0, '"Secure payments, genuine tasks. Best platform for local work."',
          'Suresh P.', 'Tasker'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(children: [
            _QuoteIcon(),
            SizedBox(width: 10),
            Text('What People Say',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dark)),
          ]),
        ),
        SizedBox(
          height: 160,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            itemCount: testimonials.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final t = testimonials[i];
              return Container(
                width: 220,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border(
                      left: BorderSide(
                          color: i.isEven
                              ? AppColors.primary
                              : AppColors.success,
                          width: 3)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8)
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        5,
                        (s) => Icon(
                          s < t.$1.floor()
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFFF59E0B),
                          size: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                        child: Text(t.$2,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.gray,
                                height: 1.4))),
                    const SizedBox(height: 8),
                    Text(t.$3,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                    Text(t.$4,
                        style:
                            const TextStyle(fontSize: 10, color: AppColors.gray)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── STATS (real-time animated) ────────────────────────────────────────────
  Widget _buildStats() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
        _StatTile(
          icon: Icons.people_alt_rounded,
          iconColor: AppColors.primary,
          bgColor: const Color(0xFFEEF2FF),
          value: _fmtUsers(_dispUsers),
          label: 'Active Users',
        ),
        const SizedBox(width: 10),
        _StatTile(
          icon: Icons.check_circle_rounded,
          iconColor: AppColors.success,
          bgColor: const Color(0xFFECFDF5),
          value: _fmtTasks(_dispTasks),
          label: 'Tasks Done',
        ),
        const SizedBox(width: 10),
        _StatTile(
          icon: Icons.currency_rupee_rounded,
          iconColor: const Color(0xFFF59E0B),
          bgColor: const Color(0xFFFFFBEB),
          value: _fmtEarned(_dispEarned),
          label: 'Paid to Taskers',
        ),
      ]),
    );
  }

  // ── ABOUT ─────────────────────────────────────────────────────────────────
  Widget _buildAbout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          children: [
            Image.asset('assets/images/logo.png', width: 200),
            const SizedBox(height: 18),
            const Text(
              'What is Workmate4u?',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.dark,
                  letterSpacing: -0.3,
                  height: 1.2),
            ),
            const SizedBox(height: 6),
            Text(
              'Your local task marketplace',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary.withValues(alpha: 0.9)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Workmate4u connects people who need tasks done with skilled locals ready to help — from deliveries and cleaning to plumbing and tutoring. Post a task in seconds, get matched fast, and pay securely inside the app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: AppColors.gray, height: 1.7),
            ),
            const SizedBox(height: 20),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(icon: '🔒', label: 'Secure Payments'),
                _Pill(icon: '📍', label: 'Location-Based'),
                _Pill(icon: '⭐', label: 'Verified Taskers'),
                _Pill(icon: '⚡', label: 'Instant Matching'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── HOW IT WORKS ──────────────────────────────────────────────────────────
  Widget _buildHowItWorks() {
    const posterSteps = [
      (icon: '📝', title: 'Post Your Task',       desc: 'Describe what you need, set a budget & location. Takes less than 2 min.'),
      (icon: '🤝', title: 'Get Matched',           desc: 'Nearby skilled taskers see your job and apply. Pick the best fit.'),
      (icon: '✅', title: 'Done & Pay Securely',   desc: 'Task done? Verify and release payment instantly from your wallet.'),
    ];
    const taskerSteps = [
      (icon: '🔍', title: 'Browse Nearby Tasks',   desc: 'See tasks posted around you filtered by category and distance.'),
      (icon: '📲', title: 'Accept & Head Over',    desc: 'Accept a task, confirm with the poster, and head to the location.'),
      (icon: '💰', title: 'Complete & Get Paid',   desc: 'Submit proof of completion. Payment lands in your wallet instantly.'),
    ];

    final steps    = _howTab == 0 ? posterSteps : taskerSteps;
    final tabColor = _howTab == 0 ? AppColors.primary : AppColors.success;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
              icon: Icons.play_circle_outline_rounded,
              text: 'How Workmate4u Works'),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(children: [
              _HowTab(
                label: 'I need tasks done',
                icon: Icons.post_add_rounded,
                active: _howTab == 0,
                color: AppColors.primary,
                onTap: () {
                  setState(() { _howTab = 0; _activeStep = 0; });
                  _stepCtrl.forward(from: 0);
                },
              ),
              _HowTab(
                label: 'I want to earn',
                icon: Icons.work_outline_rounded,
                active: _howTab == 1,
                color: AppColors.success,
                onTap: () {
                  setState(() { _howTab = 1; _activeStep = 0; });
                  _stepCtrl.forward(from: 0);
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 3)),
              ],
            ),
            padding: const EdgeInsets.all(4),
            child: Column(
              children: List.generate(3, (i) {
                final step     = steps[i];
                final isActive = _activeStep == i;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut,
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: isActive ? tabColor.withValues(alpha: 0.07) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isActive ? tabColor.withValues(alpha: 0.3) : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isActive ? tabColor : tabColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(step.icon, style: const TextStyle(fontSize: 22))),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.title,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isActive ? tabColor : AppColors.dark)),
                          const SizedBox(height: 3),
                          Text(step.desc,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.gray, height: 1.45)),
                        ],
                      ),
                    ),
                    if (isActive)
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: tabColor, shape: BoxShape.circle)),
                  ]),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: _stepCtrl,
            builder: (_, __) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _stepCtrl.value,
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation(tabColor),
                minHeight: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── EARN BY CATEGORY ──────────────────────────────────────────────────────
  Widget _buildEarnSection() {
    const cats = [
      (icon: '🚚', cat: 'Delivery',    range: '₹150–₹400',   color: Color(0xFF3B82F6)),
      (icon: '🧹', cat: 'Cleaning',    range: '₹300–₹800',   color: Color(0xFF10B981)),
      (icon: '🔧', cat: 'Plumbing',    range: '₹400–₹1,200', color: Color(0xFFF59E0B)),
      (icon: '⚡', cat: 'Electrical',  range: '₹500–₹1,500', color: Color(0xFF8B5CF6)),
      (icon: '📦', cat: 'Moving',      range: '₹600–₹2,000', color: Color(0xFFEF4444)),
      (icon: '📚', cat: 'Tutoring',    range: '₹250–₹700',   color: Color(0xFF0EA5E9)),
      (icon: '🍳', cat: 'Cooking',     range: '₹300–₹900',   color: Color(0xFFEC4899)),
      (icon: '📸', cat: 'Photography', range: '₹500–₹2,500', color: Color(0xFFF97316)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
              icon: Icons.trending_up_rounded,
              text: 'How Much Can You Earn?'),
          const SizedBox(height: 4),
          const Text('Average earnings per task by category',
              style: TextStyle(fontSize: 12, color: AppColors.gray)),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final c = cats[i];
                return Container(
                  width: 112,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.color.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c.icon, style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(c.cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.color)),
                      Text(c.range, style: const TextStyle(fontSize: 10, color: AppColors.gray)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── WHY CHOOSE US ─────────────────────────────────────────────────────────
  Widget _buildWhyUs() {
    const features = [
      (badge: '01', icon: Icons.shield_rounded,        color: Color(0xFF6366F1), title: 'Safe & Secure', desc: 'Payments held safely until work is verified by the poster.'),
      (badge: '02', icon: Icons.bolt_rounded,          color: Color(0xFFF59E0B), title: 'Fast Matching', desc: 'Get offers within minutes of posting a task near you.'),
      (badge: '03', icon: Icons.star_rounded,          color: Color(0xFF10B981), title: 'Rated Taskers', desc: 'Every helper is rated after each completed job.'),
      (badge: '04', icon: Icons.support_agent_rounded, color: Color(0xFF0EA5E9), title: '24/7 Support',  desc: 'Our team is always here if anything goes wrong.'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
              icon: Icons.verified_rounded, text: 'Why Workmate4u?'),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.05,
            ),
            itemCount: 4,
            itemBuilder: (ctx, i) {
              final f = features[i];
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: f.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(f.icon, color: f.color, size: 22),
                        ),
                        Text(f.badge, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFEEF0F5))),
                      ],
                    ),
                    const Spacer(),
                    Text(f.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.dark)),
                    const SizedBox(height: 4),
                    Text(f.desc, style: const TextStyle(fontSize: 11, color: AppColors.gray, height: 1.45)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── CTA ───────────────────────────────────────────────────────────────────
  Widget _buildCTA() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        const Text('Ready to get started?',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Post a task or start earning as a helper today.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Colors.white70, fontSize: 13, height: 1.4)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push('/post-task'),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.white, width: 1.5),
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
              child: const Text('Post a Task',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => context.go('/browse'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                minimumSize: const Size(0, 44),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
              child: const Text('Browse Tasks',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _QuoteIcon extends StatelessWidget {
  const _QuoteIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
          color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
      child: const Center(
          child: Text('\u275D',
              style: TextStyle(color: Colors.white, fontSize: 16))),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final IconData icon;
  final String text;
  const _SectionHeading({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: AppColors.gradient),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 14, color: Colors.white),
      ),
      const SizedBox(width: 8),
      Text(text,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark)),
    ]);
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String value;
  final String label;

  const _StatTile({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 6),
          Text(value,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: iconColor)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppColors.gray)),
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String icon;
  final String label;
  const _Pill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _HowTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _HowTab({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : AppColors.gray),
              const SizedBox(width: 5),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : AppColors.gray)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
