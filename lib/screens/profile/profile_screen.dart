import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/image_utils.dart';
import 'physical_onboarding_screen.dart';
import 'vehicle_verification_screen.dart';
import '../../widgets/task_screen_watermark.dart';

// â”€â”€ All available skills the user can select â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const _kAllSkills = [
  'Cleaning', 'Delivery', 'Driving', 'Cooking', 'Plumbing', 'Electrical',
  'Carpentry', 'Painting', 'Gardening', 'Moving & Packing', 'Shopping',
  'Pet Care', 'Babysitting', 'Elder Care', 'Tutoring', 'Photography',
  'Video Editing', 'Graphic Design', 'Web Development', 'Data Entry',
  'Translation', 'Errands', 'Assembly', 'Event Help', 'Security',
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showSkills = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().refreshUser();
    });
  }

  Future<void> _refresh() async {
    await context.read<AuthProvider>().refreshUser();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final userSkills = user?.skills ?? const <String>[];
    final phyStatus = user?.physicalVerificationStatus;
    final vehStatus = user?.vehicleVerificationStatus;
    final phyRemaining = user?.physicalVerificationReapplyRemaining ?? Duration.zero;
    final vehRemaining = user?.vehicleVerificationReapplyRemaining ?? Duration.zero;

    return TaskScreenWatermark(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: const Text(
            'Profile',
            style: TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: InkWell(
                onTap: () => _showEditDialog(context, auth),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.edit_outlined,
                    color: Color(0xFF2563EB),
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            // â”€â”€ Avatar, name, email, rating â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _showEditDialog(context, auth),
                    child: Stack(
                      children: [
                        Selector<AuthProvider, String?>(
                          selector: (_, a) => a.user?.avatar,
                          builder: (_, avatar, __) => Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFDBEAFE),
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: avatar != null
                                  ? Image(
                                      image: avatarImage(avatar)!,
                                      fit: BoxFit.cover,
                                      width: 96,
                                      height: 96,
                                    )
                                  : Center(
                                      child: Text(
                                        user?.name.isNotEmpty == true
                                            ? user!.name[0].toUpperCase()
                                            : 'V',
                                        style: const TextStyle(
                                          fontSize: 38,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2563EB),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.name ?? '',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    user?.email ?? '',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (user?.phone != null && user!.phone!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.phone!,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final userRating = user?.rating;
                      final rating = (userRating != null && userRating > 0)
                          ? userRating
                          : 5.0;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ...List.generate(5, (i) {
                            final filled = i < rating.floor();
                            final half = !filled && i < rating;
                            return Icon(
                              filled
                                  ? Icons.star_rounded
                                  : (half ? Icons.star_half_rounded : Icons.star_outline_rounded),
                              color: const Color(0xFFF59E0B),
                              size: 20,
                            );
                          }),
                          const SizedBox(width: 6),
                          Text(
                            rating.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // â”€â”€ Profile Role Switcher (Poster vs Helper) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _ProfileRoleSwitcher(
              currentMode: auth.profileMode,
              onModeChanged: (newMode) async {
                if (newMode == auth.profileMode) return;
                await auth.setProfileMode(newMode);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Icon(
                            newMode == 'poster'
                                ? Icons.assignment_turned_in
                                : Icons.handshake,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              newMode == 'poster'
                                  ? 'Switched to Poster Mode: You can now post tasks.'
                                  : 'Switched to Helper Mode: You can now accept tasks & receive task alerts.',
                            ),
                          ),
                        ],
                      ),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: newMode == 'poster'
                          ? AppColors.primary
                          : const Color(0xFF10B981),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              },
            ),

            const SizedBox(height: 16),

            // â”€â”€ Stats card (Tasks Completed | Tasks Posted) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    _StatCell(
                      label: 'Tasks\nCompleted',
                      value: '${user?.tasksCompleted ?? 0}',
                    ),
                    const VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: Color(0xFFF1F5F9),
                    ),
                    _StatCell(
                      label: 'Tasks\nPosted',
                      value: '${user?.tasksPosted ?? 0}',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // â”€â”€ KYC card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            _KycCard(
              user: user,
              onStart: () => context.push('/kyc'),
            ),

            const SizedBox(height: 16),

            // â”€â”€ Bio section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (user?.bio != null && user!.bio!.isNotEmpty) ...[
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader('About Me'),
                    const SizedBox(height: 8),
                    Text(
                      user.bio!,
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 13.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // â”€â”€ Skills section (Helper only) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            if (auth.isHelperMode) ...[
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _showSkills = !_showSkills),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            const Text('My Skills',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            if (userSkills.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius:
                                        BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${userSkills.length}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (userSkills.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showSkillsDialog(context, auth),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8, vertical: 8),
                        child: Icon(Icons.edit_outlined,
                            size: 20, color: AppColors.gray),
                      ),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _showSkills = !_showSkills),
                    child: Padding(
                      padding: const EdgeInsets.only(
                          left: 4, top: 8, bottom: 8),
                      child: Icon(
                        _showSkills
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: AppColors.gray,
                      ),
                    ),
                  ),
                ],
              ),
              if (_showSkills) ...[
                const SizedBox(height: 8),
                if (userSkills.isEmpty)
                  _EmptySkillsHint(
                      onAdd: () => _showSkillsDialog(context, auth))
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.light,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: userSkills
                          .map((s) {
                            final isSensitive = kSensitiveSkills.contains(s);
                            final isVehicle = isVehicleSkill(s);
                            return Chip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(s),
                                  if (isSensitive) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.shield_outlined,
                                        size: 13, color: Color(0xFFD97706)),
                                  ] else if (isVehicle) ...[
                                    const SizedBox(width: 4),
                                    const Icon(Icons.directions_car_outlined,
                                        size: 13, color: Color(0xFF1D4ED8)),
                                  ],
                                ],
                              ),
                              backgroundColor: isSensitive
                                  ? const Color(0xFFFEF3C7)
                                  : isVehicle
                                      ? const Color(0xFFEFF6FF)
                                      : AppColors.primary
                                          .withValues(alpha: 0.1),
                              labelStyle: TextStyle(
                                  color: isSensitive
                                      ? const Color(0xFF92400E)
                                      : isVehicle
                                          ? const Color(0xFF1E40AF)
                                          : AppColors.primary,
                                  fontWeight: FontWeight.w500,
                                  fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif']),
                              side: BorderSide(
                                  color: isSensitive
                                      ? const Color(0xFFF59E0B)
                                      : isVehicle
                                          ? const Color(0xFF3B82F6)
                                          : AppColors.primary
                                              .withValues(alpha: 0.3)),
                            );
                          })
                          .toList(),
                    ),
                  ),
                if (hasSensitiveSkill(userSkills)) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: phyStatus == 'verified'
                          ? const Color(0xFFD1FAE5)
                          : (phyStatus == 'pending'
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFFEE2E2)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: phyStatus == 'verified'
                            ? const Color(0xFFA7F3D0)
                            : (phyStatus == 'pending'
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFFECACA)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          phyStatus == 'verified'
                              ? Icons.verified_user_rounded
                              : (phyStatus == 'pending'
                                  ? Icons.hourglass_top_rounded
                                  : Icons.warning_amber_rounded),
                          size: 16,
                          color: phyStatus == 'verified'
                              ? const Color(0xFF059669)
                              : (phyStatus == 'pending'
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFFDC2626)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            phyStatus == 'verified'
                                ? 'Sensitive skills physically verified'
                                : (phyStatus == 'pending'
                                    ? 'Physical onboarding under review (completes in 24 hrs)'
                                    : (phyStatus == 'rejected'
                                        ? (!(user?.canReapplyPhysicalVerification ?? true)
                                            ? 'Onboarding rejected. Reapply in ${phyRemaining.inHours}h ${phyRemaining.inMinutes % 60}m'
                                            : 'Onboarding rejected. 24h cooldown passed — reapply now')
                                        : 'Sensitive skills require physical verification by Admin')),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: phyStatus == 'verified'
                                  ? const Color(0xFF065F46)
                                  : (phyStatus == 'pending'
                                      ? const Color(0xFF92400E)
                                      : const Color(0xFF991B1B)),
                            ),
                          ),
                        ),
                        if (phyStatus != 'verified' && phyStatus != 'pending')
                          GestureDetector(
                            onTap: () => context.push('/physical-onboarding', extra: {'skills': userSkills}),
                            child: Text(
                              phyStatus == 'rejected'
                                  ? (!(user?.canReapplyPhysicalVerification ?? true) ? 'View Status' : 'Reapply')
                                  : 'Verify Now',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (hasVehicleSkill(userSkills)) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: vehStatus == 'verified'
                          ? const Color(0xFFD1FAE5)
                          : (vehStatus == 'pending'
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFEFF6FF)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: vehStatus == 'verified'
                            ? const Color(0xFFA7F3D0)
                            : (vehStatus == 'pending'
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFBFDBFE)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          vehStatus == 'verified'
                              ? Icons.verified_user_rounded
                              : (vehStatus == 'pending'
                                  ? Icons.hourglass_top_rounded
                                  : Icons.directions_car_rounded),
                          size: 16,
                          color: vehStatus == 'verified'
                              ? const Color(0xFF059669)
                              : (vehStatus == 'pending'
                                  ? const Color(0xFFD97706)
                                  : const Color(0xFF1D4ED8)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vehStatus == 'verified'
                                ? 'Vehicle skills verified'
                                : (vehStatus == 'pending'
                                    ? 'Vehical verification under review (completes in 24 hrs)'
                                    : (vehStatus == 'rejected'
                                        ? (!(user?.canReapplyVehicleVerification ?? true)
                                            ? 'Vehical verification rejected. Reapply in ${vehRemaining.inHours}h ${vehRemaining.inMinutes % 60}m'
                                            : 'Vehical verification rejected. 24h cooldown passed — reapply now')
                                        : 'Vehicle skills require Driving License & RC verification')),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: vehStatus == 'verified'
                                  ? const Color(0xFF065F46)
                                  : (vehStatus == 'pending'
                                      ? const Color(0xFF92400E)
                                      : const Color(0xFF1E40AF)),
                            ),
                          ),
                        ),
                        if (vehStatus != 'verified' && vehStatus != 'pending')
                          GestureDetector(
                            onTap: () => context.push('/vehicle-verification', extra: {'skills': userSkills}),
                            child: Text(
                              vehStatus == 'rejected'
                                  ? (!(user?.canReapplyVehicleVerification ?? true) ? 'View Status' : 'Reapply')
                                  : 'Verify Now',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1D4ED8),
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 20),
            ],

            // â”€â”€ Menu items â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _MenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'My Wallet',
                    onTap: () => context.push('/wallet'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.card_giftcard_outlined,
                    title: 'Referral & Rewards',
                    badge: 'Coming Soon',
                    onTap: () => context.push('/referral'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    onTap: () => context.push('/notifications'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  if (auth.isHelperMode) ...[
                    _MenuItem(
                      icon: Icons.shield_outlined,
                      title: 'Physical Onboarding Request',
                      badge: phyStatus == 'verified'
                          ? 'Verified'
                          : (phyStatus == 'pending'
                              ? 'In 24h Review'
                              : (phyStatus == 'rejected'
                                  ? (!(user?.canReapplyPhysicalVerification ?? true)
                                      ? '24h Cooldown'
                                      : 'Reapply Ready')
                                  : (hasSensitiveSkill(userSkills) ? 'Action Required' : null))),
                      badgeColor: phyStatus == 'verified'
                          ? AppColors.success
                          : (phyStatus == 'pending'
                              ? AppColors.warning
                              : AppColors.danger),
                      onTap: () => context.push('/physical-onboarding'),
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                    _MenuItem(
                      icon: Icons.directions_car_outlined,
                      title: 'Vehicle Verification',
                      badge: vehStatus == 'verified'
                          ? 'Verified'
                          : (vehStatus == 'pending'
                              ? 'In 24h Review'
                              : (vehStatus == 'rejected'
                                  ? (!(user?.canReapplyVehicleVerification ?? true)
                                      ? '24h Cooldown'
                                      : 'Reapply Ready')
                                  : (hasVehicleSkill(userSkills) ? 'Action Required' : null))),
                      badgeColor: vehStatus == 'verified'
                          ? AppColors.success
                          : (vehStatus == 'pending'
                              ? AppColors.warning
                              : AppColors.danger),
                      onTap: () => context.push('/vehicle-verification'),
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  ],
                  _MenuItem(
                    icon: Icons.shield_outlined,
                    title: 'Security',
                    onTap: () => _launch('https://workmate4u.com/safety'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.sync_lock_rounded,
                    title: 'Change Password',
                    onTap: () => _showChangePasswordDialog(context, auth),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.help_outline_rounded,
                    title: 'Help & Support',
                    onTap: () => _launch('https://workmate4u.com/help'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.play_circle_outline_rounded,
                    title: 'How to Use (Tutorial)',
                    onTap: () => context.push('/tutorial'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.policy_outlined,
                    title: 'Privacy Policy',
                    onTap: () => context.push('/privacy'),
                  ),
                  const Divider(height: 1, thickness: 1, color: Color(0xFFF1F5F9)),
                  _MenuItem(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service & Conditions',
                    onTap: () => context.push('/terms'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // â”€â”€ Sign out â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.55),
                      builder: (dialogContext) => Dialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        insetPadding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 40),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon + title
                              Row(
                                children: [
                                  Container(
                                    width: 44, height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.logout_rounded,
                                        color: Color(0xFFEF4444), size: 22),
                                  ),
                                  const SizedBox(width: 14),
                                  const Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Sign Out',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1E293B),
                                              letterSpacing: -0.4)),
                                      Text('You can sign back in anytime',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF94A3B8))),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 20),
                              // Info banner
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.info_outline_rounded,
                                        size: 16, color: Color(0xFF64748B)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Your data and tasks will remain safe. Notifications will be disabled until you sign back in.',
                                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: const Color(0xFF64748B)
                                                .withValues(alpha: 0.9),
                                            height: 1.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              // Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(false),
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            const Color(0xFF64748B),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          side: const BorderSide(
                                              color: Color(0xFFE2E8F0)),
                                        ),
                                      ),
                                      child: const Text('Stay',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      icon: const Icon(Icons.logout_rounded,
                                          size: 16),
                                      label: const Text('Sign Out',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFEF4444),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (confirm == true && context.mounted) {
                      await auth.logout();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Color(0xFFEF4444),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Sign Out',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // â”€â”€ Delete account â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showDeleteAccountDialog(context, auth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFEF4444),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'Delete My Account',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 95),
          ],
        ),
      ),
    ),
      ),
    );
  }

  // â”€â”€ Launch URL in external browser â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // â”€â”€ Edit personal details bottom sheet (pencil icon / avatar) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showEditDialog(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _EditProfileSheet(auth: auth),
    );
  }

  // â”€â”€ Edit skills bottom sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showSkillsDialog(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _EditSkillsSheet(auth: auth),
    );
  }

  // â”€â”€ Delete Account dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showDeleteAccountDialog(BuildContext context, AuthProvider auth) {
    final isGoogleUser = auth.user?.authProvider == 'google';
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    bool deleting = false;
    String? errorMsg;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (dialogCtx, _, __) => StatefulBuilder(
        builder: (ctx, setDialogState) => Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.danger.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Red header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 60, height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.delete_forever_rounded,
                              color: Colors.white, size: 30),
                        ),
                        const SizedBox(height: 10),
                        const Text('Delete Account',
                            style: TextStyle(
                                color: Colors.white, fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text('This action is permanent',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  // Body
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('The following will be permanently removed:',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600,
                                color: Color(0xFF1E293B))),
                        const SizedBox(height: 12),
                        ...[
                          'ðŸ“‹ Your profile & personal details',
                          'ðŸ’° Wallet balance & transaction history',
                          'ðŸ“Œ Posted & accepted tasks',
                          'â­ Ratings & reviews',
                        ].map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(item, style: const TextStyle(
                              fontSize: 13, color: Color(0xFF475569))),
                        )),
                        if (!isGoogleUser) ...[
                          const SizedBox(height: 16),
                          const Divider(),
                          const SizedBox(height: 10),
                          const Text('Enter your password to confirm:',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B))),
                          const SizedBox(height: 10),
                          TextField(
                            controller: passwordCtrl,
                            obscureText: obscure,
                            decoration: InputDecoration(
                              hintText: 'Your password',
                              prefixIcon: const Icon(Icons.lock_outline,
                                  color: AppColors.danger),
                              suffixIcon: IconButton(
                                icon: Icon(obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                    color: AppColors.gray),
                                onPressed: () =>
                                    setDialogState(() => obscure = !obscure),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.danger, width: 1.5),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFFFF5F5),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        // Inline error message
                        if (errorMsg != null) ...[  
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: AppColors.danger, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(errorMsg!,
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(dialogCtx).pop(),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF475569),
                                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                ),
                                child: const Text('Keep Account',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600, fontSize: 13)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: deleting ? null
                                      : const LinearGradient(colors: [
                                          Color(0xFFDC2626), Color(0xFFEF4444)]),
                                  color: deleting ? const Color(0xFFD1D5DB) : null,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: deleting ? [] : [
                                    BoxShadow(
                                      color: AppColors.danger.withValues(alpha: 0.35),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    )
                                  ],
                                ),
                                child: ElevatedButton(
                                  onPressed: deleting ? null : () async {
                                    setDialogState(() {
                                      deleting = true;
                                      errorMsg = null;
                                    });
                                    final result = await auth.deleteAccount(
                                        password: isGoogleUser
                                            ? null
                                            : passwordCtrl.text);
                                    if (result['success'] == true) {
                                      if (dialogCtx.mounted) {
                                        Navigator.of(dialogCtx).pop();
                                      }
                                      // GoRouter auto-redirects to /login
                                    } else {
                                      setDialogState(() {
                                        deleting = false;
                                        errorMsg = result['message'] ??
                                            'Failed to delete account. Please try again.';
                                      });
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: deleting
                                      ? const SizedBox(
                                          width: 18, height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2, color: Colors.white))
                                      : const Text('Delete',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // â”€â”€ Change Password dialog â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  void _showChangePasswordDialog(BuildContext context, AuthProvider auth) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: currentCtrl,
                  obscureText: obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureCurrent
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setDialogState(() => obscureCurrent = !obscureCurrent),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter current password' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_reset_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setDialogState(() => obscureNew = !obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 6) {
                      return 'Min 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: obscureConfirm,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setDialogState(() => obscureConfirm = !obscureConfirm),
                    ),
                  ),
                  validator: (v) =>
                      v != newCtrl.text ? 'Passwords do not match' : null,
                ),
              ],
            ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogCtx);
                final ok = await auth.changePassword(
                  currentPassword: currentCtrl.text,
                  newPassword: newCtrl.text,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? 'Password changed successfully!'
                      : (auth.error ?? 'Failed to change password')),
                  backgroundColor: ok ? AppColors.success : AppColors.danger,
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Edit profile sheet (stateful so it manages skill selection + feedback) â”€â”€â”€
class _EditProfileSheet extends StatefulWidget {
  final AuthProvider auth;
  const _EditProfileSheet({required this.auth});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  String? _gender;
  bool _saving = false;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.auth.user?.name);
    _phoneCtrl = TextEditingController(text: widget.auth.user?.phone ?? '');
    _gender    = widget.auth.user?.gender;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  // â”€â”€ Image picking â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _pickImage(ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        if (status.isPermanentlyDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission denied. Enable it in app settings.'),
              action: SnackBarAction(label: 'Settings', onPressed: openAppSettings),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission denied')),
          );
        }
        return;
      }
    }

    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (picked != null && mounted) {
      setState(() => _pickedImage = File(picked.path));
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
              title: const Text('Take a Photo'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () { Navigator.pop(ctx); _pickImage(ImageSource.gallery); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // â”€â”€ Save â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _saving = true);

    // Encode picked image as base64 data URI and include in the same
    // profile-update request so name/gender are always valid fields.
    String? avatarDataUri;
    if (_pickedImage != null) {
      try {
        final bytes = await _pickedImage!.readAsBytes();
        final ext = _pickedImage!.path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        avatarDataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read the selected photo. Please try again.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
        setState(() => _saving = false);
        return;
      }
    }

    final ok = await widget.auth.updateProfile(
      name: _nameCtrl.text,
      gender: _gender,
      phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
      avatarDataUri: avatarDataUri,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Profile updated successfully!'
            : (widget.auth.error ?? 'Failed to save profile. Please try again.')),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentAvatarUrl = widget.auth.user?.avatar;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text('Edit Profile',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 16),

            // â”€â”€ Avatar picker â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Center(
              child: GestureDetector(
                onTap: _saving ? null : _showImageSourceSheet,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.light,
                      backgroundImage: _pickedImage != null
                          ? FileImage(_pickedImage!) as ImageProvider
                          : avatarImage(currentAvatarUrl),
                      child: (_pickedImage == null &&
                              (currentAvatarUrl == null || currentAvatarUrl.isEmpty))
                          ? Text(
                              widget.auth.user?.name.isNotEmpty == true
                                  ? widget.auth.user!.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary))
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: AppColors.gradient),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text('Tap to change photo',
                  style: TextStyle(color: AppColors.gray, fontSize: 12)),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                  hintText: '+91 XXXXXXXXXX'),
            ),
            const SizedBox(height: 16),

            // â”€â”€ Gender selection â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            const Text('Gender',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.dark)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _GenderOption(
                    label: 'Male', emoji: 'ðŸ‘¦',
                    selected: _gender == 'male',
                    onTap: () => setState(() => _gender = 'male'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _GenderOption(
                    label: 'Female', emoji: 'ðŸ‘§',
                    selected: _gender == 'female',
                    onTap: () => setState(() => _gender = 'female'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Gender option tile â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _GenderOption extends StatelessWidget {
  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  const _GenderOption({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.dark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Edit skills sheet â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EditSkillsSheet extends StatefulWidget {
  final AuthProvider auth;
  const _EditSkillsSheet({required this.auth});

  @override
  State<_EditSkillsSheet> createState() => _EditSkillsSheetState();
}

const List<String> _kVehicleSkills = [
  'Delivery',
  'Driving',
  'Moving & Packing',
];

const List<String> _kSensitiveSkillsList = [
  'Cleaning',
  'Cooking',
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Pet Care',
  'Babysitting',
  'Elder Care',
];

const List<String> _kGeneralSkills = [
  'Painting',
  'Gardening',
  'Shopping',
  'Tutoring',
  'Photography',
  'Video Editing',
  'Graphic Design',
  'Web Development',
  'Data Entry',
  'Translation',
  'Errands',
  'Assembly',
  'Event Help',
  'Security',
];

class _EditSkillsSheetState extends State<_EditSkillsSheet> {
  late List<String> _selectedSkills;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedSkills = List.from(widget.auth.user?.skills ?? []);
  }

  void _toggleSkill(String skill) {
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
      } else {
        _selectedSkills.add(skill);
        final user = widget.auth.user;
        if (isVehicleSkill(skill) && user?.vehicleVerificationStatus != 'verified') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showVehicleVerificationPrompt(skill);
          });
        }
      }
    });
  }

  void _showVehicleVerificationPrompt(String skill) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (promptCtx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Color(0xFFDBEAFE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_car_rounded, color: Color(0xFF1D4ED8), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Vehicle Verification Required',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A),
                          fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Skill "$skill" requires vehicle documentation (Driving License & Vehicle RC) before you can accept vehicle tasks.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    height: 1.45,
                    fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(promptCtx);
                      final router = GoRouter.of(context);
                      Navigator.pop(context);
                      final vehicleSelected = _selectedSkills.where((s) => isVehicleSkill(s)).toList();
                      router.push('/vehicle-verification', extra: {
                        'skills': vehicleSelected.isNotEmpty ? vehicleSelected : [skill],
                      });
                    },
                    icon: const Icon(Icons.drive_eta_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'Open Verification Form',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E40AF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
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

  Future<void> _save() async {
    final user = widget.auth.user;
    final isVerified = user?.physicalVerificationStatus == 'verified';
    final isVehicleVerified = user?.vehicleVerificationStatus == 'verified';

    // Sensitive skills cannot be saved directly by unverified helpers
    final sensitiveSelected = _selectedSkills.where((s) => kSensitiveSkills.contains(s)).toList();
    if (sensitiveSelected.isNotEmpty && !isVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sensitive skills (${sensitiveSelected.join(", ")}) require admin verification. Please request onboarding verification.',
            style: const TextStyle(fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif']),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Vehicle skills cannot be saved directly by unverified helpers
    final vehicleSelected = _selectedSkills.where((s) => isVehicleSkill(s)).toList();
    if (vehicleSelected.isNotEmpty && !isVehicleVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vehicle skills (${vehicleSelected.join(", ")}) require vehicle verification (DL & RC). Please submit verification.',
            style: const TextStyle(fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif']),
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final ok = await widget.auth.updateProfile(skills: _selectedSkills);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Skills updated successfully!'
              : (widget.auth.error ?? 'Failed to save skills. Please try again.'),
          style: const TextStyle(fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif']),
        ),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildSkillCard(
    String skill, {
    required bool isSelected,
    required bool isVehicle,
    required bool isSensitive,
    required VoidCallback onTap,
  }) {
    final Color activeColor = isSensitive
        ? const Color(0xFFD97706)
        : isVehicle
            ? const Color(0xFF1D4ED8)
            : AppColors.primary;

    final Color activeBg = isSensitive
        ? const Color(0xFFFFFBEB)
        : isVehicle
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFEEF2FF);

    final Color activeBorder = isSensitive
        ? const Color(0xFFF59E0B)
        : isVehicle
            ? const Color(0xFF3B82F6)
            : AppColors.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeBg : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? activeBorder : const Color(0xFFE2E8F0),
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.10),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? activeColor : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? activeColor : const Color(0xFFCBD5E1),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 12, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  skill,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? activeColor : const Color(0xFF1E293B),
                    fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                  ),
                ),
              ),
              if (isVehicle) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.directions_car_rounded,
                  size: 15,
                  color: isSelected ? activeColor : const Color(0xFF94A3B8),
                ),
              ] else if (isSensitive) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.shield_rounded,
                  size: 15,
                  color: isSelected ? activeColor : const Color(0xFF94A3B8),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTwoColumnGrid(List<String> skills, {bool spanLastIfOdd = false}) {
    final List<Widget> rows = [];
    for (int i = 0; i < skills.length; i += 2) {
      if (i + 1 < skills.length) {
        final s1 = skills[i];
        final s2 = skills[i + 1];
        rows.add(
          Row(
            children: [
              Expanded(
                child: _buildSkillCard(
                  s1,
                  isSelected: _selectedSkills.contains(s1),
                  isVehicle: isVehicleSkill(s1),
                  isSensitive: kSensitiveSkills.contains(s1),
                  onTap: () => _toggleSkill(s1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSkillCard(
                  s2,
                  isSelected: _selectedSkills.contains(s2),
                  isVehicle: isVehicleSkill(s2),
                  isSensitive: kSensitiveSkills.contains(s2),
                  onTap: () => _toggleSkill(s2),
                ),
              ),
            ],
          ),
        );
      } else {
        final s1 = skills[i];
        if (spanLastIfOdd) {
          rows.add(
            Row(
              children: [
                Expanded(
                  child: _buildSkillCard(
                    s1,
                    isSelected: _selectedSkills.contains(s1),
                    isVehicle: isVehicleSkill(s1),
                    isSensitive: kSensitiveSkills.contains(s1),
                    onTap: () => _toggleSkill(s1),
                  ),
                ),
              ],
            ),
          );
        } else {
          rows.add(
            Row(
              children: [
                Expanded(
                  child: _buildSkillCard(
                    s1,
                    isSelected: _selectedSkills.contains(s1),
                    isVehicle: isVehicleSkill(s1),
                    isSensitive: kSensitiveSkills.contains(s1),
                    onTap: () => _toggleSkill(s1),
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
          );
        }
      }
      if (i + 2 < skills.length || (i + 1 < skills.length && spanLastIfOdd)) {
        rows.add(const SizedBox(height: 8));
      }
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String badgeText,
    required Color badgeBg,
    required Color badgeTextColor,
    required Color iconColor,
    required Color iconBg,
    required String subtitle,
    required int selectedCount,
    required int totalCount,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                        fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: badgeTextColor,
                          fontFamilyFallback: const ['Roboto', 'Arial', 'sans-serif'],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selectedCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$selectedCount/$totalCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
                height: 1.3,
                fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensitiveWarningBanner(List<String> sensitiveSelected, bool isPending) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.shield_rounded, color: Color(0xFFD97706), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isPending
                      ? 'Verification Under Admin Review'
                      : 'Physical Onboarding Required',
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPending
                ? 'You have submitted an onboarding request. Once Admin approves it, your sensitive skills (${sensitiveSelected.join(", ")}) will be activated on your profile.'
                : 'Sensitive skills (${sensitiveSelected.join(", ")}) cannot be saved directly without physical verification. Submit an onboarding verification request below to enable them.',
            style: const TextStyle(
              color: Color(0xFF78350F),
              fontSize: 12,
              height: 1.45,
              fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.push('/physical-onboarding', extra: {'skills': sensitiveSelected});
              },
              icon: const Icon(Icons.send_rounded, size: 16, color: Colors.white),
              label: Text(
                isPending
                    ? 'View Pending Request'
                    : 'Send Onboarding Request (${sensitiveSelected.length} sensitive)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleWarningBanner(List<String> vehicleSelected, bool isVehiclePending) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFDBEAFE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.directions_car_rounded, color: Color(0xFF1D4ED8), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isVehiclePending
                      ? 'Vehicle Verification Under Admin Review'
                      : 'Vehicle Verification Required',
                  style: const TextStyle(
                    color: Color(0xFF1E40AF),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isVehiclePending
                ? 'You have submitted a vehicle verification request. Once Admin approves your DL and RC, your vehicle skills (${vehicleSelected.join(", ")}) will be activated on your profile.'
                : 'Vehicle skills (${vehicleSelected.join(", ")}) require vehicle and Driving License & RC verification. Direct save is disabled. Submit verification below to activate them.',
            style: const TextStyle(
              color: Color(0xFF1E3A8A),
              fontSize: 12,
              height: 1.45,
              fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton.icon(
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.push('/vehicle-verification', extra: {'skills': vehicleSelected});
              },
              icon: const Icon(Icons.drive_eta_rounded, size: 16, color: Colors.white),
              label: Text(
                isVehiclePending
                    ? 'View Pending Vehicle Verification'
                    : 'Open Vehicle Verification Form (${vehicleSelected.length} skills)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.auth.user;
    final isVerified = user?.physicalVerificationStatus == 'verified';
    final isPending = user?.physicalVerificationStatus == 'pending';
    final isVehicleVerified = user?.vehicleVerificationStatus == 'verified';
    final isVehiclePending = user?.vehicleVerificationStatus == 'pending';

    final sensitiveSelected = _selectedSkills.where((s) => kSensitiveSkills.contains(s)).toList();
    final hasSensitive = sensitiveSelected.isNotEmpty;
    final bool disableSaveForSensitive = hasSensitive && !isVerified;

    final vehicleSelected = _selectedSkills.where((s) => isVehicleSkill(s)).toList();
    final hasVehicle = vehicleSelected.isNotEmpty;
    final bool disableSaveForVehicle = hasVehicle && !isVehicleVerified;

    final bool disableSave = disableSaveForSensitive || disableSaveForVehicle;

    final vehicleSelectedCount = _selectedSkills.where((s) => isVehicleSkill(s)).length;
    final sensitiveSelectedCount = _selectedSkills.where((s) => kSensitiveSkills.contains(s)).length;
    final generalSelectedCount = _selectedSkills.where((s) => !isVehicleSkill(s) && !kSensitiveSkills.contains(s)).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.90,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fixed Top Bar: Drag handle, Header with title, count badge, close button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        'My Skills',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_selectedSkills.length} Selected',
                          style: const TextStyle(
                            color: Color(0xFF4F46E5),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 22, color: Color(0xFF64748B)),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select skills so AI can match you with relevant tasks',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            // Scrollable categorized skills
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Vehicle Skills
                    _buildSectionHeader(
                      icon: Icons.directions_car_rounded,
                      title: 'Vehicle Required',
                      badgeText: isVehicleVerified
                          ? 'Verified'
                          : (isVehiclePending ? 'Under Review' : 'DL & RC Required'),
                      badgeBg: isVehicleVerified
                          ? const Color(0xFFDCFCE7)
                          : (isVehiclePending ? const Color(0xFFFEF3C7) : const Color(0xFFEFF6FF)),
                      badgeTextColor: isVehicleVerified
                          ? const Color(0xFF15803D)
                          : (isVehiclePending ? const Color(0xFFB45309) : const Color(0xFF1D4ED8)),
                      iconColor: const Color(0xFF1D4ED8),
                      iconBg: const Color(0xFFDBEAFE),
                      subtitle: 'Tasks involving driving, transport, or vehicle delivery',
                      selectedCount: vehicleSelectedCount,
                      totalCount: _kVehicleSkills.length,
                    ),
                    _buildTwoColumnGrid(_kVehicleSkills, spanLastIfOdd: true),
                    const SizedBox(height: 22),

                    // 2. Sensitive / In-Home Skills
                    _buildSectionHeader(
                      icon: Icons.shield_rounded,
                      title: 'Sensitive & In-Home',
                      badgeText: isVerified
                          ? 'Verified'
                          : (isPending ? 'Under Review' : 'Verification Required'),
                      badgeBg: isVerified
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      badgeTextColor: isVerified
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB45309),
                      iconColor: const Color(0xFFD97706),
                      iconBg: const Color(0xFFFEF3C7),
                      subtitle: 'In-home services requiring identity & physical onboarding',
                      selectedCount: sensitiveSelectedCount,
                      totalCount: _kSensitiveSkillsList.length,
                    ),
                    _buildTwoColumnGrid(_kSensitiveSkillsList),
                    const SizedBox(height: 22),

                    // 3. General Skills
                    _buildSectionHeader(
                      icon: Icons.bolt_rounded,
                      title: 'General Skills',
                      badgeText: 'Instant Match',
                      badgeBg: const Color(0xFFEEF2FF),
                      badgeTextColor: const Color(0xFF4F46E5),
                      iconColor: const Color(0xFF4F46E5),
                      iconBg: const Color(0xFFEEF2FF),
                      subtitle: 'No extra verification needed — start accepting tasks right away',
                      selectedCount: generalSelectedCount,
                      totalCount: _kGeneralSkills.length,
                    ),
                    _buildTwoColumnGrid(_kGeneralSkills),

                    // Warning banners if restricted skills selected
                    if (disableSaveForSensitive) ...[
                      const SizedBox(height: 18),
                      _buildSensitiveWarningBanner(sensitiveSelected, isPending),
                    ],
                    if (disableSaveForVehicle) ...[
                      const SizedBox(height: 18),
                      _buildVehicleWarningBanner(vehicleSelected, isVehiclePending),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            // Fixed Bottom Bar: Save Button
            Padding(
              padding: EdgeInsets.fromLTRB(
                20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_saving || disableSave) ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(0xFFE2E8F0),
                        disabledForegroundColor: const Color(0xFF94A3B8),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(
                              disableSave
                                  ? 'Save Disabled (Verification Required)'
                                  : 'Save Skills',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                              ),
                            ),
                    ),
                  ),
                  if (disableSave)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        disableSaveForVehicle && disableSaveForSensitive
                            ? 'Deselect restricted skills to save general skills, or submit required verifications.'
                            : (disableSaveForVehicle
                                ? 'Deselect vehicle skills to save general skills, or open Vehicle Verification form.'
                                : 'Deselect sensitive skills to save general skills, or send onboarding request.'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Color(0xFF64748B),
                          height: 1.35,
                          fontFamilyFallback: ['Roboto', 'Arial', 'sans-serif'],
                        ),
                        textAlign: TextAlign.center,
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
}

// â”€â”€ KYC card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _KycCard extends StatelessWidget {
  final User? user;
  final VoidCallback onStart;
  const _KycCard({required this.user, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final isVerified = user?.isKycVerified ?? false;
    final kycStatus = user?.kycStatus;
    final canReapply = user?.canReapplyKyc ?? true;
    final rem = user?.kycReapplyRemaining ?? Duration.zero;

    final IconData icon;
    final String label;
    final String subtitle;
    final Color bgColor;
    final Color borderColor;
    final Color primaryColor;
    final String buttonLabel;

    if (isVerified) {
      icon = Icons.verified_rounded;
      label = 'KYC Verified';
      subtitle = 'Your identity is verified.';
      bgColor = const Color(0xFFECFDF5);
      borderColor = const Color(0xFFA7F3D0);
      primaryColor = const Color(0xFF059669);
      buttonLabel = '';
    } else if (kycStatus == 'pending') {
      icon = Icons.hourglass_top_rounded;
      label = 'KYC Pending';
      subtitle = 'Under review (completes in 24 hrs).';
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFFDE68A);
      primaryColor = const Color(0xFFD97706);
      buttonLabel = 'View Status';
    } else if (kycStatus == 'rejected') {
      icon = Icons.cancel_outlined;
      label = 'KYC Rejected';
      bgColor = const Color(0xFFFEE2E2);
      borderColor = const Color(0xFFFECACA);
      primaryColor = const Color(0xFFDC2626);
      if (!canReapply) {
        final hours = rem.inHours;
        final minutes = rem.inMinutes % 60;
        subtitle = 'Rejected. Reapply in ${hours}h ${minutes}m (24h cooldown).';
        buttonLabel = 'View Status';
      } else {
        subtitle = 'Rejected. 24h cooldown passed — ready to reapply.';
        buttonLabel = 'Reapply';
      }
    } else {
      icon = Icons.badge_outlined;
      label = 'KYC Not Verified';
      subtitle = 'Verify to build trust & unlock tasks.';
      bgColor = const Color(0xFFF8FAFC);
      borderColor = const Color(0xFFE2E8F0);
      primaryColor = const Color(0xFF64748B);
      buttonLabel = 'Start KYC';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (buttonLabel.isNotEmpty)
            TextButton(
              onPressed: onStart,
              style: TextButton.styleFrom(
                foregroundColor: primaryColor == const Color(0xFF64748B)
                    ? const Color(0xFF2563EB)
                    : primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                buttonLabel,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// â”€â”€ Profile Role Switcher (Poster vs Helper) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _ProfileRoleSwitcher extends StatelessWidget {
  final String currentMode;
  final ValueChanged<String> onModeChanged;

  const _ProfileRoleSwitcher({
    required this.currentMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isPoster = currentMode == 'poster';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 20, color: Color(0xFF0F172A)),
                  SizedBox(width: 8),
                  Text(
                    'Profile Mode',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPoster ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isPoster ? const Color(0xFFBFDBFE) : const Color(0xFFA7F3D0),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: isPoster ? const Color(0xFF2563EB) : const Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isPoster ? 'Poster Active' : 'Helper Active',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isPoster ? const Color(0xFF2563EB) : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RoleCard(
                  title: 'Poster Profile',
                  subtitle: 'Post tasks & hire',
                  icon: Icons.post_add_rounded,
                  isSelected: isPoster,
                  onTap: () => onModeChanged('poster'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RoleCard(
                  title: 'Helper Profile',
                  subtitle: 'Accept tasks & earn',
                  icon: Icons.handshake_rounded,
                  isSelected: !isPoster,
                  onTap: () => onModeChanged('helper'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Color(0xFF2563EB),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPoster
                        ? 'Poster Mode: You can post tasks. Helper task alerts are paused.'
                        : 'Helper Mode: You can accept tasks and receive real-time task alerts.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E40AF),
                      height: 1.35,
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
}

class _RoleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const selectedColor = Color(0xFF2563EB);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? selectedColor : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFDBEAFE)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    icon,
                    size: 18,
                    color: selectedColor,
                  ),
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 19,
                    color: selectedColor,
                  )
                else
                  Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: isSelected ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 11.5,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Section header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: AppColors.dark));
}

// â”€â”€ Empty skills hint â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _EmptySkillsHint extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptySkillsHint({required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAdd,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.add_circle_outline, color: AppColors.gray),
            SizedBox(width: 10),
            Expanded(
              child: Text('Add your skills to get AI-matched tasks',
                  style: TextStyle(color: AppColors.gray)),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Shared widgets â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String? badge;
  final Color? badgeColor;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badge,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    const effectiveContainerColor = Color(0xFFEFF6FF);
    const effectiveIconColor = Color(0xFF2563EB);
    final bColor = badgeColor ?? const Color(0xFFD97706);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: effectiveContainerColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: effectiveIconColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFDE68A),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          badge!,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: bColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
