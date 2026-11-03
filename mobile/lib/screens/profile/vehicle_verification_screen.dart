import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/verification_cooldown_banner.dart';

/// List of skills requiring vehicle verification (Driving License & Vehicle RC)
const List<String> kVehicleSkills = [
  'Delivery',
  'Driving',
  'Moving & Packing',
];

/// Helper check to determine if any given skills require vehicle verification
bool hasVehicleSkill(Iterable<String> skills) {
  final vehicleSet = kVehicleSkills.map((s) => s.toLowerCase()).toSet();
  return skills.any((s) {
    final lower = s.trim().toLowerCase();
    return vehicleSet.contains(lower) || lower == 'moving & packaging';
  });
}

/// Helper filter to extract vehicle skills from a list
List<String> getVehicleSkillsFrom(Iterable<String> skills) {
  final vehicleSet = kVehicleSkills.map((s) => s.toLowerCase()).toSet();
  return skills.where((s) {
    final lower = s.trim().toLowerCase();
    return vehicleSet.contains(lower) || lower == 'moving & packaging';
  }).toList();
}

bool isVehicleSkill(String skill) {
  final lower = skill.trim().toLowerCase();
  return lower == 'driving' ||
      lower == 'delivery' ||
      lower == 'moving & packing' ||
      lower == 'moving & packaging';
}

class VehicleVerificationScreen extends StatefulWidget {
  final List<String>? initialSkills;
  const VehicleVerificationScreen({super.key, this.initialSkills});

  @override
  State<VehicleVerificationScreen> createState() => _VehicleVerificationScreenState();
}

