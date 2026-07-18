import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/gradient_button.dart';

class KycScreen extends StatefulWidget {
  const KycScreen({super.key});

  @override
  State<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends State<KycScreen> {
  final _formKey = GlobalKey<FormState>();
  String _docType = 'aadhaar';
  final _docNumberCtrl = TextEditingController();
  String? _frontImagePath;
  String? _selfieImagePath;
  bool _loading = false;

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isSelfie) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: isSelfie ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 80,
    );
    if (file != null && mounted) {
      setState(() {
        if (isSelfie) {
          _selfieImagePath = file.path;
        } else {
          _frontImagePath = file.path;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();

    // Require email to be verified before KYC submission
    if (auth.user?.isEmailVerified == false) {
      await _showEmailVerificationDialog(auth);
      return;
    }

    if (_frontImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload the front of your document.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }
    setState(() => _loading = true);
    final ok = await auth.submitKyc(
      docType: _docType,
      docNumber: _docNumberCtrl.text.trim(),
      frontImagePath: _frontImagePath!,
      backImagePath: _selfieImagePath,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KYC submitted! Verification usually takes 24-48 hours.'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 4),
        ),
      );
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'KYC submission failed. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showEmailVerificationDialog(AuthProvider auth) async {
    final otpCtrl = TextEditingController();

    // Send OTP first
    final sent = await auth.sendEmailVerificationOtp();
    if (!mounted) return;
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.error ?? 'Could not send verification email'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Verification OTP sent to your email'),
      backgroundColor: AppColors.primary,
    ));

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Verify Your Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the 6-digit OTP sent to ${auth.user?.email ?? "your email"} to continue KYC.',
              style: const TextStyle(color: AppColors.gray, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: otpCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: 'Enter OTP',
                prefixIcon: Icon(Icons.mark_email_read_outlined),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (otpCtrl.text.trim().length != 6) return;
              final ok = await auth.verifyEmailOtp(otpCtrl.text.trim());
              if (!dialogCtx.mounted) return;
              Navigator.pop(dialogCtx, ok);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Verify'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (verified == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Email verified! You can now submit KYC.'),
        backgroundColor: AppColors.success,
      ));
      // Re-trigger submission now that email is verified
      await _submit();
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.error!),
        backgroundColor: AppColors.danger,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;

    return Scaffold(
      appBar: AppBar(title: const Text('KYC Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status banner
              _buildStatusBanner(user?.kycStatus, user?.isKycVerified ?? false),
              const SizedBox(height: 12),

              // Email verification warning
              if (user?.isEmailVerified == false)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Your email is not verified. Email verification is required before KYC submission.',
                          style: TextStyle(color: AppColors.dark, fontSize: 12, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),

              // Info card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'KYC verification builds trust with task posters and may unlock higher-value tasks.',
                        style:
                            TextStyle(color: AppColors.dark, fontSize: 13, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              const Text('Document Type',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _DocTypeChip(
                      label: 'Aadhaar',
                      selected: _docType == 'aadhaar',
                      onTap: () => setState(() => _docType = 'aadhaar')),
                  const SizedBox(width: 8),
                  _DocTypeChip(
                      label: 'PAN Card',
                      selected: _docType == 'pan',
                      onTap: () => setState(() => _docType = 'pan')),
                  const SizedBox(width: 8),
                  _DocTypeChip(
                      label: 'Voter ID',
                      selected: _docType == 'voter_id',
                      onTap: () => setState(() => _docType = 'voter_id')),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _docNumberCtrl,
                decoration: InputDecoration(
                  labelText: _docType == 'aadhaar'
                      ? 'Aadhaar Number (12 digits)'
                      : _docType == 'pan'
                          ? 'PAN Number'
                          : 'Voter ID Number',
                  prefixIcon: const Icon(Icons.credit_card_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (_docType == 'aadhaar' && v.trim().length != 12) {
                    return 'Aadhaar must be 12 digits';
                  }
                  if (_docType == 'pan' && v.trim().length != 10) {
                    return 'PAN must be 10 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              const Text('Document Photo',
                  style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.dark)),
              const SizedBox(height: 8),
              _ImagePickerCard(
                label: 'Front of Document',
                imagePath: _frontImagePath,
                icon: Icons.document_scanner_outlined,
                onPick: () => _pickImage(false),
              ),
              const SizedBox(height: 12),
              _ImagePickerCard(
                label: 'Selfie with Document',
                imagePath: _selfieImagePath,
                icon: Icons.camera_front_outlined,
                onPick: () => _pickImage(true),
              ),
              const SizedBox(height: 28),

              GradientButton(
                label: 'Submit for Verification',
                loading: _loading,
                onPressed: _submit,
                icon: Icons.verified_outlined,
              ),

              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Your documents are encrypted and stored securely.\nVerification takes 24-48 hours.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.gray, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String? kycStatus, bool isVerified) {
    if (isVerified) {
      return const _Banner(
        icon: Icons.verified,
        label: 'KYC Verified',
        subtitle: 'Your identity has been verified.',
        color: AppColors.success,
      );
    }
    if (kycStatus == 'pending') {
      return const _Banner(
        icon: Icons.hourglass_top_rounded,
        label: 'Verification Pending',
        subtitle: 'Your documents are under review.',
        color: AppColors.warning,
      );
    }
    if (kycStatus == 'rejected') {
      return const _Banner(
        icon: Icons.cancel_outlined,
        label: 'Verification Rejected',
        subtitle: 'Please re-submit with valid documents.',
        color: AppColors.danger,
      );
    }
    return const _Banner(
      icon: Icons.badge_outlined,
      label: 'Not Verified',
      subtitle: 'Complete KYC to build trust and unlock tasks.',
      color: AppColors.gray,
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  const _Banner({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
        ],
      ),
    );
  }
}

class _DocTypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DocTypeChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.light,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : AppColors.gray,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
      ),
    );
  }
}

class _ImagePickerCard extends StatelessWidget {
  final String label;
  final String? imagePath;
  final IconData icon;
  final VoidCallback onPick;
  const _ImagePickerCard({
    required this.label,
    required this.imagePath,
    required this.icon,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: imagePath != null
              ? AppColors.success.withValues(alpha: 0.06)
              : AppColors.light,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: imagePath != null
                ? AppColors.success.withValues(alpha: 0.4)
                : AppColors.border,
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Icon(
              imagePath != null ? Icons.check_circle : icon,
              color: imagePath != null ? AppColors.success : AppColors.gray,
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                imagePath != null ? '$label ✓' : 'Tap to upload $label',
                style: TextStyle(
                    color: imagePath != null ? AppColors.success : AppColors.gray,
                    fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.grayLight),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
