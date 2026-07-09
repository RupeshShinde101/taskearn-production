import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
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
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 2) ? 'Enter your full name' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                  validator: (v) {
                    if (v == null || !v.contains('@')) return 'Enter valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                    if (digits.isEmpty) return 'Phone number is required';
                    if (digits.length < 10) return 'Enter a valid phone number';
                    return null;
                  },
                ),

                // ── Date of Birth ──────────────────────────────────────────
                FormField<DateTime>(
                  initialValue: _dob,
                  validator: (v) =>
                      v == null ? 'Date of birth is required' : null,
                  builder: (state) => GestureDetector(
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _dob ?? DateTime(now.year - 20, now.month, now.day),
                        firstDate: DateTime(1920),
                        lastDate:
                            DateTime(now.year - 13, now.month, now.day),
                        helpText: 'Select Date of Birth',
                        fieldLabelText: 'Date of Birth',
                      );
                      if (picked != null) {
                        setState(() => _dob = picked);
                        state.didChange(picked); // pass value directly, not via _dob
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date of Birth',
                        prefixIcon: const Icon(Icons.cake_outlined),
                        suffixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            size: 18),
                        errorText: state.errorText,
                        border: const OutlineInputBorder(),
                        enabledBorder: const OutlineInputBorder(
                          borderSide:
                              BorderSide(color: AppColors.border),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.primary, width: 1.5),
                        ),
                        errorBorder: const OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.red),
                        ),
                        focusedErrorBorder: const OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.red, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 16),
                      ),
                      child: Text(
                        state.value != null
                            ? DateFormat('dd MMM yyyy').format(state.value!)
                            : 'Select your date of birth',
                        style: TextStyle(
                          fontSize: 16,
                          color: state.value != null
                              ? AppColors.dark
                              : AppColors.gray,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
                const SizedBox(height: 14),

                // ── Invite Code ────────────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
                  child: TextFormField(
                    controller: _inviteCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Invite Code',
                      hintText: 'e.g. WORKMATE2026',
                      prefixIcon: Icon(Icons.vpn_key_outlined,
                          color: AppColors.primary),
                      helperText:
                          'Required during closed beta — get your code from the team or a referral link.',
                      helperMaxLines: 2,
                      helperStyle:
                          TextStyle(color: AppColors.gray, fontSize: 11),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: 14),
                TextFormField(
                  controller: _referralCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Referral Code (optional)',
                    prefixIcon: Icon(Icons.card_giftcard_outlined),
                    hintText: 'Friend\'s referral code for bonus',
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Checkbox(
                      value: _agreeTerms,
                      activeColor: AppColors.primary,
                      onChanged: (v) => setState(() => _agreeTerms = v ?? false),
                    ),
                    Expanded(
                      child: Wrap(
                        children: [
                          const Text('I agree to the '),
                          GestureDetector(
                            onTap: () {},
                            child: const Text('Terms & Conditions',
                                style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                GradientButton(
                  label: 'Create Account',
                  loading: auth.isLoading,
                  onPressed: _register,
                ),
                const SizedBox(height: 20),

                // ── OR divider ─────────────────────────────────────────────
                const Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.border)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                          style:
                              TextStyle(color: AppColors.gray, fontSize: 13)),
                    ),
                    Expanded(child: Divider(color: AppColors.border)),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Google Sign-Up button ──────────────────────────────────
                OutlinedButton(
                  onPressed: auth.isLoading ? null : _signUpWithGoogle,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dark,
                    backgroundColor: AppColors.white,
                    side:
                        const BorderSide(color: AppColors.border, width: 1.5),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _GoogleLogo(),
                      const SizedBox(width: 10),
                      const Text(
                        'Sign up with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.dark,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Already have an account? ',
                        style: TextStyle(color: AppColors.gray)),
                    GestureDetector(
                      onTap: () => context.go('/login'),
                      child: const Text('Sign In',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws the Google multicolour "G" logo using a custom painter.
class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
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
