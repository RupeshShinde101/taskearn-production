import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_emailCtrl.text, _passwordCtrl.text);
    if (!mounted) return;

    if (ok) {
      context.go('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.error ?? 'Login failed')),
      );
    }
  }

  Future<void> _loginWithGoogle() async {
    // Show invite code + DOB sheet before triggering Google auth.
    // Closed beta: server always requires an invite code for /auth/google.
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _GoogleSetupSheet(),
    );
    if (result == null || !mounted) return; // user dismissed

    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle(
      inviteCode: result['inviteCode'] as String?,
      dob: result['dob'] as DateTime?,
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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),

              // Logo & headline
              Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      height: 130,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      "India's #1 Local Task Marketplace",
                      style: TextStyle(color: AppColors.gray, fontSize: 14),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              const Text(
                'Welcome back',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sign in to continue',
                style: TextStyle(color: AppColors.gray, fontSize: 14),
              ),

              const SizedBox(height: 24),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Enter email';
                        if (!v.contains('@')) return 'Invalid email';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),

                    // Forgot password
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => context.push('/forgot-password'),
                        child: const Text('Forgot password?'),
                      ),
                    ),

                    const SizedBox(height: 8),
                    GradientButton(
                      label: 'Sign In',
                      loading: auth.isLoading,
                      onPressed: _login,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Divider
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

              // Google Sign-In button
              OutlinedButton(
                onPressed: auth.isLoading ? null : _loginWithGoogle,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dark,
                  backgroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.border, width: 1.5),
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
                      'Continue with Google',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.dark,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Sign up link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account? ",
                      style: TextStyle(color: AppColors.gray)),
                  GestureDetector(
                    onTap: () => context.push('/register'),
                    child: const Text(
                      'Sign Up',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
            ],
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

    // Clip to circle
    canvas.clipPath(Path()..addOval(rect));

    // Background
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

    // Blue (top-right to bottom-right)
    drawArc(-0.52, 1.57, const Color(0xFF4285F4));
    // Green (bottom-right to bottom-left)
    drawArc(1.05, 1.57, const Color(0xFF34A853));
    // Yellow (bottom-left to top-left)
    drawArc(2.62, 1.57, const Color(0xFFFBBC05));
    // Red (top-left to top-right)
    drawArc(4.19, 1.57, const Color(0xFFEA4335));

    // White horizontal bar for the "G" cutout
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = strokeW * 1.1;
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx + radius * 0.9, center.dy),
      paint,
    );
    // White inner circle to create ring effect
    canvas.drawCircle(
      center,
      radius - strokeW * 1.1,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Google Sign-In Setup Sheet ─────────────────────────────────────────────
// Collects invite code + DOB before triggering Google auth.
// WorkMate4U is 16+ only and in closed beta (invite code required).

String _monthName(int m) => const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ][m - 1];

class _GoogleSetupSheet extends StatefulWidget {
  const _GoogleSetupSheet();

  @override
  State<_GoogleSetupSheet> createState() => _GoogleSetupSheetState();
}

class _GoogleSetupSheetState extends State<_GoogleSetupSheet> {
  final _inviteCtrl = TextEditingController();
  DateTime? _dob;

  @override
  void dispose() {
    _inviteCtrl.dispose();
    super.dispose();
  }

  int _ageInYears(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) age--;
    return age;
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1920),
      // The date picker's lastDate prevents selecting a DOB < 16 years ago.
      lastDate: DateTime(now.year - 16, now.month, now.day),
      helpText: 'Select Date of Birth',
      fieldLabelText: 'Date of Birth',
    );
    if (picked != null) setState(() => _dob = picked);
  }

  void _continue() {
    final code = _inviteCtrl.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your invite code')),
      );
      return;
    }
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select your date of birth')),
      );
      return;
    }
    if (_ageInYears(_dob!) < 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You must be at least 16 years old to join WorkMate4U')),
      );
      return;
    }
    Navigator.of(context).pop({'inviteCode': code, 'dob': _dob});
  }

  @override
  Widget build(BuildContext context) {
    final dob = _dob;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
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
          const Text(
            'One quick step',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.dark),
          ),
          const SizedBox(height: 6),
          const Text(
            'WorkMate4U is in closed beta. Enter your invite code and confirm your age to continue.',
            style: TextStyle(color: AppColors.gray, fontSize: 14),
          ),
          const SizedBox(height: 20),

          // Invite code
          TextFormField(
            controller: _inviteCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Invite Code',
              hintText: 'e.g. WORKMATE2026',
              prefixIcon:
                  Icon(Icons.vpn_key_outlined, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),

          // DOB picker
          GestureDetector(
            onTap: _pickDob,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Date of Birth',
                prefixIcon: const Icon(Icons.cake_outlined),
                suffixIcon:
                    const Icon(Icons.calendar_today_outlined, size: 18),
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: AppColors.primary, width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              ),
              child: Text(
                dob != null
                    ? '${dob.day.toString().padLeft(2, '0')} ${_monthName(dob.month)} ${dob.year}'
                    : 'Select your date of birth',
                style: TextStyle(
                  fontSize: 16,
                  color: dob != null ? AppColors.dark : AppColors.gray,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Must be 16 or older to use WorkMate4U.',
            style: TextStyle(color: AppColors.gray, fontSize: 12),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _continue,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text(
                'Continue with Google',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
