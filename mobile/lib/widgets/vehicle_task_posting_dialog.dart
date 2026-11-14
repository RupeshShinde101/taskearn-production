import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A high-fidelity, realistic popup dialog for Workmate4u task posting.
///
/// Implements the exact 2-stage interaction matching the user's design:
/// - Stage 1 (Posting In-Progress):
///   - Clean white card with rounded corners (24px).
///   - Winding road illustration with blue start location pin (📍) on left,
///     checkered finish flag (🏁) on right, and the user's selected vehicle.
///   - Contained strictly within the card boundaries (never overflows).
///   - Graceful 3.5s animation duration with smooth road bobbing.
///   - Headline: "Posting your task..."
///   - Clean circular loading spinner.
///
/// - Stage 2 (Task is Posted!):
///   - 3D vehicle parked beside delivery parcel box (or cargo boxes + helper avatar)
///     with a glowing green verified checkmark badge.
///   - Headline: "Task is Posted!"
///   - Mint Status Pill: "🟢 Waiting for Helper..."
///   - Detail Pill: "[Selected Vehicle] • Instant Radar Active"
///   - Full-width royal blue button: "Track in My Tasks"
class VehicleTaskPostingDialog extends StatefulWidget {
  final String category;
  final String vehicleType; // 'bike', 'rikshaw', 'auto', 'mini_truck', 'pickup', 'car'
  final double budget;
  final double? distanceKm;
  final String? customTitle;
  final Future<bool> Function() onPostTask;
  final VoidCallback? onTrackInMyTasks;
  final VoidCallback? onBackToHome;

  const VehicleTaskPostingDialog({
    super.key,
    required this.category,
    this.vehicleType = 'bike',
    required this.budget,
    this.distanceKm,
    this.customTitle,
    required this.onPostTask,
    this.onTrackInMyTasks,
    this.onBackToHome,
  });

  /// Static helper to show this dialog cleanly.
  static Future<bool?> show({
    required BuildContext context,
    required String category,
    String vehicleType = 'bike',
    required double budget,
    double? distanceKm,
    String? customTitle,
    required Future<bool> Function() onPostTask,
    VoidCallback? onTrackInMyTasks,
    VoidCallback? onBackToHome,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (ctx) => VehicleTaskPostingDialog(
        category: category,
        vehicleType: vehicleType,
        budget: budget,
        distanceKm: distanceKm,
        customTitle: customTitle,
        onPostTask: onPostTask,
        onTrackInMyTasks: onTrackInMyTasks,
        onBackToHome: onBackToHome,
      ),
    );
  }

  @override
  State<VehicleTaskPostingDialog> createState() => _VehicleTaskPostingDialogState();
}

