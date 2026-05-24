import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

// ── Rank colour helper ──────────────────────────────────────────────────────
Color _rankColor(String rank) {
  switch (rank) {
    case 'Elite':    return const Color(0xFF7C3AED);
    case 'Platinum': return const Color(0xFF0EA5E9);
    case 'Gold':     return const Color(0xFFF59E0B);
    case 'Silver':   return const Color(0xFF6B7280);
    case 'Bronze':   return const Color(0xFFB45309);
    default:         return AppColors.gray;
  }
}

// ── All available skills the user can select ──────────────────────────────────
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
  List<Map<String, dynamic>> _reviews = [];
  bool _reviewsLoading = false;
  bool _showReviews = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().refreshUser();
      _loadReviews();
    });
  }

  Future<void> _refresh() async {
    await Future.wait([
      context.read<AuthProvider>().refreshUser(),
      _loadReviews(),
    ]);
  }

  Future<void> _loadReviews() async {
    final userId = context.read<AuthProvider>().user?.id;
    if (userId == null || userId.isEmpty) return;
    if (!mounted) return;
    setState(() => _reviewsLoading = true);
    try {
      final data = await ApiService.get('/user/$userId/reviews');
      if (!mounted) return;
      final list = (data['reviews'] as List? ?? []);
      setState(() {
        _reviews = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _reviewsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditDialog(context, auth),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar, name, email, rating ──────────────────────────────
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => _showEditDialog(context, auth),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: user?.avatar != null
                              ? NetworkImage(user!.avatar!)
                              : null,
                          backgroundColor: AppColors.light,
                          child: user?.avatar == null
                              ? Text(
                                  user?.name.isNotEmpty == true
                                      ? user!.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary))
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: AppColors.gradient),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(user?.name ?? '',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dark)),
                  Text(user?.email ?? '',
                      style: const TextStyle(color: AppColors.gray)),
                  if (user?.phone != null && user!.phone!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(user.phone!,
                          style: const TextStyle(
                              color: AppColors.grayLight, fontSize: 13)),
                    ),
                  if (user?.rating != null && user!.rating > 0) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(5, (i) {
                          final filled = i < user.rating.floor();
                          final half = !filled && i < user.rating;
                          return Icon(
                            filled
                                ? Icons.star
                                : (half ? Icons.star_half : Icons.star_border),
                            color: AppColors.warning,
                            size: 20,
                          );
                        }),
                        const SizedBox(width: 6),
                        Text(
                          user.rating.toStringAsFixed(1),
                          style: const TextStyle(
                              color: AppColors.gray,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Stats grid (2×2: Completed | Posted / Rating | Rank) ─────────
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
                child: Column(
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          _StatCell(
                            label: 'Tasks\nCompleted',
                            value: '${user?.tasksCompleted ?? 0}',
                          ),
                          const VerticalDivider(width: 1),
                          _StatCell(
                            label: 'Tasks\nPosted',
                            value: '${user?.tasksPosted ?? 0}',
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 20),
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          _StatCell(
                            label: 'Rating',
                            value: user != null && user.rating > 0
                                ? '${user.rating.toStringAsFixed(1)} ★'
                                : '— ★',
                            valueColor: user != null && user.rating > 0
                                ? AppColors.warning
                                : AppColors.gray,
                          ),
                          const VerticalDivider(width: 1),
                          _StatCell(
                            label: 'Rank',
                            value: user?.rank ?? 'New',
                            valueColor: _rankColor(user?.rank ?? 'New'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── KYC card ──────────────────────────────────────────────────
            _KycCard(
              isVerified: user?.isKycVerified ?? false,
              kycStatus: user?.kycStatus,
              onStart: () => context.push('/kyc'),
            ),

            const SizedBox(height: 16),

            // ── Bio section ───────────────────────────────────────────────
            if (user?.bio != null && user!.bio!.isNotEmpty) ...[
              const _SectionHeader('About Me'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.light,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(user.bio!,
                    style: const TextStyle(
                        color: AppColors.dark, height: 1.5)),
              ),
              const SizedBox(height: 16),
            ],

            // ── Skills section ────────────────────────────────────────────
            Row(
              children: [
                const _SectionHeader('My Skills'),
                const Spacer(),
                if (user?.skills != null && user!.skills.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined,
                        size: 18, color: AppColors.gray),
                    onPressed: () => _showSkillsDialog(context, auth),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 18,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (user?.skills == null || user!.skills.isEmpty)
              _EmptySkillsHint(onAdd: () => _showSkillsDialog(context, auth))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: user.skills
                    .map((s) => Chip(
                          label: Text(s),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          labelStyle: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500),
                          side: BorderSide(
                              color: AppColors.primary.withValues(alpha: 0.3)),
                        ))
                    .toList(),
              ),

            const SizedBox(height: 20),

            // ── Reviews Received ──────────────────────────────────────────
            InkWell(
              onTap: () => setState(() => _showReviews = !_showReviews),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Text(
                      'Reviews Received',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_reviews.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${_reviews.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Icon(
                      _showReviews
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.gray,
                    ),
                  ],
                ),
              ),
            ),
            if (_showReviews) ...[
              const SizedBox(height: 8),
              if (_reviewsLoading)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator()))
              else if (_reviews.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.light,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text('No reviews yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.gray)),
                )
              else
                Column(
                  children: _reviews.map((r) => _ReviewCard(review: r)).toList(),
                ),
            ],

            const SizedBox(height: 20),

            // ── Menu items ────────────────────────────────────────────────
            Card(
              child: Column(
                children: [
                  _MenuItem(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'My Wallet',
                    onTap: () => context.push('/wallet'),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.card_giftcard_outlined,
                    title: 'Referral & Rewards',
                    onTap: () => context.push('/referral'),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    onTap: () => context.push('/notifications'),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.security_outlined,
                    title: 'Security',
                    onTap: () => _launch('https://workmate4u.com/safety'),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.lock_reset_outlined,
                    title: 'Change Password',
                    onTap: () => _showChangePasswordDialog(context, auth),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.help_outline,
                    title: 'Help & Support',
                    onTap: () => _launch('https://workmate4u.com/help'),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    onTap: () => _launch('https://workmate4u.com/privacy'),
                  ),
                  const Divider(height: 1),
                  _MenuItem(
                    icon: Icons.description_outlined,
                    title: 'Terms of Service',
                    onTap: () => _launch('https://workmate4u.com/terms'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Sign out ──────────────────────────────────────────────────
            Card(
              child: _MenuItem(
                icon: Icons.logout,
                title: 'Sign Out',
                textColor: AppColors.danger,
                iconColor: AppColors.danger,
                onTap: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Sign Out',
                                style: TextStyle(color: AppColors.danger))),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await auth.logout();
                  }
                },
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    ),
    );
  }

  // ── Launch URL in external browser ────────────────────────────────────────
  static Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  // ── Edit personal details bottom sheet (pencil icon / avatar) ──────────────
  void _showEditDialog(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _EditProfileSheet(auth: auth),
    );
  }

  // ── Edit skills bottom sheet ──────────────────────────────────────────────
  void _showSkillsDialog(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => _EditSkillsSheet(auth: auth),
    );
  }

  // ── Change Password dialog ────────────────────────────────────────────────
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

// ── Edit profile sheet (stateful so it manages skill selection + feedback) ───
class _EditProfileSheet extends StatefulWidget {
  final AuthProvider auth;
  const _EditProfileSheet({required this.auth});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.auth.user?.name);
    _bioCtrl   = TextEditingController(text: widget.auth.user?.bio);
    _phoneCtrl = TextEditingController(text: widget.auth.user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _saving = true);
    final ok = await widget.auth.updateProfile(
      name: _nameCtrl.text,
      bio: _bioCtrl.text,
      phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
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
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
            const SizedBox(height: 12),
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Bio',
                  hintText: 'Tell task posters about yourself...',
                  prefixIcon: Icon(Icons.info_outline)),
            ),

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
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

// ── Edit skills sheet ─────────────────────────────────────────────────────────
class _EditSkillsSheet extends StatefulWidget {
  final AuthProvider auth;
  const _EditSkillsSheet({required this.auth});

  @override
  State<_EditSkillsSheet> createState() => _EditSkillsSheetState();
}

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
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await widget.auth.updateProfile(skills: _selectedSkills);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? 'Skills updated!'
            : (widget.auth.error ?? 'Failed to save skills. Please try again.')),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text('My Skills',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text('Select skills so AI can match you with relevant tasks',
                  style: TextStyle(color: AppColors.gray, fontSize: 12)),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kAllSkills
                  .map((skill) => FilterChip(
                        label: Text(skill),
                        selected: _selectedSkills.contains(skill),
                        onSelected: (_) => _toggleSkill(skill),
                        selectedColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        checkmarkColor: AppColors.primary,
                        labelStyle: TextStyle(
                            color: _selectedSkills.contains(skill)
                                ? AppColors.primary
                                : AppColors.gray,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                        side: BorderSide(
                            color: _selectedSkills.contains(skill)
                                ? AppColors.primary
                                : AppColors.border),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save Skills'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── KYC card ─────────────────────────────────────────────────────────────────
class _KycCard extends StatelessWidget {
  final bool isVerified;
  final String? kycStatus;
  final VoidCallback onStart;
  const _KycCard(
      {required this.isVerified, required this.kycStatus, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final (icon, label, subtitle, color) = isVerified
        ? (Icons.verified, 'KYC Verified', 'Your identity is verified.', AppColors.success)
        : kycStatus == 'pending'
            ? (Icons.hourglass_top_rounded, 'KYC Pending', 'Under review (24-48 hrs).', AppColors.warning)
            : kycStatus == 'rejected'
                ? (Icons.cancel_outlined, 'KYC Rejected', 'Please re-submit documents.', AppColors.danger)
                : (Icons.badge_outlined, 'KYC Not Verified', 'Verify to build trust & unlock tasks.', AppColors.gray);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        const TextStyle(color: AppColors.gray, fontSize: 12)),
              ],
            ),
          ),
          if (!isVerified && kycStatus != 'pending')
            TextButton(
              onPressed: onStart,
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: const Text('Start KYC'),
            ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
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

// ── Empty skills hint ─────────────────────────────────────────────────────────
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

// ── Shared widgets ────────────────────────────────────────────────────────────
class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _StatCell({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: valueColor ?? AppColors.dark)),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.gray, fontSize: 11, height: 1.3)),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? textColor;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.textColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? AppColors.gray, size: 22),
      title: Text(title,
          style: TextStyle(
              color: textColor ?? AppColors.dark,
              fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.grayLight),
      onTap: onTap,
    );
  }
}

// ── Individual review card ────────────────────────────────────────────────────
class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final rating = (review['rating'] as num?)?.toDouble() ?? 0;
    final raterName = review['rater_name'] as String? ?? 'Anonymous';
    final taskTitle = review['task_title'] as String? ?? 'Task';
    final comment = (review['review'] as String? ?? '').trim();
    final createdAt = review['created_at'] as String?;
    String? dateStr;
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        dateStr = '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  raterName.isNotEmpty ? raterName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(raterName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.dark,
                            fontSize: 13)),
                    Text(taskTitle,
                        style: const TextStyle(
                            color: AppColors.gray, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: List.generate(5, (i) => Icon(
                      i < rating.round() ? Icons.star : Icons.star_border,
                      color: AppColors.warning,
                      size: 14,
                    )),
                  ),
                  if (dateStr != null)
                    Text(dateStr,
                        style: const TextStyle(
                            color: AppColors.grayLight, fontSize: 10)),
                ],
              ),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(comment,
                style: const TextStyle(
                    color: AppColors.dark, fontSize: 13, height: 1.4)),
          ],
        ],
      ),
    );
  }
}
