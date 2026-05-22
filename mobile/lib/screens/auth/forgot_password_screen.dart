import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

/// Two-step forgot-password flow:
///   Step 1 — enter email, send OTP
///   Step 2 — enter OTP + new password, reset
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 1; // 1 = email entry, 2 = OTP + new password
  String _email = '';

  // Step 1 controllers
  final _emailCtrl = TextEditingController();
  final _emailFormKey = GlobalKey<FormState>();

  // Step 2 controllers
  String _otp = '';
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  final _resetFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_emailFormKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.forgotPasswordSendOtp(_emailCtrl.text);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _email = _emailCtrl.text.trim();
        _step = 2;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Failed to send OTP. Try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _resendOtp() async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.forgotPasswordSendOtp(_email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'OTP resent to $_email' : (auth.error ?? 'Failed to resend')),
        backgroundColor: ok ? AppColors.success : AppColors.danger,
      ),
    );
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    if (_otp.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP')),
      );
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = await auth.resetPasswordWithOtp(
      email: _email,
      otp: _otp,
      newPassword: _newPassCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset successfully! Please log in.'),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Reset failed. Check OTP and try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Forgot Password'),
        leading: BackButton(onPressed: () {
          if (_step == 2) {
            setState(() => _step = 1);
          } else {
            context.pop();
          }
        }),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _step == 1 ? _buildStep1(auth) : _buildStep2(auth),
        ),
      ),
    );
  }

  Widget _buildStep1(AuthProvider auth) {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Center(
            child: Icon(Icons.lock_reset_outlined, size: 64, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Center(
            child: Text(
              'Reset your password',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.dark),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Enter your registered email and we will\nsend a 6-digit OTP to reset your password.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.gray, height: 1.5),
            ),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _sendOtp(),
            decoration: const InputDecoration(
              labelText: 'Registered Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Enter your email';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: 'Send OTP',
            loading: auth.isLoading,
            onPressed: _sendOtp,
            icon: Icons.send_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(AuthProvider auth) {
    final pinTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.dark),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.white,
      ),
    );

    return Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Center(
            child: Icon(Icons.mark_email_read_outlined, size: 64, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Enter OTP & New Password',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.dark),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'OTP sent to $_email',
              style: const TextStyle(color: AppColors.gray),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
          const Text('6-Digit OTP',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dark)),
          const SizedBox(height: 10),
          Center(
            child: Pinput(
              length: 6,
              defaultPinTheme: pinTheme,
              focusedPinTheme: pinTheme.copyWith(
                decoration: pinTheme.decoration!.copyWith(
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
              ),
              onChanged: (v) => _otp = v,
              onCompleted: (v) => _otp = v,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: auth.isLoading ? null : _resendOtp,
              child: const Text('Resend OTP'),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _newPassCtrl,
            obscureText: _obscureNew,
            decoration: InputDecoration(
              labelText: 'New Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureNew
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
            ),
            validator: (v) {
              if (v == null || v.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPassCtrl,
            obscureText: _obscureConfirm,
            decoration: InputDecoration(
              labelText: 'Confirm New Password',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscureConfirm
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            validator: (v) {
              if (v != _newPassCtrl.text) return 'Passwords do not match';
              return null;
            },
          ),
          const SizedBox(height: 28),
          GradientButton(
            label: 'Reset Password',
            loading: auth.isLoading,
            onPressed: _resetPassword,
            icon: Icons.check_circle_outline,
          ),
        ],
      ),
    );
  }
}
