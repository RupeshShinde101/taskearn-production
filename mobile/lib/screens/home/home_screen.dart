import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _usersCount  = 36;
  int _tasksCount  = 22;
  int _earnedTotal = 4000;
  String _cityName = 'Your City';

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
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

  Future<void> _fetchStats() async {
    try {
      final data = await ApiService.get('/platform-stats');
      if (!mounted || data == null) return;
      setState(() {
        _usersCount  = (data['users']          as num?)?.toInt() ?? _usersCount;
        _tasksCount  = (data['completedTasks'] as num?)?.toInt() ?? _tasksCount;
        _earnedTotal = (data['totalEarned']    as num?)?.toInt() ?? _earnedTotal;
      });
    } catch (_) {}
  }

  String _fmtEarned(int v) {
    if (v >= 10000000) return '₹${(v / 10000000).toStringAsFixed(0)}Cr+';
    if (v >= 100000)   return '₹${(v / 100000).toStringAsFixed(0)}L+';
    if (v >= 1000)     return '₹${v ~/ 1000}K+';
    return '₹$v+';
  }

  @override
  Widget build(BuildContext context) {
    final auth          = context.watch<AuthProvider>();
    final notifications = context.watch<NotificationProvider>();
    final wallet        = context.watch<WalletProvider>();
    final firstName     = auth.user?.name.split(' ').first ?? 'there';
    final isSuspended   = auth.user?.isSuspended == true;
    final avatarUrl     = auth.user?.avatar;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F8),
      body: CustomScrollView(
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
                  backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                      ? NetworkImage(avatarUrl)
                      : null,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  child: (avatarUrl == null || avatarUrl.isEmpty)
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

          SliverToBoxAdapter(child: _buildHero(firstName)),
          SliverToBoxAdapter(child: _buildStats()),
          SliverToBoxAdapter(child: _buildSearch()),
          SliverToBoxAdapter(child: _buildCategories()),
        ],
      ),
    );
  }

  // ── HERO ─────────────────────────────────────────────────────────────────
  Widget _buildHero(String firstName) {
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
                        child: const Center(
                          child: Text('🧑',
                              style: TextStyle(fontSize: 40)),
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

  // ── STATS ─────────────────────────────────────────────────────────────────
  Widget _buildStats() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _statItem(Icons.people_alt_rounded, AppColors.primary,
                '$_usersCount+', 'Active Users'),
            _vDivider(),
            _statItem(Icons.check_circle_rounded, AppColors.success,
                '$_tasksCount+', 'Tasks Done'),
            _vDivider(),
            _statItem(Icons.currency_rupee_rounded,
                const Color(0xFFF59E0B),
                _fmtEarned(_earnedTotal), 'Paid Out'),
          ],
        ),
      ),
    );
  }

  Widget _statItem(
      IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, color: AppColors.gray)),
        ],
      ),
    );
  }

  Widget _vDivider() {
    return Container(
        width: 1,
        color: AppColors.border,
        margin: const EdgeInsets.symmetric(vertical: 4));
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
}
