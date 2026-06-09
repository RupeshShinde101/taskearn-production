import 'package:flutter/material.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
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
    }
    context.read<NotificationProvider>().fetchNotifications();
    context.read<WalletProvider>().fetchWallet();
    _fetchStats();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF1F2F8),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            // ── App Bar ────────────────────────────────────────────────────
            SliverAppBar(
              floating: true,
              snap: true,
              backgroundColor: Colors.white,
              elevation: 0,
              title: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: AppColors.gradient),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.handshake_rounded,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 8),
                const GradientText('Workmate4u',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ]),
              actions: [
                GestureDetector(
                  onTap: () => context.push('/wallet'),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                        color: AppColors.light,
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('₹${wallet.balance.balance.toStringAsFixed(0)}',
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
                            color: AppColors.danger, shape: BoxShape.circle),
                        child: Text('${notifications.unreadCount}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ),
                ]),
              ],
            ),

            // ── Suspension banner ──────────────────────────────────────────
            if (isSuspended)
              SliverToBoxAdapter(
                child: Builder(builder: (ctx) {
                  final until = auth.user?.suspendedUntil;
                  final msg = (until != null && until.isAfter(DateTime.now()))
                      ? 'Account suspended until ${until.day}/${until.month}. You cannot accept tasks.'
                      : 'Your account is suspended. Contact support.';
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3))),
                    child: Row(children: [
                      const Icon(Icons.block, color: AppColors.danger, size: 18),
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
            SliverToBoxAdapter(child: _buildAbout()),
            SliverToBoxAdapter(child: _buildHowItWorks()),
            SliverToBoxAdapter(child: _buildEarnSection()),
            SliverToBoxAdapter(child: _buildWhyUs()),
            SliverToBoxAdapter(child: _buildTestimonials()),
            SliverToBoxAdapter(child: _buildCTA()),
          ],
        ),
      ),
    );
  }

  // ── HERO ──────────────────────────────────────────────────────────────────
  Widget _buildHero(String firstName) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(children: [
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 40,
            bottom: -50,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.bolt_rounded, color: Colors.amber, size: 14),
                    SizedBox(width: 4),
                    Text("India's Local Task App",
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(height: 14),
                Text('Hi $firstName 👋',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        height: 1.1)),
                const SizedBox(height: 8),
                const Text(
                  'Post tasks.\nEarn money.\nAnywhere.',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.55),
                ),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/post-task'),
                      icon: const Icon(Icons.add_circle_outline, size: 16),
                      label: const Text('Post a Task'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF4F46E5),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/browse'),
                      icon: const Icon(Icons.search,
                          size: 16, color: Colors.white),
                      label: const Text('Find Tasks',
                          style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        side: const BorderSide(
                            color: Colors.white38, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22)),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ]),
      ),
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

  // ── ABOUT (centered) ──────────────────────────────────────────────────────
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
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: AppColors.gradient),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: const Icon(Icons.handshake_rounded,
                  color: Colors.white, size: 32),
            ),
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
              style: TextStyle(
                  fontSize: 13.5, color: AppColors.gray, height: 1.7),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: const [
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

  // ── HOW IT WORKS (animated auto-stepping) ─────────────────────────────────
  Widget _buildHowItWorks() {
    const posterSteps = [
      (
        icon: '📝',
        title: 'Post Your Task',
        desc:
            'Describe what you need, set a budget & location. Takes less than 2 min.',
      ),
      (
        icon: '🤝',
        title: 'Get Matched',
        desc:
            'Nearby skilled taskers see your job and apply. Pick the best fit.',
      ),
      (
        icon: '✅',
        title: 'Done & Pay Securely',
        desc:
            'Task done? Verify and release payment instantly from your wallet.',
      ),
    ];
    const taskerSteps = [
      (
        icon: '🔍',
        title: 'Browse Nearby Tasks',
        desc:
            'See tasks posted around you filtered by category and distance.',
      ),
      (
        icon: '📲',
        title: 'Accept & Head Over',
        desc: 'Accept a task, confirm with the poster, and head to the location.',
      ),
      (
        icon: '💰',
        title: 'Complete & Get Paid',
        desc:
            'Submit proof of completion. Payment lands in your wallet instantly.',
      ),
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

          // ── Tab toggle ────────────────────────────────────────────────
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
                  setState(() {
                    _howTab     = 0;
                    _activeStep = 0;
                  });
                  _stepCtrl.forward(from: 0);
                },
              ),
              _HowTab(
                label: 'I want to earn',
                icon: Icons.work_outline_rounded,
                active: _howTab == 1,
                color: AppColors.success,
                onTap: () {
                  setState(() {
                    _howTab     = 1;
                    _activeStep = 0;
                  });
                  _stepCtrl.forward(from: 0);
                },
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Step cards (auto-animated) ────────────────────────────────
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: isActive
                        ? tabColor.withValues(alpha: 0.07)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isActive
                          ? tabColor.withValues(alpha: 0.3)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: isActive
                            ? tabColor
                            : tabColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                          child: Text(step.icon,
                              style: const TextStyle(fontSize: 22))),
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
                                  color:
                                      isActive ? tabColor : AppColors.dark)),
                          const SizedBox(height: 3),
                          Text(step.desc,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.gray,
                                  height: 1.45)),
                        ],
                      ),
                    ),
                    if (isActive)
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: tabColor, shape: BoxShape.circle)),
                  ]),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),

          // ── Progress bar ──────────────────────────────────────────────
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

  // ── EARN BY CATEGORY (horizontal scroll) ──────────────────────────────────
  Widget _buildEarnSection() {
    const cats = [
      (
        icon: '🚚',
        cat: 'Delivery',
        range: '₹150–₹400',
        color: Color(0xFF3B82F6)
      ),
      (
        icon: '🧹',
        cat: 'Cleaning',
        range: '₹300–₹800',
        color: Color(0xFF10B981)
      ),
      (
        icon: '🔧',
        cat: 'Plumbing',
        range: '₹400–₹1,200',
        color: Color(0xFFF59E0B)
      ),
      (
        icon: '⚡',
        cat: 'Electrical',
        range: '₹500–₹1,500',
        color: Color(0xFF8B5CF6)
      ),
      (
        icon: '📦',
        cat: 'Moving',
        range: '₹600–₹2,000',
        color: Color(0xFFEF4444)
      ),
      (
        icon: '📚',
        cat: 'Tutoring',
        range: '₹250–₹700',
        color: Color(0xFF0EA5E9)
      ),
      (
        icon: '🍳',
        cat: 'Cooking',
        range: '₹300–₹900',
        color: Color(0xFFEC4899)
      ),
      (
        icon: '📸',
        cat: 'Photography',
        range: '₹500–₹2,500',
        color: Color(0xFFF97316)
      ),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: c.color.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c.icon,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(height: 4),
                      Text(c.cat,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: c.color)),
                      Text(c.range,
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.gray)),
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

  // ── WHY CHOOSE US (numbered cards) ───────────────────────────────────────
  Widget _buildWhyUs() {
    const features = [
      (
        badge: '01',
        icon: Icons.shield_rounded,
        color: Color(0xFF6366F1),
        title: 'Safe & Secure',
        desc: 'Payments held safely until work is verified by the poster.',
      ),
      (
        badge: '02',
        icon: Icons.bolt_rounded,
        color: Color(0xFFF59E0B),
        title: 'Fast Matching',
        desc: 'Get offers within minutes of posting a task near you.',
      ),
      (
        badge: '03',
        icon: Icons.star_rounded,
        color: Color(0xFF10B981),
        title: 'Rated Taskers',
        desc: 'Every helper is rated after each completed job.',
      ),
      (
        badge: '04',
        icon: Icons.support_agent_rounded,
        color: Color(0xFF0EA5E9),
        title: '24/7 Support',
        desc: 'Our team is always here if anything goes wrong.',
      ),
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
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: f.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child:
                              Icon(f.icon, color: f.color, size: 22),
                        ),
                        Text(f.badge,
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFEEF0F5))),
                      ],
                    ),
                    const Spacer(),
                    Text(f.title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.dark)),
                    const SizedBox(height: 4),
                    Text(f.desc,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.gray,
                            height: 1.45)),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ── TESTIMONIALS ──────────────────────────────────────────────────────────
  Widget _buildTestimonials() {
    const reviews = [
      (
        name: 'Priya M.',
        role: 'Task Poster',
        quote:
            'Got my house cleaned within 2 hours of posting. Super fast and reliable!',
        even: true,
      ),
      (
        name: 'Rahul S.',
        role: 'Tasker',
        quote:
            'Earning ₹800–1,200 a day doing deliveries. Flexible and pays on time.',
        even: false,
      ),
      (
        name: 'Anjali K.',
        role: 'Task Poster',
        quote: 'Hired an electrician in 30 minutes. Payment was safe and easy.',
        even: true,
      ),
      (
        name: 'Vikram D.',
        role: 'Tasker',
        quote:
            'Workmate4u helped me find consistent work near home. Love it!',
        even: false,
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeading(
              icon: Icons.format_quote_rounded, text: 'What People Say'),
          const SizedBox(height: 14),
          SizedBox(
            height: 152,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: reviews.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (ctx, i) {
                final r = reviews[i];
                final accentColor =
                    r.even ? AppColors.primary : AppColors.success;
                return Container(
                  width: 224,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border(
                        left: BorderSide(color: accentColor, width: 3)),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: List.generate(
                            5,
                            (_) => const Icon(Icons.star_rounded,
                                color: Color(0xFFF59E0B), size: 14)),
                      ),
                      const SizedBox(height: 8),
                      Text('"${r.quote}"',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.gray,
                              height: 1.5)),
                      const Spacer(),
                      Text(r.name,
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.dark)),
                      Text(r.role,
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.gray)),
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

  // ── BOTTOM CTA ────────────────────────────────────────────────────────────
  Widget _buildCTA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 36),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 8)),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Text(
            'Ready to get started?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Post a task or start earning as a helper today.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => context.push('/post-task'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.primary,
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23)),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  elevation: 0,
                ),
                child: const Text('Post a Task'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.go('/browse'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  side: const BorderSide(color: Colors.white70, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(23)),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: const Text('Browse Tasks',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Private helper widgets ───────────────────────────────────────────────────

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
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.dark)),
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
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: iconColor)),
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
        border:
            Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 5),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.primary,
                fontWeight: FontWeight.w600)),
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
              Icon(icon,
                  size: 15, color: active ? Colors.white : AppColors.gray),
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
