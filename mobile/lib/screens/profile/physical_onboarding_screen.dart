import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/verification_cooldown_banner.dart';

/// List of sensitive skills requiring admin physical verification
const List<String> kSensitiveSkills = [
  'Cleaning',
  'Cooking',
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Pet Care',
  'Babysitting',
  'Elder Care',
];

/// Helper check to determine if any given skills are sensitive
bool hasSensitiveSkill(Iterable<String> skills) {
  final sensitiveSet = kSensitiveSkills.map((s) => s.toLowerCase()).toSet();
  return skills.any((s) => sensitiveSet.contains(s.trim().toLowerCase()));
}

/// Helper filter to extract sensitive skills from a list
List<String> getSensitiveSkillsFrom(Iterable<String> skills) {
  final sensitiveSet = kSensitiveSkills.map((s) => s.toLowerCase()).toSet();
  return skills.where((s) => sensitiveSet.contains(s.trim().toLowerCase())).toList();
}

class PhysicalOnboardingScreen extends StatefulWidget {
  final List<String>? initialSkills;
  const PhysicalOnboardingScreen({super.key, this.initialSkills});

  @override
  State<PhysicalOnboardingScreen> createState() => _PhysicalOnboardingScreenState();
}

class _PhysicalOnboardingScreenState extends State<PhysicalOnboardingScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _primaryPhoneCtrl;
  late final TextEditingController _altPhoneCtrl;
  late final TextEditingController _notesCtrl;

  bool _declarationAccepted = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _addressCtrl = TextEditingController();
    _primaryPhoneCtrl = TextEditingController(text: user?.phone ?? '');
    _altPhoneCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _primaryPhoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Widget _buildFieldLabel(String label, {bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text.rich(
        TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
          children: [
            if (isRequired)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '0m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = context.read<AuthProvider>();
    final user = auth.user;

    // Check 24-hour cooldown if previously rejected
    if (user != null && !user.canReapplyPhysicalVerification) {
      final rem = user.physicalVerificationReapplyRemaining ?? Duration.zero;
      final hours = rem.inHours;
      final minutes = rem.inMinutes % 60;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Onboarding verification was recently rejected. You can reapply in ${hours}h ${minutes}m.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (!_declarationAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the physical verification declaration to proceed.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // Use initialSkills, or user's active sensitive skills, or default full sensitive skills list
    List<String> targetSkills = widget.initialSkills != null && widget.initialSkills!.isNotEmpty
        ? getSensitiveSkillsFrom(widget.initialSkills!)
        : getSensitiveSkillsFrom(user?.skills ?? []);

    if (targetSkills.isEmpty) {
      targetSkills = user?.skills.isNotEmpty == true
          ? user!.skills
          : const ['Cleaning', 'Plumbing', 'Electrical'];
    }

    setState(() => _submitting = true);

    final ok = await auth.submitPhysicalOnboardingRequest(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      primaryPhone: _primaryPhoneCtrl.text.trim(),
      alternativePhone: _altPhoneCtrl.text.trim(),
      skills: targetSkills,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Failed to submit request. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _showSuccessDialog() {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_rounded,
                    color: Color(0xFF059669), size: 38),
              ),
              const SizedBox(height: 16),
              const Text(
                'Verification Request Sent! 🛡️',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF065F46),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your physical onboarding request for sensitive skills has been successfully dispatched to the Workmate4u Admin team.\n\nOur verification agent will contact your primary or alternative number to complete your physical verification review within 24 hours.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF475569),
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    context.pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    final sensitiveSkillsToDisplay = widget.initialSkills != null && widget.initialSkills!.isNotEmpty
        ? getSensitiveSkillsFrom(widget.initialSkills!)
        : getSensitiveSkillsFrom(user?.skills ?? []);

    final skillsList = sensitiveSkillsToDisplay.isNotEmpty
        ? sensitiveSkillsToDisplay
        : kSensitiveSkills.take(6).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Physical Onboarding Request'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // â”€â”€ Top Header Notice Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.shield_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Onboarding verification',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'For client safety and community trust, tasks involving in-home services, transit, caregiving, or technical trades require onboarding verification by our administrative team.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // ── Cooldown & Review Status Banner ──────────────────────────────
              VerificationCooldownBanner(
                verificationTitle: 'Physical Onboarding',
                status: user?.physicalVerificationStatus ?? 'none',
                rejectionReason: user?.physicalVerificationRejectReason,
                rejectedAt: user?.physicalVerificationRejectedAt,
              ),

              const SizedBox(height: 16),

              // â”€â”€ Selected Sensitive Skills Chip Banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_outlined, color: Color(0xFFD97706), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Skill verification and onbaording',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: skillsList.map((skill) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFFD97706), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                skill,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF78350F),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // â”€â”€ Form Card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Helper Onboarding Form',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'All marked fields are mandatory for physical inspection and background validation.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 18),

                      // 1. Full Legal Name *
                      _buildFieldLabel('Full Legal Name'),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          hintText: 'Enter your legal name as on ID proof',
                          prefixIcon: const Icon(Icons.person_outline, color: AppColors.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Full legal name is required';
                          if (v.trim().length < 3) return 'Name must be at least 3 characters';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // 2. Complete Residential Address *
                      _buildFieldLabel('Complete Residential Address'),
                      TextFormField(
                        controller: _addressCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Flat/House No., Society/Street, Landmark, City & PIN code',
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 40),
                            child: Icon(Icons.home_outlined, color: AppColors.primary),
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Complete residential address is required';
                          if (v.trim().length < 10) return 'Please provide full address with city and PIN';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // 3. Primary Mobile Number *
                      _buildFieldLabel('Primary Mobile Number'),
                      TextFormField(
                        controller: _primaryPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                          hintText: '10-digit primary contact number',
                          prefixIcon: const Icon(Icons.phone_outlined, color: AppColors.primary),
                          prefixText: '+91 ',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          final clean = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (clean.isEmpty) return 'Primary mobile number is required';
                          if (clean.length != 10) return 'Enter a valid 10-digit mobile number';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // 4. Alternative Mobile Number *
                      _buildFieldLabel('Alternative Mobile Number'),
                      TextFormField(
                        controller: _altPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                          hintText: 'Secondary or family contact number',
                          prefixIcon: const Icon(Icons.phone_android_outlined, color: AppColors.primary),
                          prefixText: '+91 ',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          final clean = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (clean.isEmpty) return 'Alternative mobile number is required';
                          if (clean.length != 10) return 'Enter a valid 10-digit mobile number';
                          final primaryClean = _primaryPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                          if (clean == primaryClean) {
                            return 'Alternative number must be different from primary number';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // 5. Additional Experience / Notes (Optional)
                      _buildFieldLabel('Experience / Additional Remarks', isRequired: false),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'e.g., 3 years of electrical experience, valid driving license, etc.',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // 8. Mandatory Declaration Checkbox *
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _declarationAccepted ? AppColors.primary : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _declarationAccepted,
                              activeColor: AppColors.primary,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (val) {
                                setState(() => _declarationAccepted = val ?? false);
                              },
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _declarationAccepted = !_declarationAccepted);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text.rich(
                                    TextSpan(
                                      text: 'I declare that the address and contact details provided are authentic. I agree to an in-person physical background and skill verification by an authorized Workmate4u admin or agent.',
                                      style: TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.4),
                                      children: [
                                        TextSpan(
                                          text: ' *',
                                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // â”€â”€ Request Onboarding Button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      Builder(
                        builder: (context) {
                          final isVerified = user?.physicalVerificationStatus == 'verified';
                          final isPending = user?.physicalVerificationStatus == 'pending';
                          final isRejected = user?.physicalVerificationStatus == 'rejected';
                          final canReapply = user?.canReapplyPhysicalVerification ?? true;
                          final cooldownActive = isRejected && !canReapply;

                          final bool isDisabled = _submitting || isVerified || isPending || cooldownActive;

                          String buttonText = 'Request Onboarding';
                          IconData buttonIcon = Icons.send_rounded;
                          Color buttonBg = AppColors.primary;

                          if (isVerified) {
                            buttonText = 'Onboarding Verified';
                            buttonIcon = Icons.verified_user_rounded;
                            buttonBg = const Color(0xFF059669);
                          } else if (isPending) {
                            buttonText = 'Under Review (Completes in 24 hrs)';
                            buttonIcon = Icons.hourglass_top_rounded;
                            buttonBg = const Color(0xFFD97706);
                          } else if (cooldownActive) {
                            buttonText = 'Reapply in ${_formatDuration(user!.physicalVerificationReapplyRemaining)}';
                            buttonIcon = Icons.timer_outlined;
                            buttonBg = const Color(0xFFDC2626);
                          } else if (isRejected) {
                            buttonText = 'Reapply Onboarding Request';
                            buttonIcon = Icons.refresh_rounded;
                            buttonBg = AppColors.primary;
                          }

                          return SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: isDisabled ? buttonBg.withValues(alpha: 0.6) : buttonBg,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: isDisabled
                                    ? null
                                    : [
                                        BoxShadow(
                                          color: buttonBg.withValues(alpha: 0.25),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                              ),
                              child: ElevatedButton(
                                onPressed: isDisabled ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  disabledForegroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _submitting
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(buttonIcon, color: Colors.white, size: 20),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              buttonText,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                letterSpacing: 0.3,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          );
                        },
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
}
