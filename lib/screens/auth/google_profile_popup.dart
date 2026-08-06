import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

/// Popup shown immediately after a successful Google sign-up.
///
/// The account is already created — this collects the remaining required
/// info (name, phone, DOB, terms) and calls updateGoogleProfile().
class GoogleProfilePopup extends StatefulWidget {
  final String? googleName;
  final String? photoUrl;
  final String? email;

  const GoogleProfilePopup({
    super.key,
    this.googleName,
    this.photoUrl,
    this.email,
  });

  static Future<void> show(
    BuildContext context, {
    String? googleName,
    String? photoUrl,
    String? email,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<AuthProvider>(),
        child: GoogleProfilePopup(
          googleName: googleName,
          photoUrl: photoUrl,
          email: email,
        ),
      ),
    );
  }

  @override
  State<GoogleProfilePopup> createState() => _GoogleProfilePopupState();
}

class _GoogleProfilePopupState extends State<GoogleProfilePopup> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  DateTime? _dob;
  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.googleName ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  int _ageInYears(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  void _msg(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().length < 2) {
      _msg('Please enter your full name (at least 2 characters).');
      return;
    }
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      _msg('Please enter a valid 10-digit phone number.');
      return;
    }
    if (_dob == null) {
      _msg('Please select your date of birth.');
      return;
    }
    if (_ageInYears(_dob!) < 16) {
      _msg('You must be at least 16 years old to join WorkMate4U.');
      return;
    }
    if (!_agreeTerms || !_agreePrivacy) {
      _msg('Please accept both the Terms & Conditions and Privacy Policy.');
      return;
    }

    setState(() => _submitting = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateGoogleProfile(
      name: _nameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      dob: _dob,
      termsAcceptedAt: DateTime.now().toUtc().toIso8601String(),
    );
    if (!mounted) return;

    setState(() => _submitting = false);
    if (!ok) {
      // Show error briefly but don't block — account is already created,
      // user can update their profile from settings later.
      _msg(auth.error ?? 'Profile saved partially. You can update it later.');
    }
    // Always close the popup and proceed to home.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Handle bar ──────────────────────────────────────────
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Header ───────────────────────────────────────────────
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor:
                        AppColors.primary.withValues(alpha: 0.12),
                    backgroundImage: widget.photoUrl != null
                        ? NetworkImage(widget.photoUrl!)
                        : null,
                    child: widget.photoUrl == null
                        ? Text(
                            (widget.googleName?.isNotEmpty == true
                                    ? widget.googleName![0]
                                    : 'G')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Complete your profile',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dark,
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (widget.email != null && widget.email!.isNotEmpty)
                          Text(
                            widget.email!,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.gray),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Just a few details required to get you started.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.gray, height: 1.4),
              ),
              const SizedBox(height: 20),

              // ── Full Name ─────────────────────────────────────────────
              _Field(
                controller: _nameCtrl,
                hint: 'Full Name',
                icon: Icons.person_outline_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),

              // ── Phone ────────────────────────────────────────────────
              _Field(
                controller: _phoneCtrl,
                hint: 'Phone number',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),

              // ── DOB picker ───────────────────────────────────────────
              GestureDetector(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _dob ??
                        DateTime(now.year - 20, now.month, now.day),
                    firstDate: DateTime(1920),
                    lastDate: DateTime(now.year - 13, now.month, now.day),
                    helpText: 'Date of Birth',
                  );
                  if (picked != null && mounted) {
                    setState(() => _dob = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 20, color: AppColors.grayLight),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _dob != null
                              ? DateFormat('dd / MM / yyyy').format(_dob!)
                              : 'Date of Birth',
                          style: TextStyle(
                            color: _dob != null
                                ? AppColors.dark
                                : AppColors.grayLight,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down_rounded,
                          color: AppColors.grayLight),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Terms checkboxes ──────────────────────────────────────
              _CheckRow(
                value: _agreeTerms,
                onTap: () => setState(() => _agreeTerms = !_agreeTerms),
                label: 'I agree to the Terms & Conditions',
              ),
              const SizedBox(height: 10),
              _CheckRow(
                value: _agreePrivacy,
                onTap: () => setState(() => _agreePrivacy = !_agreePrivacy),
                label: 'I agree to the Privacy Policy',
              ),
              const SizedBox(height: 24),

              // ── Complete button ───────────────────────────────────────
              GradientButton(
                label: 'Complete Profile',
                loading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
              const SizedBox(height: 10),

              // ── Skip ──────────────────────────────────────────────────
              Center(
                child: TextButton(
                  onPressed:
                      _submitting ? null : () => Navigator.of(context).pop(),
                  child: const Text(
                    'Skip for now',
                    style: TextStyle(
                      color: AppColors.gray,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
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
}

// ── Shared input field ────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: const TextStyle(fontSize: 15, color: AppColors.dark),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppColors.grayLight, fontSize: 15),
        prefixIcon: Icon(icon, size: 20, color: AppColors.grayLight),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ── Checkbox row ──────────────────────────────────────────────────────────────

class _CheckRow extends StatelessWidget {
  final bool value;
  final VoidCallback onTap;
  final String label;

  const _CheckRow({
    required this.value,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: value ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: value ? AppColors.primary : AppColors.border,
                width: 1.5,
              ),
            ),
            child: value
                ? const Icon(Icons.check_rounded,
                    size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.dark, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