class _VehicleVerificationScreenState extends State<VehicleVerificationScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _primaryPhoneCtrl;
  late final TextEditingController _altPhoneCtrl;
  late final TextEditingController _dlNumberCtrl;
  late final TextEditingController _rcNumberCtrl;
  late final TextEditingController _notesCtrl;

  String _vehicleType = 'Two Wheeler (Bike / Scooter)';
  final List<String> _vehicleTypes = const [
    'Two Wheeler (Bike / Scooter)',
    'Three Wheeler (Auto / Rickshaw)',
    'Four Wheeler (Car / Taxi)',
    'Commercial / Tempo / Pickup Truck',
  ];

  String? _dlImagePath;
  int? _dlImageSize;
  String? _rcImagePath;
  int? _rcImageSize;

  bool _declarationAccepted = false;
  bool _submitting = false;

  static const int _maxFileSizeBytes = 2 * 1024 * 1024; // 2MB

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().user;
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _addressCtrl = TextEditingController();
    _primaryPhoneCtrl = TextEditingController(text: user?.phone ?? '');
    _altPhoneCtrl = TextEditingController();
    _dlNumberCtrl = TextEditingController();
    _rcNumberCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _primaryPhoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _dlNumberCtrl.dispose();
    _rcNumberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Widget _buildFieldLabel(String label, {bool isRequired = true, String? badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
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
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getVehicleTypeIcon(String type) {
    final lower = type.toLowerCase();
    if (lower.contains('two')) return Icons.two_wheeler_outlined;
    if (lower.contains('three')) return Icons.electric_rickshaw_outlined;
    if (lower.contains('four') || lower.contains('car')) return Icons.directions_car_outlined;
    return Icons.local_shipping_outlined;
  }

  Future<void> _pickImage({
    required bool isDrivingLicense,
    required ImageSource source,
  }) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (picked == null) return;

      final path = picked.path.toLowerCase();
      final isPngOrJpeg = path.endsWith('.png') ||
          path.endsWith('.jpg') ||
          path.endsWith('.jpeg');

      if (!isPngOrJpeg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid format. Only PNG and JPEG images are allowed.'),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      final bytes = await picked.length();
      if (bytes > _maxFileSizeBytes) {
        final sizeMb = (bytes / (1024 * 1024)).toStringAsFixed(2);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File size exceeds 2MB limit (selected: $sizeMb MB). Please select an image under 2MB.',
            ),
            backgroundColor: AppColors.danger,
          ),
        );
        return;
      }

      setState(() {
        if (isDrivingLicense) {
          _dlImagePath = picked.path;
          _dlImageSize = bytes;
        } else {
          _rcImagePath = picked.path;
          _rcImageSize = bytes;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _showImagePickerModal({required bool isDrivingLicense}) {
    final title = isDrivingLicense ? 'Driving License' : 'Vehicle RC';
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Upload $title Photo',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Supported formats: PNG, JPEG (Up to 2MB)',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.camera_alt_outlined, color: AppColors.primary),
                ),
                title: const Text('Take Photo using Camera'),
                subtitle: const Text('Capture clear photo of document'),
                onTap: () {
                  Navigator.pop(modalCtx);
                  _pickImage(isDrivingLicense: isDrivingLicense, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.photo_library_outlined, color: AppColors.primary),
                ),
                title: const Text('Choose from Gallery'),
                subtitle: const Text('Select existing PNG or JPEG image'),
                onTap: () {
                  Navigator.pop(modalCtx);
                  _pickImage(isDrivingLicense: isDrivingLicense, source: ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageUploadCard({
    required String label,
    required String? imagePath,
    required int? imageSize,
    required bool isDrivingLicense,
  }) {
    final hasImage = imagePath != null;
    final sizeMbText = (imageSize != null)
        ? '${(imageSize / (1024 * 1024)).toStringAsFixed(2)} MB'
        : '';
    final filename = hasImage ? imagePath.split(RegExp(r'[/\\]')).last : '';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: hasImage ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasImage ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
          style: BorderStyle.solid,
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: hasImage
          ? Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: kIsWeb
                        ? Image.network(imagePath, fit: BoxFit.cover)
                        : Image.file(File(imagePath), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: Color(0xFF16A34A), size: 15),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              filename,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF166534),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$sizeMbText • PNG/JPEG (< 2MB)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF15803D),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Change document image',
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 20),
                  onPressed: () => _showImagePickerModal(isDrivingLicense: isDrivingLicense),
                ),
                IconButton(
                  tooltip: 'Remove',
                  constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                  padding: const EdgeInsets.all(4),
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 20),
                  onPressed: () {
                    setState(() {
                      if (isDrivingLicense) {
                        _dlImagePath = null;
                        _dlImageSize = null;
                      } else {
                        _rcImagePath = null;
                        _rcImageSize = null;
                      }
                    });
                  },
                ),
              ],
            )
          : InkWell(
              onTap: () => _showImagePickerModal(isDrivingLicense: isDrivingLicense),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_upload_outlined,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Upload $label Photo',
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'PNG / JPEG format • Maximum size 2MB',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '0m';
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final auth = context.read<AuthProvider>();
    final user = auth.user;

    // Check 24-hour cooldown if previously rejected
    if (user != null && !user.canReapplyVehicleVerification) {
      final rem = user.vehicleVerificationReapplyRemaining ?? Duration.zero;
      final hours = rem.inHours;
      final minutes = rem.inMinutes % 60;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vehicle verification was recently rejected. You can reapply in ${hours}h ${minutes}m.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_dlImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload your Driving License image (PNG/JPEG, max 2MB).'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (_rcImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please upload your Vehicle RC image (PNG/JPEG, max 2MB).'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (!_declarationAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept the vehicle verification declaration to proceed.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    List<String> targetSkills = widget.initialSkills != null && widget.initialSkills!.isNotEmpty
        ? getVehicleSkillsFrom(widget.initialSkills!)
        : getVehicleSkillsFrom(user?.skills ?? []);

    if (targetSkills.isEmpty) {
      targetSkills = const ['Driving', 'Delivery', 'Moving & Packing'];
    }

    setState(() => _submitting = true);

    final ok = await auth.submitVehicleVerificationRequest(
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      primaryPhone: _primaryPhoneCtrl.text.trim(),
      alternativePhone: _altPhoneCtrl.text.trim().isNotEmpty ? _altPhoneCtrl.text.trim() : null,
      skills: targetSkills,
      dlNumber: _dlNumberCtrl.text.trim(),
      dlImagePath: _dlImagePath!,
      rcNumber: _rcNumberCtrl.text.trim(),
      rcImagePath: _rcImagePath!,
      vehicleType: _vehicleType,
      notes: _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    if (ok) {
      _showSuccessDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error ?? 'Failed to submit vehicle verification. Please try again.'),
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
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFFDBEAFE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car_filled_rounded,
                    color: Color(0xFF1D4ED8), size: 38),
              ),
              const SizedBox(height: 16),
              const Text(
                'Vehical Verification Request Sent! 🚗',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E3A8A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              const Text(
                'Your vehicle verification request containing Driving License and Vehicle RC documents has been successfully submitted to the Workmate4u Admin team.\n\nOur verification team will review your submitted documents within 24 hours to activate your vehicle skills.',
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
                    backgroundColor: const Color(0xFF2563EB),
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

    final vehicleSkillsToDisplay = widget.initialSkills != null && widget.initialSkills!.isNotEmpty
        ? getVehicleSkillsFrom(widget.initialSkills!)
        : getVehicleSkillsFrom(user?.skills ?? []);

    final skillsList = vehicleSkillsToDisplay.isNotEmpty
        ? vehicleSkillsToDisplay
        : kVehicleSkills;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Vehical Verification'),
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
                  color: const Color(0xFF1E40AF),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1E40AF).withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
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
                          child: const Icon(Icons.directions_car_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Vehical Verification',
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
                      'Tasks requiring a vehicle (Driving, Delivery, Moving & Packing) require valid vehicle documentation. Please provide your personal info, Driving License number with image, and Vehicle RC number with image.',
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

              // ── Cooldown & Review Status Banner ──────────────────────────────
              VerificationCooldownBanner(
                verificationTitle: 'Vehical Verification',
                status: user?.vehicleVerificationStatus ?? 'none',
                rejectionReason: user?.vehicleVerificationRejectReason,
                rejectedAt: user?.vehicleVerificationRejectedAt,
              ),

              const SizedBox(height: 16),

              // ── Selected Vehicle Skills Chip Banner ─────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.drive_eta_rounded, color: Color(0xFF1D4ED8), size: 18),
                        SizedBox(width: 6),
                        Text(
                          'Vehicle Skills Verification',
                          style: TextStyle(
                            color: Color(0xFF1E40AF),
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
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle, color: Color(0xFF1D4ED8), size: 14),
                              const SizedBox(width: 4),
                              Text(
                                skill,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E3A8A),
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
                        'Helper & Vehicle Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'All marked fields and document photos (up to 2MB) are mandatory.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 18),

                      // 1. Full Legal Name *
                      _buildFieldLabel('Full Legal Name'),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(
                          hintText: 'Enter your legal name as on Driving License',
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
                          if (v.trim().length < 8) return 'Please provide full address with city and PIN';
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
                          hintText: '10-digit primary mobile number',
                          helperText: 'Main contact number for verification calls',
                          helperStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
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

                      // 4. Alternate Mobile Number (Optional)
                      _buildFieldLabel('Alternate Mobile Number', isRequired: false, badge: 'Optional'),
                      TextFormField(
                        controller: _altPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: InputDecoration(
                          hintText: 'Secondary or family contact number',
                          helperText: 'Optional • Backup contact if primary number is unreachable',
                          helperStyle: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          prefixIcon: const Icon(Icons.phone_android_outlined, color: AppColors.primary),
                          prefixText: '+91 ',
                          counterText: '',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        validator: (v) {
                          final clean = (v ?? '').replaceAll(RegExp(r'\D'), '');
                          if (clean.isEmpty) {
                            return null; // Optional: completely valid when omitted
                          }
                          if (clean.length != 10) {
                            return 'Enter a valid 10-digit mobile number';
                          }
                          final primaryClean = _primaryPhoneCtrl.text.replaceAll(RegExp(r'\D'), '');
                          if (clean == primaryClean) {
                            return 'Alternate number cannot be same as primary mobile number';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      // 5. Vehicle Type Selection *
                      _buildFieldLabel('Vehical Type'),
                      DropdownButtonFormField<String>(
                        value: _vehicleType,
                        isExpanded: true,
                        isDense: true,
                        icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                        decoration: InputDecoration(
                          prefixIcon: Icon(_getVehicleTypeIcon(_vehicleType), color: AppColors.primary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                        selectedItemBuilder: (context) {
                          return _vehicleTypes.map((type) {
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                type,
                                style: const TextStyle(fontSize: 13.5, color: Color(0xFF1E293B)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList();
                        },
                        items: _vehicleTypes.map((type) {
                          return DropdownMenuItem(
                            value: type,
                            child: Text(
                              type,
                              style: const TextStyle(fontSize: 13.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _vehicleType = val);
                        },
                      ),

                      const SizedBox(height: 20),

                      // ── Driving License Section ─────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.badge_outlined, color: AppColors.primary, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Driving License Details',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Driving License Number *
                            _buildFieldLabel('Driving License Number'),
                            TextFormField(
                              controller: _dlNumberCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'e.g. MH12AB1234',
                                prefixIcon: const Icon(Icons.credit_card_rounded, color: AppColors.primary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Driving License number is required';
                                if (v.trim().length < 5) return 'Enter a valid Driving License number';
                                return null;
                              },
                            ),

                            const SizedBox(height: 12),

                            // Driving License Image Upload *
                            _buildFieldLabel('Upload Driving License Photo (PNG / JPEG, up to 2MB)'),
                            _buildImageUploadCard(
                              label: 'Driving License',
                              imagePath: _dlImagePath,
                              imageSize: _dlImageSize,
                              isDrivingLicense: true,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ── Vehicle RC Section ──────────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.directions_car_filled_outlined, color: AppColors.primary, size: 20),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Vehical RC (Registration Certificate) Details',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Vehicle RC Number *
                            _buildFieldLabel('Vehical RC Number'),
                            TextFormField(
                              controller: _rcNumberCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: InputDecoration(
                                hintText: 'e.g. MH1220180012345',
                                prefixIcon: const Icon(Icons.pin_outlined, color: AppColors.primary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              ),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Vehicle RC number is required';
                                if (v.trim().length < 5) return 'Enter a valid Vehicle RC number';
                                return null;
                              },
                            ),

                            const SizedBox(height: 12),

                            // Vehicle RC Image Upload *
                            _buildFieldLabel('Upload Vehical RC Photo (PNG / JPEG, up to 2MB)'),
                            _buildImageUploadCard(
                              label: 'Vehical RC',
                              imagePath: _rcImagePath,
                              imageSize: _rcImageSize,
                              isDrivingLicense: false,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Experience / Additional Notes (Optional)
                      _buildFieldLabel('Experience / Additional Remarks', isRequired: false),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: 'e.g., 4 years driving experience, own tempo for moving, etc.',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),

                      const SizedBox(height: 18),

                      // Declaration Checkbox *
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
                              onChanged: (val) {
                                setState(() => _declarationAccepted = val ?? false);
                              },
                            ),
                            const Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'I declare that the Driving License and Vehicle RC details and images uploaded belong to me, are genuine, unexpired, and valid. I agree that false document submissions will result in immediate termination of account.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF334155),
                                    height: 1.45,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Submit Button
                      Builder(
                        builder: (context) {
                          final isVerified = user?.vehicleVerificationStatus == 'verified';
                          final isPending = user?.vehicleVerificationStatus == 'pending';
                          final isRejected = user?.vehicleVerificationStatus == 'rejected';
                          final canReapply = user?.canReapplyVehicleVerification ?? true;
                          final cooldownActive = isRejected && !canReapply;

                          final bool isDisabled = _submitting || isVerified || isPending || cooldownActive;

                          String buttonText = 'Submit Vehical Verification';
                          IconData buttonIcon = Icons.send_rounded;
                          Color buttonBg = const Color(0xFF1E40AF);

                          if (isVerified) {
                            buttonText = 'Vehical Verified';
                            buttonIcon = Icons.directions_car_filled_rounded;
                            buttonBg = const Color(0xFF059669);
                          } else if (isPending) {
                            buttonText = 'Under Review (Completes in 24 hrs)';
                            buttonIcon = Icons.hourglass_top_rounded;
                            buttonBg = const Color(0xFFD97706);
                          } else if (cooldownActive) {
                            buttonText = 'Reapply in ${_formatDuration(user!.vehicleVerificationReapplyRemaining)}';
                            buttonIcon = Icons.timer_outlined;
                            buttonBg = const Color(0xFFDC2626);
                          } else if (isRejected) {
                            buttonText = 'Reapply Vehical Verification';
                            buttonIcon = Icons.refresh_rounded;
                            buttonBg = const Color(0xFF1E40AF);
                          }

                          return SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: isDisabled ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDisabled ? buttonBg.withValues(alpha: 0.6) : buttonBg,
                                foregroundColor: Colors.white,
                                disabledForegroundColor: Colors.white,
                                disabledBackgroundColor: buttonBg.withValues(alpha: 0.6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: isDisabled ? 0 : 2,
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(buttonIcon, size: 18, color: Colors.white),
                                          const SizedBox(width: 8),
                                          Text(
                                            buttonText,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          );
                        },
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