class _VehicleTaskPostingDialogState extends State<VehicleTaskPostingDialog>
    with TickerProviderStateMixin {
  late AnimationController _driveController;
  late Animation<double> _driveAnimation;
  late AnimationController _morphController;

  bool _isPosted = false;
  bool _postSuccess = false;

  bool get _isMoving =>
      widget.category.toLowerCase() == 'moving' ||
      widget.vehicleType.toLowerCase().contains('truck') ||
      widget.vehicleType.toLowerCase().contains('pickup');

  bool get _isRikshaw =>
      widget.vehicleType.toLowerCase() == 'rikshaw' ||
      widget.vehicleType.toLowerCase() == 'auto';

  bool get _isCar =>
      widget.category.toLowerCase() == 'transport' ||
      widget.vehicleType.toLowerCase() == 'car' ||
      widget.vehicleType.toLowerCase() == 'cab';

  String get _postingAsset {
    if (_isMoving) return 'assets/images/style_b_truck_posting.png';
    if (_isRikshaw) return 'assets/images/style_b_rikshaw_posting.png';
    return 'assets/images/style_b_scooter_posting.png';
  }

  String get _postedAsset {
    if (_isMoving) return 'assets/images/style_b_moving_truck_posted.png';
    if (_isRikshaw) return 'assets/images/style_b_rikshaw_posted.png';
    return 'assets/images/style_b_scooter_posted.png';
  }

  String get _vehiclePillLabel {
    if (_isMoving) return 'Mini Truck Moving • Instant Radar Active';
    if (_isRikshaw) return 'Auto Delivery • Instant Radar Active';
    if (_isCar) return 'Cab Transport • Instant Radar Active';
    return 'Bike Delivery • Instant Radar Active';
  }

  @override
  void initState() {
    super.initState();

    // Paced 3.4 seconds duration so user enjoys the cartoon road animation
    _driveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3400),
    );

    _driveAnimation = CurvedAnimation(
      parent: _driveController,
      curve: Curves.easeInOutCubic,
    );

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _startFlow();
  }

  void _startFlow() async {
    _driveController.forward();

    // Call actual task creation API in parallel
    try {
      final success = await widget.onPostTask();
      _postSuccess = success;
    } catch (_) {
      _postSuccess = false;
    }

    if (!mounted) return;

    // Ensure the animation has played sufficiently (at least 2.5s) so the animation is clearly visible
    if (_driveController.value < 0.85) {
      await Future.delayed(
        Duration(milliseconds: ((0.90 - _driveController.value) * 3400).toInt().clamp(200, 2500)),
      );
    }

    if (!mounted) return;

    if (_postSuccess) {
      setState(() {
        _isPosted = true;
      });
      _morphController.forward();
    } else {
      Navigator.of(context).pop(false);
    }
  }

  @override
  void dispose() {
    _driveController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isPosted,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 315,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(anim),
                  child: child,
                ),
              ),
              child: _isPosted ? _buildPostedView() : _buildPostingView(),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STAGE 1: WHILE POSTING (Road track + driving vehicle + spinner)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostingView() {
    return Column(
      key: const ValueKey('stage1_posting'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Road track illustration strictly clipped within container boundaries
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.white,
            height: 180,
            width: double.infinity,
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _driveAnimation,
              builder: (context, _) {
                // Subtle road bobbing animation strictly within frame
                final floatOffset = math.sin(_driveAnimation.value * 6 * math.pi) * 2.2;
                return Transform.translate(
                  offset: Offset(0, floatOffset),
                  child: Image.asset(
                    _postingAsset,
                    height: 175,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => _buildFallbackPostingHero(),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Headline: "Posting your task..."
        const Text(
          'Posting your task...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 14),

        // Modern circular loading spinner (as shown in reference image)
        const SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.6,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STAGE 2: TASK POSTED (Vehicle parked + parcel box + "Track in My Tasks")
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostedView() {
    return Column(
      key: const ValueKey('stage2_posted'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Cartoon Vehicle + Delivery Box / Cargo Illustration
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.white,
            height: 190,
            width: double.infinity,
            alignment: Alignment.center,
            child: Image.asset(
              _postedAsset,
              height: 185,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => _buildFallbackPostedHero(),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Bold Headline: "Task is Posted!"
        const Text(
          'Task is Posted!',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 8),

        // Mint Status Pill: "🟢 Waiting for Helper..."
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE6FFFA),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Waiting for Helper...',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0D9488),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Detail Pill: e.g. "Bike Delivery • Instant Radar Active"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            _vehiclePillLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF475569),
            ),
          ),
        ),
        const SizedBox(height: 18),

        // Primary Button: "Track in My Tasks"
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(true);
              if (widget.onTrackInMyTasks != null) {
                widget.onTrackInMyTasks!();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Track in My Tasks',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Fallback Graphic Builders ──────────────────────────────────────────────
  Widget _buildFallbackPostingHero() {
    return Icon(
      _isMoving ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
      size: 72,
      color: const Color(0xFF2563EB),
    );
  }

  Widget _buildFallbackPostedHero() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          _isMoving ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
          size: 96,
          color: const Color(0xFF2563EB),
        ),
        Positioned(
          top: 15,
          right: 35,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 20),
          ),
        ),
      ],
    );
  }
}
