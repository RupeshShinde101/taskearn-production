import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A high-fidelity, realistic popup dialog for Workmate4u task posting.
///
/// Implements a 2-stage interaction matching the user's design:
/// - Stage 1 (Posting In-Progress): Shows an arched road track with the user's
///   selected vehicle running from start point to end point with cartoon dust puffs,
///   a real-time progress bar (0% -> 100%), and status message.
/// - Stage 2 (Task Posted): Smoothly morphs into the success state displaying the
///   selected vehicle with delivery box (or cargo boxes + helper avatar), green
///   checkmark badge, "Task Posted!" / "Moving Task Posted!", "Waiting for helper...",
///   the task info pill, and the primary "Track in My Tasks" button.
class VehicleTaskPostingDialog extends StatefulWidget {
  final String category;
  final String vehicleType; // 'bike', 'rikshaw', 'mini_truck', 'pickup', 'car'
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
      barrierColor: Colors.black.withValues(alpha: 0.55),
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
      widget.vehicleType.toLowerCase().contains('truck');

  bool get _isRikshaw =>
      widget.vehicleType.toLowerCase() == 'rikshaw' ||
      widget.vehicleType.toLowerCase() == 'auto';

  @override
  void initState() {
    super.initState();

    // Drive animation runs across 2.0 seconds while post is processing
    _driveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );

