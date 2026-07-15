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
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';
import '../browse/browse_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _cityName = 'Your City';
  List<Task> _suggestedTasks = [];
  List<Task> _expiringTasks  = [];

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
    _fetchSuggestedTasks();
    _fetchExpiringTasks();
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

  Future<void> _fetchExpiringTasks() async {
    try {
      final data = await ApiService.get('/tasks',
          queryParams: {'limit': '8', 'sort': 'expiry'});
      if (!mounted || data == null) return;
      final list = data is List ? data : (data['tasks'] as List? ?? []);
      final tasks = <Task>[];
      for (final item in list) {
        try {
          tasks.add(Task.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }
      // Only keep tasks that still have expiresAt set and are expiring within 6 hours
      final cutoff = DateTime.now().add(const Duration(hours: 6));
      final expiring = tasks
          .where((t) => t.expiresAt != null && t.expiresAt!.isBefore(cutoff))
          .toList();
      if (mounted) setState(() => _expiringTasks = expiring);
    } catch (_) {}
  }

  Future<void> _fetchSuggestedTasks() async {
    try {
      final data = await ApiService.get('/tasks',
          queryParams: {'limit': '8'});
      if (!mounted || data == null) return;
      final list = data is List ? data : (data['tasks'] as List? ?? []);
      final tasks = <Task>[];
      for (final item in list) {
        try {
          tasks.add(Task.fromJson(item as Map<String, dynamic>));
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _suggestedTasks = tasks);
        // Cache into TaskProvider so getTaskDetail can find them when
        // the user taps Apply, avoiding a 'Task not found' error.
        context.read<TaskProvider>().cacheTasksForBrowse(tasks);
      }
    } catch (_) {}
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
          if (_expiringTasks.isNotEmpty)
            SliverToBoxAdapter(child: _buildExpiringSoon()),
          SliverToBoxAdapter(child: _buildTestimonials()),
          SliverToBoxAdapter(child: _buildCTA()),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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

  Widget _catTile((String, String) cat) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          BrowseScreen.jumpToCategory = cat.$2.toLowerCase();
          context.go('/browse');
        },
        child: AspectRatio(
          aspectRatio: 1.05,
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
                Text(cat.$1, style: const TextStyle(fontSize: 30)),
                const SizedBox(height: 6),
                Text(cat.$2,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.dark)),
              ],
            ),
          ),
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
              onTap: () => context.go('/browse'),
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
      onTap: () => context.push('/task/\${task.id}'),
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
                      Text('₹\${task.budget.toStringAsFixed(0)}',
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

  // ── CTA ───────────────────────────────────────────────────────────────────
  Widget _buildCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        children: [
          // ── Post a Task card ────────────────────────────────────────
          GestureDetector(
            onTap: () => context.push('/post-task'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.add_task_rounded,
                        color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Post a Task',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        SizedBox(height: 3),
                        Text('Get help from skilled helpers nearby',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                height: 1.3)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // ── Browse Tasks card ────────────────────────────────────────
          GestureDetector(
            onTap: () => context.go('/browse'),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.search_rounded,
                        color: Color(0xFF6366F1), size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Browse Tasks',
                            style: TextStyle(
                                color: Color(0xFF1E293B),
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3)),
                        SizedBox(height: 3),
                        Text('Find tasks matching your skills & earn',
                            style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                height: 1.3)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: Color(0xFF6366F1), size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
