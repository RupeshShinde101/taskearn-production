import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String _docType = 'aadhaar'; // 'aadhaar' | 'pan'
  final _docNumberCtrl = TextEditingController();
  String? _frontImagePath;
  String? _backImagePath; // only for aadhaar
  bool _acknowledged = false;
  bool _loading = false;

  bool get _isAadhaar => _docType == 'aadhaar';
  String get _docLabel => _isAadhaar ? 'Aadhaar Card' : 'PAN Card';

  @override
  void dispose() {
    _docNumberCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isFront}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.primary),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: source,
      imageQuality: 60,   // keep document text legible but under 300 KB per image
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (file != null && mounted) {
      setState(() {
        if (isFront) {
          _frontImagePath = file.path;
        } else {
          _backImagePath = file.path;
        }
      });
    }
  }

  void _switchDocType(String type) {
    if (_docType == type) return;
    setState(() {
      _docType = type;
      _docNumberCtrl.clear();
      _frontImagePath = null;
      _backImagePath = null;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_frontImagePath == null) {
      _showSnack('Please upload the front side of your ' + _docLabel + '.', isError: true);
      return;
    }
    if (_isAadhaar && _backImagePath == null) {
      _showSnack('Aadhaar Card requires both Front and Back side photos.', isError: true);
      return;
    }
    if (!_acknowledged) {
      _showSnack('Please accept the legal declaration to continue.', isError: true);
      return;
    }
    setState(() => _loading = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.submitKyc(
      docType: _docType,
      docNumber: _docNumberCtrl.text.trim(),
      frontImagePath: _frontImagePath!,
      backImagePath: _isAadhaar ? _backImagePath : null,
    );
    if (!mounted) return;
    setState(() => _loading = false);
    if (ok) {
      _showSnack(auth.kycSubmitMessage ?? 'KYC submitted successfully!', isError: false);
      context.pop();
    } else {
      _showSnack(auth.error ?? 'KYC submission failed. Please try again.', isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.danger : AppColors.success,
      duration: const Duration(seconds: 5),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final isVerified = user?.isKycVerified ?? false;
    final kycStatus = user?.kycStatus;
    return Scaffold(
      backgroundColor: AppColors.light,
      appBar: AppBar(
        title: const Text('KYC Verification'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusBanner(kycStatus, isVerified),
              const SizedBox(height: 20),
              if (isVerified || kycStatus == 'pending') ...[
                _buildReadOnlyInfo(kycStatus, isVerified),
              ] else ...[
                _buildInfoCard(),
                const SizedBox(height: 24),
                _buildStepHeader('1', 'Choose Document Type'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _DocTypeCard(
                      label: 'Aadhaar Card',
                      icon: Icons.badge_outlined,
                      requirement: 'Front + Back required',
                      selected: _isAadhaar,
                      onTap: () => _switchDocType('aadhaar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DocTypeCard(
                      label: 'PAN Card',
                      icon: Icons.credit_card_outlined,
                      requirement: 'Front only required',
                      selected: _docType == 'pan',
                      onTap: () => _switchDocType('pan'),
                    ),
                  ),
                ]),
                const SizedBox(height: 24),
                _buildStepHeader('2', 'Enter Document Number'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _docNumberCtrl,
                  decoration: InputDecoration(
                    labelText: _isAadhaar
                        ? 'Aadhaar Number (12 digits)'
                        : 'PAN Number (e.g. ABCDE1234F)',
                    hintText: _isAadhaar ? '000000000000' : 'ABCDE1234F',
                    prefixIcon: const Icon(Icons.numbers_outlined),
                    helperText: _isAadhaar
                        ? 'Enter all 12 digits exactly as shown on your Aadhaar card'
                        : 'Enter the 10-character PAN number exactly as on the card',
                    helperMaxLines: 2,
                  ),
                  keyboardType: _isAadhaar
                      ? TextInputType.number
                      : TextInputType.text,
                  textCapitalization: _isAadhaar
                      ? TextCapitalization.none
                      : TextCapitalization.characters,
                  inputFormatters: [
                    if (_isAadhaar) FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(_isAadhaar ? 12 : 10),
                    if (!_isAadhaar) _UpperCaseFormatter(),
                  ],
                  validator: (v) {
                    final val = (v ?? '').trim();
                    if (val.isEmpty) return 'Document number is required';
                    if (_isAadhaar) {
                      if (!RegExp(r'^\d{12}$').hasMatch(val)) {
                        return 'Aadhaar must be exactly 12 digits';
                      }
                    } else {
                      if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
                          .hasMatch(val.toUpperCase())) {
                        return 'PAN format must be like ABCDE1234F';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                _buildStepHeader('3', 'Upload Document Photos'),
                const SizedBox(height: 12),
                _buildPhotoHint(),
                const SizedBox(height: 12),
                _ImageCard(
                  label: 'Front Side',
                  sublabel: _isAadhaar
                      ? 'Side showing name, photo & Aadhaar number'
                      : 'Side showing name, photo & PAN number',
                  imagePath: _frontImagePath,
                  onPick: () => _pickImage(isFront: true),
                  onRemove: () => setState(() => _frontImagePath = null),
                ),
                if (_isAadhaar) ...[
                  const SizedBox(height: 12),
                  _ImageCard(
                    label: 'Back Side',
                    sublabel: 'Side showing address & QR code',
                    imagePath: _backImagePath,
                    onPick: () => _pickImage(isFront: false),
                    onRemove: () => setState(() => _backImagePath = null),
                  ),
                ],
                const SizedBox(height: 24),
                _buildStepHeader('4', 'Acknowledge & Submit'),
                const SizedBox(height: 12),
                _buildAcknowledgmentTile(),
                const SizedBox(height: 20),
                GradientButton(
                  label: 'Submit for Verification',
                  loading: _loading,
                  onPressed: _submit,
                  icon: Icons.verified_outlined,
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Your documents are encrypted and stored securely.\n'
                    'Verification usually takes 24-48 hours.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.gray, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepHeader(String step, String title) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: Text(step,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 10),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: AppColors.dark)),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.primary, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'KYC is mandatory to post tasks, accept tasks & withdraw earnings. '
              'Verify using Aadhaar Card or PAN Card.',
              style: TextStyle(
                  color: AppColors.dark, fontSize: 13, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.camera_enhance_outlined,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Text(
              _isAadhaar
                  ? 'Aadhaar - Front AND Back photo required'
                  : 'PAN Card - Front side only required',
              style: const TextStyle(
                  color: AppColors.dark,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'x Entire document must be fully visible\n'
            'x Photo must be clear, well-lit and not blurry\n'
            'x Number in photo must match the number you entered above\n'
            'x Avoid glare, shadows or cropped edges',
            style: TextStyle(
                color: AppColors.gray, fontSize: 12, height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _buildAcknowledgmentTile() {
    return GestureDetector(
      onTap: () => setState(() => _acknowledged = !_acknowledged),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        decoration: BoxDecoration(
          color: _acknowledged
              ? AppColors.success.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _acknowledged
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.border,
            width: _acknowledged ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acknowledged,
              activeColor: AppColors.success,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4)),
              onChanged: (v) => setState(() => _acknowledged = v ?? false),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'I declare that the documents submitted are genuine, belong to '
                  'me, and the information provided is accurate. I understand '
                  'that submitting forged or stolen documents is an offence '
                  'under the IT Act and IPC section 420.',
                  style: TextStyle(
                      color: AppColors.dark, fontSize: 12, height: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String? kycStatus, bool isVerified) {
    if (isVerified) {
      return _StatusBanner(
        icon: Icons.verified_rounded,
        label: 'KYC Verified',
        subtitle: 'Your identity has been successfully verified.',
        color: AppColors.success,
      );
    }
    switch (kycStatus) {
      case 'pending':
        return _StatusBanner(
          icon: Icons.hourglass_top_rounded,
          label: 'Verification Pending',
          subtitle: 'Your documents are under review (24-48 hours).',
          color: AppColors.warning,
        );
      case 'rejected':
        return _StatusBanner(
          icon: Icons.cancel_outlined,
          label: 'Verification Rejected',
          subtitle:
              'Documents were not accepted. Please re-submit with clear, valid documents.',
          color: AppColors.danger,
        );
      default:
        return _StatusBanner(
          icon: Icons.badge_outlined,
          label: 'KYC Not Verified',
          subtitle:
              'Complete KYC to post tasks, accept tasks & withdraw earnings.',
          color: AppColors.gray,
        );
    }
  }

  Widget _buildReadOnlyInfo(String? status, bool isVerified) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        isVerified
            ? 'Your KYC has been verified. No further action needed.'
            : 'Your KYC is under review. Our team will verify your documents '
                'within 24-48 hours.',
        style: TextStyle(
            color: isVerified ? AppColors.success : AppColors.dark,
            fontSize: 14,
            height: 1.5),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;

  const _StatusBanner({
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
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 12,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTypeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String requirement;
  final bool selected;
  final VoidCallback onTap;

  const _DocTypeCard({
    required this.label,
    required this.icon,
    required this.requirement,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: selected ? AppColors.primary : AppColors.gray,
                size: 30),
            const SizedBox(height: 8),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected ? AppColors.primary : AppColors.dark,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(requirement,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.gray, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  final String label;
  final String sublabel;
  final String? imagePath;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  const _ImageCard({
    required this.label,
    required this.sublabel,
    required this.imagePath,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasPic = imagePath != null;
    return GestureDetector(
      onTap: hasPic ? null : onPick,
      child: Container(
        decoration: BoxDecoration(
          color: hasPic
              ? AppColors.success.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPic
                ? AppColors.success.withValues(alpha: 0.5)
                : AppColors.border,
            width: hasPic ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.hardEdge,
        child: hasPic
            ? _PickedView(
                imagePath: imagePath!,
                label: label,
                onRepick: onPick,
                onRemove: onRemove,
              )
            : _EmptyView(label: label, sublabel: sublabel),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String label;
  final String sublabel;
  const _EmptyView({required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.add_photo_alternate_outlined,
                color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppColors.dark,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(sublabel,
                    style: const TextStyle(
                        color: AppColors.gray,
                        fontSize: 12,
                        height: 1.4)),
                const SizedBox(height: 6),
                const Text('Tap to upload',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.grayLight),
        ],
      ),
    );
  }
}

class _PickedView extends StatelessWidget {
  final String imagePath;
  final String label;
  final VoidCallback onRepick;
  final VoidCallback onRemove;

  const _PickedView({
    required this.imagePath,
    required this.label,
    required this.onRepick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Image.file(
          File(imagePath),
          height: 170,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.black.withValues(alpha: 0.55),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            children: [
              _Btn(
                icon: Icons.refresh_rounded,
                label: 'Retake',
                color: AppColors.primary,
                onTap: onRepick,
              ),
              const SizedBox(width: 6),
              _Btn(
                icon: Icons.close,
                label: 'Remove',
                color: AppColors.danger,
                onTap: onRemove,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _Btn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