    _driveAnimation = CurvedAnimation(
      parent: _driveController,
      curve: Curves.easeInOutCubic,
    );

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _startFlow();
  }

  void _startFlow() async {
    _driveController.forward();

    // Call the actual task creation API in parallel
    try {
      final success = await widget.onPostTask();
      _postSuccess = success;
    } catch (_) {
      _postSuccess = false;
    }

    if (!mounted) return;

    // Ensure the driving animation has at least reached 90% so the user enjoys the cartoon run
    if (_driveController.value < 0.90) {
      await Future.delayed(
        Duration(milliseconds: ((0.95 - _driveController.value) * 2100).toInt().clamp(100, 1500)),
      );
    }

    if (!mounted) return;

    if (_postSuccess) {
      setState(() {
        _isPosted = true;
      });
      _morphController.forward();
    } else {
      // If failed, close dialog after a tiny delay so error can be shown
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
      canPop: _isPosted, // Prevent dismissing mid-flight
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 330,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.95, end: 1.0).animate(anim),
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
  // STAGE 1: WHILE POSTING (Vehicle running along curved road)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostingView() {
    return AnimatedBuilder(
      key: const ValueKey('stage1_posting'),
      animation: _driveAnimation,
      builder: (context, _) {
        final progress = _driveAnimation.value;
        final percentInt = (progress * 100).clamp(0, 100).toInt();

        String statusText = 'Loading status';
        if (percentInt < 30) {
          statusText = 'Preparing task details...';
        } else if (percentInt < 70) {
          statusText = 'Securing escrow budget...';
        } else if (percentInt < 95) {
          statusText = 'Broadcasting to nearby helpers...';
        } else {
          statusText = 'Finalizing task...';
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Arched Road Track with Running Vehicle
            SizedBox(
              height: 190,
              width: double.infinity,
              child: CustomPaint(
                painter: _RoadTrackPainter(),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Animated Vehicle positioning along curved road arc
                    _buildAnimatedVehicleOnRoad(progress),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Progress text row: "Posting your task..." on left, "85%" on right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Posting your task...',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  '$percentInt%',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Vibrant Royal Blue Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1D64EC)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Subtitle / Status message
            Text(
              statusText,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Calculates position and tilt along the arched road curve
  Widget _buildAnimatedVehicleOnRoad(double t) {
    // Road arc parameters: starts lower on left, peaks in center, slopes down to right
    const double trackWidth = 270.0;
    const double startX = 10.0;
    final double posX = startX + (trackWidth * t);

    // Parabolic arc for Y: y = a*(x-x0)^2 + peak
    // Normalized x from 0 to 1
    final double nx = t;
    // Base hill curve: starts at y=110, peaks at y=45 at t=0.55, ends at y=95 at t=1.0
    final double posY = 105.0 - (75.0 * math.sin(nx * math.pi));

    // Tangent angle for realistic vehicle tilt along road
    final double slope = -75.0 * math.pi * math.cos(nx * math.pi) / trackWidth;
    final double rotationAngle = math.atan(slope) * 0.75;

    Widget vehicleSprite;
    if (_isMoving) {
      vehicleSprite = Image.asset(
        'assets/images/popup_truck_driving.png',
        width: 105,
        height: 75,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackTruck(),
      );
    } else if (_isRikshaw) {
      vehicleSprite = Image.asset(
        'assets/images/vehicle_rikshaw.png',
        width: 85,
        height: 70,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackScooter(),
      );
    } else {
      vehicleSprite = Image.asset(
        'assets/images/popup_scooter_driving.png',
        width: 90,
        height: 75,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackScooter(),
      );
    }

    return Positioned(
      left: posX - 45,
      top: posY - 55,
      child: Transform.rotate(
        angle: rotationAngle,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Cartoon smoke dust puffs trailing behind
            if (t > 0.08)
              Opacity(
                opacity: (1.0 - (t * 0.3)).clamp(0.4, 0.95),
                child: Padding(
                  padding: const EdgeInsets.only(right: 2, bottom: 8),
                  child: Image.asset(
                    'assets/images/popup_dust_puffs.png',
                    width: 32,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text(
                      '💨',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            vehicleSprite,
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STAGE 2: TASK POSTED (Vehicle parked + delivery box + "Track in My Tasks")
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostedView() {
    final title = _isMoving ? 'Moving Task Posted!' : 'Task Posted!';
    final distStr = widget.distanceKm != null
        ? '${widget.distanceKm!.toStringAsFixed(1)} km'
        : '2.4 km';
    final budgetStr = '₹${widget.budget.toInt()}';

    String pillText;
    if (_isMoving) {
      pillText = 'Moving • Mini Truck • $budgetStr';
    } else if (_isRikshaw) {
      pillText = 'Delivery • Auto • $budgetStr';
    } else {
      pillText = 'Delivery • $distStr • $budgetStr';
    }

    Widget heroIllustration;
    if (_isMoving) {
      heroIllustration = Image.asset(
        'assets/images/popup_moving_truck.png',
        height: 185,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackTruckHero(),
      );
    } else {
      heroIllustration = Image.asset(
        'assets/images/popup_delivery_scooter.png',
        height: 185,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _buildFallbackScooterHero(),
      );
    }

    return Column(
      key: const ValueKey('stage2_posted'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Cartoon Vehicle + Delivery Box / Cargo Illustration
        SizedBox(
          height: 190,
          child: Center(child: heroIllustration),
        ),
        const SizedBox(height: 14),

        // Bold Headline: "Task Posted!" or "Moving Task Posted!"
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 5),

        // Subtitle: "Waiting for helper..."
        const Text(
          'Waiting for helper...',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),

        // Task Detail Pill: e.g. "Delivery • 2.4 km • ₹250"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            pillText,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ),
        const SizedBox(height: 20),

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
              backgroundColor: const Color(0xFF1D64EC),
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

  // ── Fallback Graphic Builders (if assets take milliseconds to initialize) ─
  Widget _buildFallbackScooter() {
    return const Icon(Icons.two_wheeler_rounded, size: 64, color: Color(0xFF0284C7));
  }

  Widget _buildFallbackTruck() {
    return const Icon(Icons.local_shipping_rounded, size: 70, color: Color(0xFF0284C7));
  }

  Widget _buildFallbackScooterHero() {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.two_wheeler_rounded, size: 100, color: Color(0xFF0284C7)),
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

  Widget _buildFallbackTruckHero() {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.local_shipping_rounded, size: 110, color: Color(0xFF0284C7)),
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

/// Custom painter for drawing the arched road track with dashed divider line
class _RoadTrackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final dashPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Road top boundary curve: arched mound
    final topPath = Path();
    topPath.moveTo(0, size.height * 0.65);
    topPath.quadraticBezierTo(
      size.width * 0.52,
      size.height * 0.16,
      size.width,
      size.height * 0.60,
    );
    canvas.drawPath(topPath, borderPaint);

    // Road bottom boundary curve
    final bottomPath = Path();
    bottomPath.moveTo(0, size.height * 0.77);
    bottomPath.quadraticBezierTo(
      size.width * 0.52,
      size.height * 0.30,
      size.width,
      size.height * 0.73,
    );
    canvas.drawPath(bottomPath, borderPaint);

    // Center dashed divider line along the road
    const double dashWidth = 8.0;
    const double dashSpace = 7.0;
    final int numDashes = (size.width / (dashWidth + dashSpace)).floor();

    for (int i = 0; i < numDashes; i++) {
      final double t1 = i / numDashes;
      final double t2 = (i + 0.55) / numDashes;

      final p1 = _getArcPoint(t1, size, 0.71, 0.23, 0.665);
      final p2 = _getArcPoint(t2, size, 0.71, 0.23, 0.665);

      canvas.drawLine(p1, p2, dashPaint);
    }
  }

  Offset _getArcPoint(double t, Size size, double startY, double peakY, double endY) {
    final double x = size.width * t;
    // Quadratic bezier point: B(t) = (1-t)^2 * P0 + 2(1-t)t * P1 + t^2 * P2
    final double y0 = size.height * startY;
    final double y1 = size.height * peakY;
    final double y2 = size.height * endY;

    final double y = math.pow(1 - t, 2) * y0 + 2 * (1 - t) * t * y1 + math.pow(t, 2) * y2;
    return Offset(x, y);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
