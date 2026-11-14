import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A high-fidelity, realistic popup dialog for Workmate4u task posting.
///
/// Implements:
/// - Stage 1 (Posting In-Progress):
///   - Clean white card with rounded corners (24px).
///   - Winding road with start pin (📍) and finish flag (🏁).
///   - Selected vehicle moves in a continuous smooth loop along the winding road!
///   - Vehicle tilts naturally with the road curve and bobs with suspension motion.
///   - Contained strictly within the card boundaries (never overflows).
///   - Headline: "Posting your task..."
///   - Clean circular loading spinner.
///
/// - Stage 2 (Task is Posted!):
///   - 3D vehicle parked beside delivery parcel box (or cargo boxes + mover) with green check badge.
///   - Headline: "Task is Posted!"
///   - Mint Status Pill: "🟢 Waiting for Helper..."
///   - Detail Pill: "[Vehicle] • Instant Radar Active"
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
  late AnimationController _loopController;
  late AnimationController _morphController;

  bool _isPosted = false;
  bool _apiCompleted = false;
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

  String get _vehicleSpriteAsset {
    if (_isMoving) return 'assets/images/popup_truck_driving.png';
    if (_isRikshaw) return 'assets/images/vehicle_rikshaw.png';
    return 'assets/images/scooter_sprite_clean.png';
  }

  String get _postedHeroAsset {
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

    // 2.6 seconds per loop iteration along the road track
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Add status listener to smoothly transition once API finishes
    _loopController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_apiCompleted && _postSuccess) {
          // Finished driving across: transition to Stage 2
          if (mounted) {
            setState(() => _isPosted = true);
            _morphController.forward();
          }
        } else if (_apiCompleted && !_postSuccess) {
          if (mounted) Navigator.of(context).pop(false);
        } else {
          // Continue looping along the road
          _loopController.forward(from: 0.0);
        }
      }
    });

    _startFlow();
  }

  void _startFlow() async {
    _loopController.forward();

    try {
      final success = await widget.onPostTask();
      _postSuccess = success;
    } catch (_) {
      _postSuccess = false;
    }

    _apiCompleted = true;

    if (!mounted) return;

    // If API responded very fast, ensure at least one full loop completes
    // The addStatusListener will trigger the transition when it reaches 1.0
  }

  @override
  void dispose() {
    _loopController.dispose();
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
  // STAGE 1: WHILE POSTING (Vehicle moving in a loop on winding road)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostingView() {
    return Column(
      key: const ValueKey('stage1_posting'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Strictly contained road canvas + looping vehicle
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.white,
            height: 185,
            width: double.infinity,
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _loopController,
              builder: (context, _) {
                final double t = _loopController.value;
                return CustomPaint(
                  size: const Size(275, 185),
                  painter: _WindingRoadPainter(loopProgress: t),
                  child: SizedBox(
                    width: 275,
                    height: 185,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        // Animated Vehicle traversing the winding road
                        _buildLoopingVehicle(t),
                      ],
                    ),
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

        // Modern circular loading spinner
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

  /// Calculates position and angle along the winding road curve
  Widget _buildLoopingVehicle(double t) {
    // Road curve geometry inside 275x185 box:
    // Start Pin: (28, 70), End Flag: (245, 65)
    // S-curve road path
    final roadPath = Path()
      ..moveTo(26, 96)
      ..quadraticBezierTo(85, 134, 140, 102)
      ..quadraticBezierTo(195, 70, 245, 88);

    final metrics = roadPath.computeMetrics().first;
    // Keep vehicle safely bounded between 0.05 and 0.95 of the track
    final double safeT = 0.04 + (t * 0.90);
    final tangent = metrics.getTangentForOffset(metrics.length * safeT);

    final double posX = tangent?.position.dx ?? (30 + (210 * t));
    final double posY = tangent?.position.dy ?? (100 - (20 * math.sin(t * math.pi)));
    final double angle = tangent?.angle ?? 0.0;

    // Gentle road suspension bobbing
    final double bobY = math.sin(t * 14 * math.pi) * 1.8;

    // Vehicle dimension
    final double vWidth = _isMoving ? 75 : (_isRikshaw ? 60 : 66);
    final double vHeight = _isMoving ? 58 : (_isRikshaw ? 54 : 54);

    return Positioned(
      left: posX - (vWidth * 0.5),
      top: posY - (vHeight * 0.85) + bobY,
      child: Transform.rotate(
        angle: angle * 0.85,
        alignment: Alignment.center,
        child: Image.asset(
          _vehicleSpriteAsset,
          width: vWidth,
          height: vHeight,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            _isMoving ? Icons.local_shipping_rounded : Icons.two_wheeler_rounded,
            size: 48,
            color: const Color(0xFF2563EB),
          ),
        ),
      ),
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
              _postedHeroAsset,
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

/// Custom painter for the winding road track with start pin and finish flag
class _WindingRoadPainter extends CustomPainter {
  final double loopProgress;

  _WindingRoadPainter({required this.loopProgress});

  @override
  void paint(Canvas canvas, Size size) {
    // S-curve road path definition
    final roadPath = Path()
      ..moveTo(26, 96)
      ..quadraticBezierTo(85, 134, 140, 102)
      ..quadraticBezierTo(195, 70, 245, 88);

    // 1. Road shadow
    final shadowPaint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(roadPath.shift(const Offset(0, 3)), shadowPaint);

    // 2. Asphalt Road Ribbon
    final roadPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(roadPath, roadPaint);

    // 3. Road Borders
    final borderPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final topEdge = Path()
      ..moveTo(26, 96 - 15)
      ..quadraticBezierTo(85, 134 - 15, 140, 102 - 15)
      ..quadraticBezierTo(195, 70 - 15, 245, 88 - 15);
    canvas.drawPath(topEdge, borderPaint);

    final bottomEdge = Path()
      ..moveTo(26, 96 + 15)
      ..quadraticBezierTo(85, 134 + 15, 140, 102 + 15)
      ..quadraticBezierTo(195, 70 + 15, 245, 88 + 15);
    canvas.drawPath(bottomEdge, borderPaint);

    // 4. Center Dashed Lane Divider
    final dashPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final metrics = roadPath.computeMetrics().first;
    const double dashLength = 7.0;
    const double spaceLength = 6.0;

    // Animate dashed lines subtly flowing along the road
    final double flowOffset = (loopProgress * (dashLength + spaceLength)) % (dashLength + spaceLength);

    for (double d = flowOffset; d < metrics.length; d += (dashLength + spaceLength)) {
      final t1 = metrics.getTangentForOffset(d);
      final t2 = metrics.getTangentForOffset(math.min(d + dashLength, metrics.length));
      if (t1 != null && t2 != null) {
        canvas.drawLine(t1.position, t2.position, dashPaint);
      }
    }

    // 5. Start Location Pin (📍) on left
    _drawStartPin(canvas, const Offset(20, 68));

    // 6. Checkered Finish Flag (🏁) on right
    _drawFinishFlag(canvas, const Offset(245, 62));
  }

  void _drawStartPin(Canvas canvas, Offset pos) {
    // Pin shadow / base circle
    final basePaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(pos.dx + 4, pos.dy + 30), 8, basePaint);

    final innerBasePaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(pos.dx + 4, pos.dy + 30), 3.5, innerBasePaint);

    // Pin head (Royal Blue gradient pin)
    final pinPaint = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(pos.dx + 4, pos.dy + 28);
    path.quadraticBezierTo(pos.dx - 6, pos.dy + 14, pos.dx - 6, pos.dy + 8);
    path.arcToPoint(
      Offset(pos.dx + 14, pos.dy + 8),
      radius: const Radius.circular(10),
    );
    path.quadraticBezierTo(pos.dx + 14, pos.dy + 14, pos.dx + 4, pos.dy + 28);
    path.close();
    canvas.drawPath(path, pinPaint);

    // White dot inside pin
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(pos.dx + 4, pos.dy + 8), 3.5, whitePaint);
  }

  void _drawFinishFlag(Canvas canvas, Offset pos) {
    // Flag pole
    final polePaint = Paint()
      ..color = const Color(0xFF334155)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(pos, Offset(pos.dx, pos.dy + 30), polePaint);

    // Flag banner (checkered)
    const double w = 18;
    const double h = 13;
    final r = Rect.fromLTWH(pos.dx, pos.dy, w, h);

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(r, bgPaint);

    final checkPaint = Paint()..color = const Color(0xFF0F172A);
    // 2x2 checker pattern
    canvas.drawRect(Rect.fromLTWH(pos.dx, pos.dy, w / 2, h / 2), checkPaint);
    canvas.drawRect(Rect.fromLTWH(pos.dx + w / 2, pos.dy + h / 2, w / 2, h / 2), checkPaint);

    // Flag border
    final flagBorder = Paint()
      ..color = const Color(0xFF0F172A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRect(r, flagBorder);
  }

  @override
  bool shouldRepaint(covariant _WindingRoadPainter oldDelegate) =>
      oldDelegate.loopProgress != loopProgress;
}
