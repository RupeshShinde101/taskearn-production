import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/gradient_button.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  final _referralCtrl = TextEditingController();
  bool _obscure = true;
  bool _agreeTerms = false;
  DateTime? _dob;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _inviteCtrl.dispose();
    _referralCtrl.dispose();
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

  Future<void> _signUpWithGoogle() async {
    if (_inviteCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter your invite code above before signing up with Google')),
      );
      return;
    }
    final phoneDigits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (phoneDigits.isEmpty || phoneDigits.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please enter a valid phone number before signing up with Google')),
      );
      return;
    }
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please select your date of birth above before signing up with Google')),
      );
      return;
    }
    if (_ageInYears(_dob!) < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('You must be at least 16 years old to join WorkMate4U')),
      );
      return;
    }
    if (!_agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms & conditions')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle(
      inviteCode: _inviteCtrl.text.trim(),
      referralCode:
          _referralCtrl.text.trim().isEmpty ? null : _referralCtrl.text.trim(),
      dob: _dob,
      phone: _phoneCtrl.text.trim(),
    );
    if (!mounted) return;

    if (ok) {
      context.go('/home');
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error!)),
      );
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select your date of birth')),
      );
      return;
    }
    if (_ageInYears(_dob!) < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('You must be at least 16 years old to join WorkMate4U')),
      );
      return;
    }
    if (!_agreeTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please accept the terms & conditions')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final ok = await auth.register(
      name: _nameCtrl.text,
      email: _emailCtrl.text,
      password: _passwordCtrl.text,
      phone: _phoneCtrl.text.trim(),
      dob: _dob != null ? DateFormat('yyyy-MM-dd').format(_dob!) : null,
      inviteCode: _inviteCtrl.text.isNotEmpty ? _inviteCtrl.text : null,
      referralCode: _referralCtrl.text.isNotEmpty ? _referralCtrl.text : null,
    );

    if (!mounted) return;

    if (ok) {
      context.go('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Registration failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top bar ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: Color(0xFF1E293B)),
                onPressed: () => context.pop(),
              ),
            ),

            // ── Scrollable form ───────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Heading ──────────────────────────────────────────
                    const Text(
                      'Create your account',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    RichText(
                      text: const TextSpan(
                        style: TextStyle(
                            fontSize: 14, color: Color(0xFF64748B)),
                        children: [
                          TextSpan(text: 'Join '),
                          TextSpan(
                            text: 'W4u',
                            style: TextStyle(
                              color: Color(0xFF6366F1),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                              text:
                                  ' and start your journey today!'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Form ─────────────────────────────────────────────
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _InputField(
                            controller: _nameCtrl,
                            hint: 'Full Name',
                            icon: Icons.person_outline_rounded,
                            textInputAction: TextInputAction.next,
                            validator: (v) =>
                                (v == null || v.trim().length < 2)
                                    ? 'Enter your full name'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          _InputField(
                            controller: _emailCtrl,
                            hint: 'Email address',
                            icon: Icons.mail_outline_rounded,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              if (v == null || !v.contains('@')) {
                                return 'Enter valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          _InputField(
                            controller: _phoneCtrl,
                            hint: 'Phone number',
                            icon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            validator: (v) {
                              final d =
                                  v?.replaceAll(RegExp(r'\D'), '') ??
                                      '';
                              if (d.isEmpty) return 'Required';
                              if (d.length < 10) return 'Invalid number';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // ── DOB picker ──────────────────────────────
                          FormField<DateTime>(
                            initialValue: _dob,
                            validator: (v) => v == null
                                ? 'Date of birth is required'
                                : null,
                            builder: (state) => Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final now = DateTime.now();
                                    final picked =
                                        await showDatePicker(
                                      context: context,
                                      initialDate: _dob ??
                                          DateTime(now.year - 20,
                                              now.month, now.day),
                                      firstDate: DateTime(1920),
                                      lastDate: DateTime(now.year - 13,
                                          now.month, now.day),
                                      helpText: 'Date of Birth',
                                    );
                                    if (picked != null) {
                                      setState(() => _dob = picked);
                                      state.didChange(picked);
                                    }
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                        color: state.hasError
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                            Icons
                                                .calendar_today_outlined,
                                            size: 20,
                                            color: Color(0xFF94A3B8)),
                                        const SizedBox(width: 12),
                                        const Expanded(
                                          child: Text(
                                            'Date of birth',
                                            style: TextStyle(
                                              color: Color(0xFF1E293B),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          state.value != null
                                              ? DateFormat('dd / MM / yyyy')
                                                  .format(state.value!)
                                              : 'DD / MM / YYYY',
                                          style: TextStyle(
                                            color: state.value != null
                                                ? const Color(0xFF1E293B)
                                                : const Color(0xFFADB5BD),
                                            fontSize: 14,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (state.hasError)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 4, left: 12),
                                    child: Text(state.errorText!,
                                        style: const TextStyle(
                                            color: Color(0xFFEF4444),
                                            fontSize: 12)),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ── Password ────────────────────────────────
                          _InputField(
                            controller: _passwordCtrl,
                            hint: 'Password',
                            icon: Icons.lock_outline_rounded,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.next,
                            suffix: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                                color: const Color(0xFF94A3B8),
                              ),
                              onPressed: () => setState(
                                  () => _obscure = !_obscure),
                            ),
                            validator: (v) => (v == null || v.length < 6)
                                ? 'Min 6 characters'
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // ── Invite code ──────────────────────────────
                          _TwoLineField(
                            controller: _inviteCtrl,
                            icon: Icons.vpn_key_outlined,
                            title: 'Invite code (optional)',
                            hint: 'Enter invite code',
                            textCapitalization:
                                TextCapitalization.characters,
                            validator: (v) =>
                                (v == null || v.trim().isEmpty)
                                    ? 'Invite code is required'
                                    : null,
                          ),
                          const SizedBox(height: 12),

                          // ── Referral code ────────────────────────────
                          _TwoLineField(
                            controller: _referralCtrl,
                            icon: Icons.card_giftcard_outlined,
                            title: 'Referral code (optional)',
                            hint: 'Enter referral code',
                          ),
                          const SizedBox(height: 16),

                          // ── Terms ────────────────────────────────────
                          GestureDetector(
                            onTap: () => setState(
                                () => _agreeTerms = !_agreeTerms),
                            child: Row(
                              children: [
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: _agreeTerms
                                        ? const Color(0xFF6366F1)
                                        : Colors.transparent,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                    border: Border.all(
                                      color: _agreeTerms
                                          ? const Color(0xFF6366F1)
                                          : const Color(0xFFCBD5E1),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: _agreeTerms
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 13)
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Wrap(
                                    children: [
                                      const Text(
                                        'I agree to the ',
                                        style: TextStyle(
                                            fontSize: 13,
                                            color: Color(0xFF64748B)),
                                      ),
                                      GestureDetector(
                                        onTap: () {},
                                        child: const Text(
                                          'Terms & Conditions',
                                          style: TextStyle(
                                            color: Color(0xFF6366F1),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Create account button ────────────────────
                          GradientButton(
                            label: 'Create Account',
                            icon: Icons.arrow_forward_rounded,
                            loading: auth.isLoading,
                            onPressed: _register,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    // ── OR divider ──────────────────────────────────────
                    const Row(
                      children: [
                        Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or sign up with',
                            style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                        Expanded(child: Divider(color: Color(0xFFE2E8F0))),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Social row ──────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: _SocialBtn(
                        label: 'Continue with Google',
                        icon: const _GoogleLogo(),
                        onTap: auth.isLoading ? null : _signUpWithGoogle,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ── Sign in link ────────────────────────────────────
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Already have an account? ',
                            style: TextStyle(
                                color: Color(0xFF64748B), fontSize: 14),
                          ),
                          GestureDetector(
                            onTap: () => context.go('/login'),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                color: Color(0xFF6366F1),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Two-line field (title + text input) ─────────────────────────────────────

class _TwoLineField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String title;
  final String hint;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  const _TwoLineField({
    required this.controller,
    required this.icon,
    required this.title,
    required this.hint,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
                TextFormField(
                  controller: controller,
                  textCapitalization: textCapitalization,
                  validator: validator,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF1E293B)),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: const TextStyle(
                        color: Color(0xFFADB5BD), fontSize: 13),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 4),
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

// ── Input field ──────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final void Function(String)? onFieldSubmitted;
  final String? Function(String?)? validator;

  const _InputField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      style: const TextStyle(
        fontSize: 15,
        color: Color(0xFF1E293B),
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFFADB5BD),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon:
            Icon(icon, color: const Color(0xFF94A3B8), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEF4444)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ── Social button ─────────────────────────────────────────────────────────────

class _SocialBtn extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  const _SocialBtn(
      {required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Google "G" logo
class _GoogleLogo extends StatelessWidget {
  final double size;
  const _GoogleLogo({this.size = 24});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}


class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final center = rect.center;
    final radius = size.width / 2;

    canvas.clipPath(Path()..addOval(rect));
    canvas.drawRect(rect, Paint()..color = Colors.white);

    final strokeW = size.width * 0.09;

    void drawArc(double start, double sweep, Color color) {
      canvas.drawArc(
        rect.deflate(strokeW / 2),
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW,
      );
    }

    drawArc(-0.52, 1.57, const Color(0xFF4285F4));
    drawArc(1.05, 1.57, const Color(0xFF34A853));
    drawArc(2.62, 1.57, const Color(0xFFFBBC05));
    drawArc(4.19, 1.57, const Color(0xFFEA4335));

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeW * 1.1;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + radius * 0.9, center.dy),
      paint,
    );
    canvas.drawCircle(
      center,
      radius - strokeW * 1.1,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
