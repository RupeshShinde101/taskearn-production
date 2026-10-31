import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

/// List of sensitive skills requiring admin physical verification
const List<String> kSensitiveSkills = [
  'Cleaning',
  'Delivery',
  'Driving',
  'Cooking',
  'Plumbing',
  'Electrical',
  'Carpentry',
  'Moving & Packing',
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
  late final TextEditingController _idNumberCtrl;
  late final TextEditingController _notesCtrl;

  String _govtIdType = 'Aadhaar Card';
  String _preferredSlot = 'Morning (10:00 AM – 01:00 PM)';
  bool _declarationAccepted = false;
  bool _submitting = false;

  final List<String> _idTypes = const [
    'Aadhaar Card',
    'PAN Card',
    'Voter ID Card',
    'Driving License',
  ];

  final List<String> _timeSlots = const [
    'Morning (10:00 AM – 01:00 PM)',
    'Afternoon (02:00 PM – 05:00 PM)',
    'Evening (05:00 PM – 08:00 PM)',
    'Weekend Slot (Saturday / Sunday)',
  ];

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _addressCtrl = TextEditingController();
    _primaryPhoneCtrl = TextEditingController(text: user?.phone ?? '');
    _altPhoneCtrl = TextEditingController();
    _idNumberCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _primaryPhoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _idNumberCtrl.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
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

    final auth = context.read<AuthProvider>();
    final user = auth.user;

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
      govtIdType: _govtIdType,
      govtIdNumber: _idNumberCtrl.text.trim(),
      preferredSlot: _preferredSlot,
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
                'Your physical onboarding request for sensitive skills has been successfully dispatched to the Workmate4u Admin team.\n\nOur verification agent will contact your primary or alternative number within 24–48 hours to schedule your physical in-person verification visit.',
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
              // ── Top Header Notice Card ──────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF4F46E5).withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
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
                            'Admin Physical Verification',
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
                      'For client safety and community trust, tasks involving in-home services, transit, caregiving, or technical trades require physical in-person verification by our administrative team.',
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

              // ── Selected Sensitive Skills Chip Banner ───────────────────────
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
                          'Sensitive Skills Under Review',
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

              // ── Form Card ──────────────────────────────────────────────────
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

                      // 5. Government ID Type & Number *
                      _buildFieldLabel('Government ID Proof'),
                      Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<String>(
                              value: _govtIdType,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              items: _idTypes.map((type) {
                                return DropdownMenuItem(
                                  value: type,
                                  child: Text(type, style: const TextStyle(fontSize: 13)),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _govtIdType = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: _idNumberCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'ID Number',
                                prefixIcon: const Icon(Icons.badge_outlined, color: AppColors.primary, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'ID number is required';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // 6. Preferred In-Person Verification Slot *
                      _buildFieldLabel('Preferred In-Person Verification Slot'),
                      DropdownButtonFormField<String>(
                        value: _preferredSlot,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: _timeSlots.map((slot) {
                          return DropdownMenuItem(
                            value: slot,
                            child: Text(slot, style: const TextStyle(fontSize: 13)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _preferredSlot = val);
                        },
                      ),

                      const SizedBox(height: 16),

                      // 7. Additional Experience / Notes (Optional)
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

                      // ── Request Onboarding Button ──────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4F46E5).withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
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
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.send_rounded, color: Colors.white, size: 20),
                                      SizedBox(width: 8),
                                      Text(
                                        'Request Onboarding',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
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
