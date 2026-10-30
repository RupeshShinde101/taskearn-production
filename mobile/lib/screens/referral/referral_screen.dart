import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';

class ReferralScreen extends StatefulWidget {
  const ReferralScreen({super.key});

  @override
  State<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends State<ReferralScreen> {
  bool _isNotified = false;
  int? _expandedFaqIndex;

  void _toggleNotify() {
    setState(() {
      _isNotified = !_isNotified;
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _isNotified ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isNotified
                    ? "🎉 You're on the VIP list! We will alert you the moment rewards launch."
                    : 'VIP launch notification preference updated.',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: _isNotified ? const Color(0xFF10B981) : AppColors.dark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: AppColors.dark),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/profile');
            }
          },
        ),
        title: const Text(
          'Referral & Rewards',
          style: TextStyle(
            color: AppColors.dark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero Banner ──────────────────────────────────────────
            _buildHeroCard(),

            const SizedBox(height: 20),

            // ── VIP Early-Access Subscription Card ───────────────────
            _buildVipAccessCard(),

            const SizedBox(height: 28),

            // ── How It Will Work (Timeline) ──────────────────────────
            _buildSectionHeader(
              title: "How You'll Earn",
              subtitle: 'Simple 3-step rewards program designed for you',
              badge: 'COMING SOON',
            ),
            const SizedBox(height: 14),
            _buildStepsCard(),

            const SizedBox(height: 28),

            // ── Milestone Reward Tiers (Preview) ─────────────────────
            _buildSectionHeader(
              title: 'Sneak Peek: Reward Tiers',
              subtitle: 'Unlock bigger cashbacks as your referral circle grows',
            ),
            const SizedBox(height: 14),
            _buildTiersList(),

            const SizedBox(height: 28),

            // ── Key Highlights (2x2 Grid) ────────────────────────────
            _buildSectionHeader(
              title: 'Why You’ll Love Rewards 2.0',
              subtitle: 'Transparent, instant, and rewarding for both sides',
            ),
            const SizedBox(height: 14),
            _buildPerksGrid(),

            const SizedBox(height: 28),

            // ── FAQs ─────────────────────────────────────────────────
            _buildSectionHeader(
              title: 'Frequently Asked Questions',
              subtitle: 'Everything you need to know about the upcoming launch',
            ),
            const SizedBox(height: 14),
            _buildFaqSection(),

            const SizedBox(height: 32),

            // ── Bottom Action Button ─────────────────────────────────
            _buildBottomAction(context),

            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Workmate4u Pune • Referral program terms apply upon launch',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hero Card ──────────────────────────────────────────────────────
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E1B4B), // deep indigo
            Color(0xFF312E81),
            Color(0xFF4338CA),
            Color(0xFF6366F1), // bright vibrant indigo
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4338CA).withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Ambient decorative circles
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.04),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            child: Column(
              children: [
                // Glowing Top Chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFFDE047).withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, color: Color(0xFFFDE047), size: 14),
                      SizedBox(width: 7),
                      Text(
                        'REWARDS 2.0 • COMING SOON',
                        style: TextStyle(
                          color: Color(0xFFFEF08A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                // Icon Centerpiece with layered glowing ring
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.25),
                        Colors.white.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.45),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 66,
                      height: 66,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.card_giftcard_rounded,
                        color: Color(0xFF4F46E5),
                        size: 36,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // Title
                const Text(
                  'Invite Friends & Earn Real Cash',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    height: 1.25,
                  ),
                ),

                const SizedBox(height: 10),

                // Subtitle
                Text(
                  'We are currently upgrading our rewards system with instant wallet cash, tier bonuses, and zero-commission vouchers. Stay tuned!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 20),

                // Mini highlight chips
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPillTag(
                      icon: Icons.currency_rupee_rounded,
                      text: '₹100 / Invite',
                    ),
                    _buildPillTag(
                      icon: Icons.bolt_rounded,
                      text: 'Instant UPI Cash',
                    ),
                    _buildPillTag(
                      icon: Icons.workspace_premium_rounded,
                      text: 'VIP Helper Badges',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillTag({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFFFDE047), size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── VIP Access Card ────────────────────────────────────────────────
  Widget _buildVipAccessCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isNotified ? const Color(0xFF10B981) : const Color(0xFFC7D2FE),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: _isNotified
                ? const Color(0xFF10B981).withValues(alpha: 0.1)
                : const Color(0xFF6366F1).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: _isNotified
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFEEF2FF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isNotified
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: _isNotified ? const Color(0xFF10B981) : AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _isNotified ? 'VIP Priority Reserved' : 'Get Launch Notification',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.dark,
                      ),
                    ),
                    if (_isNotified) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_circle_rounded,
                          color: Color(0xFF10B981), size: 15),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _isNotified
                      ? 'You will receive priority access and launch bonus alert!'
                      : 'Be the first in Pune to get an active referral link.',
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleNotify,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: _isNotified
                      ? const Color(0xFFF1F5F9)
                      : AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isNotified ? 'Subscribed' : 'Notify Me',
                  style: TextStyle(
                    color: _isNotified ? AppColors.dark : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Steps Section ──────────────────────────────────────────────────
  Widget _buildStepsCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildStepRow(
            number: '01',
            icon: Icons.share_rounded,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFDBEAFE),
            title: 'Share Your Unique Link',
            description:
                'Send your personal invite link or QR code to friends, neighbors & helpers via WhatsApp or SMS in Pune.',
            isLast: false,
          ),
          _buildStepRow(
            number: '02',
            icon: Icons.task_alt_rounded,
            iconColor: const Color(0xFF8B5CF6),
            iconBg: const Color(0xFFEDE9FE),
            title: 'Friend Posts or Takes a Task',
            description:
                'When your friend posts their first local task or accepts a gig and successfully completes it.',
            isLast: false,
          ),
          _buildStepRow(
            number: '03',
            icon: Icons.account_balance_wallet_rounded,
            iconColor: const Color(0xFF10B981),
            iconBg: const Color(0xFFD1FAE5),
            title: 'Guaranteed Wallet Cash',
            description:
                '₹100 bonus instantly hits both of your Workmate4u wallets. Withdraw directly via UPI anytime!',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow({
    required String number,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String description,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Number badge + vertical line
        Column(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
                border: Border.all(color: iconColor.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  number,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 48,
                margin: const EdgeInsets.symmetric(vertical: 4),
                color: const Color(0xFFE2E8F0),
              ),
          ],
        ),
        const SizedBox(width: 14),

        // Text & details
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: iconColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.dark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: AppColors.gray,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Tiers Section ──────────────────────────────────────────────────
  Widget _buildTiersList() {
    return Column(
      children: [
        _buildTierCard(
          badgeLabel: 'TIER 1 • BRONZE',
          badgeColor: const Color(0xFFB45309),
          badgeBg: const Color(0xFFFEF3C7),
          title: 'Starter Circle',
          criteria: '1 - 3 Friends Invited',
          reward: '₹50 per invite',
          perks: 'Standard wallet payout',
          icon: Icons.shield_outlined,
          iconColor: const Color(0xFFD97706),
        ),
        const SizedBox(height: 10),
        _buildTierCard(
          badgeLabel: 'TIER 2 • SILVER',
          badgeColor: const Color(0xFF475569),
          badgeBg: const Color(0xFFF1F5F9),
          title: 'Community Ambassador',
          criteria: '4 - 9 Friends Invited',
          reward: '₹75 per invite',
          perks: 'Priority Helper Matching + Silver Profile Badge',
          icon: Icons.military_tech_outlined,
          iconColor: const Color(0xFF64748B),
          isHighlighted: true,
        ),
        const SizedBox(height: 10),
        _buildTierCard(
          badgeLabel: 'TIER 3 • GOLD CHAMPION',
          badgeColor: const Color(0xFF92400E),
          badgeBg: const Color(0xFFFDE68A),
          title: 'Workmate4u Legend',
          criteria: '10+ Friends Invited',
          reward: '₹100 per invite',
          perks: 'Zero Service Fee Vouchers + VIP Crown on Profile',
          icon: Icons.workspace_premium_rounded,
          iconColor: const Color(0xFFEAB308),
        ),
      ],
    );
  }

  Widget _buildTierCard({
    required String badgeLabel,
    required Color badgeColor,
    required Color badgeBg,
    required String title,
    required String criteria,
    required String reward,
    required String perks,
    required IconData icon,
    required Color iconColor,
    bool isHighlighted = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted ? AppColors.primary : AppColors.border,
          width: isHighlighted ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isHighlighted
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 12, color: Color(0xFF64748B)),
                    SizedBox(width: 4),
                    Text(
                      'Locked',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: AppColors.dark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      criteria,
                      style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    reward,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    perks,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Perks Grid ─────────────────────────────────────────────────────
  Widget _buildPerksGrid() {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.45,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        _PerkMiniCard(
          icon: Icons.bolt_rounded,
          iconColor: Color(0xFFEAB308),
          title: 'Instant UPI Payouts',
          subtitle: 'Direct to Bank or GPay',
        ),
        _PerkMiniCard(
          icon: Icons.all_inclusive_rounded,
          iconColor: Color(0xFF2563EB),
          title: 'Unlimited Invites',
          subtitle: 'No monthly cap or limit',
        ),
        _PerkMiniCard(
          icon: Icons.handshake_rounded,
          iconColor: Color(0xFF10B981),
          title: 'Double-Sided Bonus',
          subtitle: 'Both you & friend win',
        ),
        _PerkMiniCard(
          icon: Icons.verified_user_rounded,
          iconColor: Color(0xFF8B5CF6),
          title: '100% Free & Safe',
          subtitle: 'Zero hidden conditions',
        ),
      ],
    );
  }

  // ── FAQs ───────────────────────────────────────────────────────────
  Widget _buildFaqSection() {
    final faqs = [
      {
        'q': 'When will the Referral & Rewards program launch?',
        'a':
            'Our engineering team is actively testing the automated wallet reward distribution system. We will release it in the next upcoming Pune app update!',
      },
      {
        'q': 'Can I earn as both a Task Poster and a Helper?',
        'a':
            'Absolutely! You can refer both task posters and helpers. Once they finish their first task in Pune, your wallet will be credited automatically.',
      },
      {
        'q': 'How do I withdraw my referral rewards?',
        'a':
            'All reward earnings are deposited directly into your Workmate4u Wallet, which can be withdrawn to your UPI ID or bank account instantly.',
      },
      {
        'q': 'Will previous tasks count towards milestones?',
        'a':
            'Yes! Active helpers and verified posters will receive an early-bird starter bonus when the system officially opens.',
      },
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(faqs.length, (index) {
          final isExpanded = _expandedFaqIndex == index;
          final isLast = index == faqs.length - 1;
          final faq = faqs[index];

          return Column(
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expandedFaqIndex = isExpanded ? null : index;
                  });
                },
                borderRadius: BorderRadius.vertical(
                  top: index == 0 ? const Radius.circular(18) : Radius.zero,
                  bottom: isLast && !isExpanded ? const Radius.circular(18) : Radius.zero,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.help_outline_rounded,
                            size: 15, color: AppColors.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          faq['q']!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.dark,
                          ),
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.gray,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
                  child: Text(
                    faq['a']!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.gray,
                      height: 1.45,
                    ),
                  ),
                ),
              if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
            ],
          );
        }),
      ),
    );
  }

  // ── Bottom Action ──────────────────────────────────────────────────
  Widget _buildBottomAction(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/profile');
              }
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text(
              'Back to Profile',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Section Header Helper ──────────────────────────────────────────
  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    String? badge,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.dark,
                letterSpacing: -0.2,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    color: Color(0xFFB45309),
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppColors.gray,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _PerkMiniCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _PerkMiniCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: AppColors.dark,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.gray,
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
