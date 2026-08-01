import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/google_profile_popup.dart';

/// Bridge screen after any new account creation.
/// Shows a loading animation, then the Google profile popup if required,
/// then navigates to home.
class AuthSuccessScreen extends StatefulWidget {
  const AuthSuccessScreen({super.key});

  @override
  State<AuthSuccessScreen> createState() => _AuthSuccessScreenState();
}

class _AuthSuccessScreenState extends State<AuthSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    _startFlow();
  }

  Future<void> _startFlow() async {
    // Brief loading pause so the animation is visible.
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    if (auth.requiresGoogleProfileCompletion) {
      final completed = await GoogleProfilePopup.show(
        context,
        googleName: auth.user?.name,
        photoUrl: auth.user?.avatar,
        email: auth.user?.email,
      );
      if (!mounted) return;
      if (completed == true) await auth.markGoogleProfileCompleted();
    } else {
      // No popup: hold for a comfortable total of ~3 s.
      await Future.delayed(const Duration(milliseconds: 1600));
      if (!mounted) return;
    }

    auth.clearPendingSuccessScreen();
    // ignore: use_build_context_synchronously
    context.go('/home');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstName =
        context.watch<AuthProvider>().user?.name.trim().split(' ').first ?? '';
    return Scaffold(
      backgroundColor: const Color(0xFFF0F5FF),
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/images/logo.png', height: 110),
              const SizedBox(height: 28),
              Text(
                firstName.isNotEmpty ? 'Welcome, $firstName! 🎉' : 'Welcome! 🎉',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Setting up your account…',
                style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
