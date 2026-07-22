import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class OtpScreen extends StatefulWidget {
  final Map<String, dynamic>? extra;
  const OtpScreen({super.key, this.extra});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  String _otp = '';
  bool _loading = false;
  String? _error;

  String get _email => widget.extra?['email'] ?? '';
  String get _mode => widget.extra?['mode'] ?? 'verify'; // verify | reset

  Future<void> _verify() async {
    if (_otp.length != 6) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_mode == 'reset') {
        context.go('/login', extra: {'reset_otp': _otp, 'email': _email});
        return;
      }
      final auth = context.read<AuthProvider>();
      final ok = await auth.verifyEmailOtp(_otp);
      if (!mounted) return;
      if (ok) {
        context.go('/home');
      } else {
        setState(() => _error = auth.error ?? 'Verification failed');
      }
      return;
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ApiService.post('/auth/send-verification-otp', body: {'email': _email});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 52,
      height: 56,
      textStyle:
          const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.dark),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(12),
        color: AppColors.white,
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Verify OTP')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            const Icon(Icons.mark_email_read_outlined,
                size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text('Enter the 6-digit code',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.dark)),
            const SizedBox(height: 8),
            Text(
              'We sent it to $_email',
              style: const TextStyle(color: AppColors.gray),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Pinput(
              length: 6,
              defaultPinTheme: pinTheme,
              focusedPinTheme: pinTheme.copyWith(
                decoration: pinTheme.decoration!.copyWith(
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
              ),
              onChanged: (v) => setState(() => _otp = v),
              onCompleted: (_) => _verify(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
            const SizedBox(height: 28),
            GradientButton(
              label: 'Verify',
              loading: _loading,
              onPressed: _otp.length == 6 ? _verify : null,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _resend,
              child: const Text("Didn't receive? Resend OTP"),
            ),
          ],
        ),
      ),
    );
  }
}
