import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A 100% pure code vector-animated popup dialog for Workmate4u task posting.
///
/// Built entirely with custom Flutter Canvas code — ZERO cropped or cutoff images:
/// - Stage 1 (Posting In-Progress):
///   - Dynamic arched S-curve road with flowing dashed lane dividers.
///   - Start location pin (📍) with animated ripple rings.
///   - Checkered racing flag (🏁) at the finish.
///   - 100% Vector Vehicle (Scooter, Mini-Truck, or Auto-Rikshaw) looping smoothly on the road.
///   - Rotating wheel spokes, engine suspension bobbing, motion speed lines, and exhaust smoke puffs (💨).
///   - Headline: "Posting your task..." on left with animated percentage ("85%") on right.
///   - Sleek rounded linear progress bar and "Loading status" subtitle.
///   - Fully contained within the card boundaries (never overflows).
///
/// - Stage 2 (Task Posted!):
///   - Delivery: Cute cartoon scooter with rear parcel box and floating scalloped emerald green checkmark badge (✓).
///   - Moving: White mini-truck loaded with furniture & cardboard boxes, with friendly mover helper guy waving (👋)!
///   - Auto/Transport: Auto-Rikshaw or Cab with luggage and green check badge.
///   - Bold Headline: "Task Posted!" (or "Moving Task Posted!")
///   - Subtitle: "Waiting for helper..."
///   - Info Pill: "Delivery • 2.4 km • ₹250" or "Moving • Mini Truck • ₹850"
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
  late AnimationController _progressController;
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

  String get _infoPillText {
    final catName = _isMoving
        ? 'Moving'
        : (widget.category.isNotEmpty
            ? widget.category[0].toUpperCase() + widget.category.substring(1)
            : 'Delivery');

    final String middleDetail;
    if (_isMoving) {
      middleDetail = 'Mini Truck';
    } else if (widget.distanceKm != null && widget.distanceKm! > 0) {
      middleDetail = '${widget.distanceKm!.toStringAsFixed(1)} km';
    } else if (_isRikshaw) {
      middleDetail = 'Auto';
    } else if (_isCar) {
      middleDetail = 'Cab';
    } else {
      middleDetail = 'Bike';
    }

    final budgetStr = '₹${widget.budget.toInt()}';
    return '$catName • $middleDetail • $budgetStr';
  }

  @override
  void initState() {
    super.initState();

    // 2.8 seconds per loop iteration along the road track
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    // Linear progress animation controller (ramps smoothly from 15% towards 92%)
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..forward();

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Loop continuously until the background API call finishes
    _loopController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        if (_apiCompleted && _postSuccess) {
          _progressController.animateTo(1.0, duration: const Duration(milliseconds: 200)).then((_) {
            if (mounted) {
              setState(() => _isPosted = true);
              _morphController.forward();
            }
          });
        } else if (_apiCompleted && !_postSuccess) {
          if (mounted) Navigator.of(context).pop(false);
        } else {
          // Restart loop smoothly from the start
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
  }

  @override
  void dispose() {
    _loopController.dispose();
    _progressController.dispose();
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
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 36,
                  offset: const Offset(0, 14),
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
  // STAGE 1: WHILE POSTING (Pure Code Vector Road + Vehicle Looping)
  // Matches Image 1 Right Card & Image 2 Left Screen
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostingView() {
    return Column(
      key: const ValueKey('stage1_posting'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pure Vector Road + Vehicle Animation Canvas
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.white,
            height: 180,
            width: double.infinity,
            alignment: Alignment.center,
            child: AnimatedBuilder(
              animation: _loopController,
              builder: (context, _) {
                final double t = _loopController.value;
                return CustomPaint(
                  size: const Size(275, 180),
                  painter: _VectorVehicleScenePainter(
                    progress: t,
                    isMoving: _isMoving,
                    isRikshaw: _isRikshaw,
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Headline & Percentage Row: "Posting your task... 85%"
        AnimatedBuilder(
          animation: _progressController,
          builder: (context, _) {
            // Curves smoothly from 0.20 to 0.88 while API runs, up to 1.0 when done
            final double rawVal = _progressController.value;
            final double pctVal = 0.20 + (rawVal * 0.68);
            final int displayPct = (pctVal * 100).clamp(15, 99).toInt();

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Posting your task...',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      '$displayPct%',
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Rounded Blue Linear Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: pctVal,
                    minHeight: 7,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),

        // Subtitle: "Loading status"
        const Text(
          'Loading status',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STAGE 2: TASK POSTED (Parked Vector Vehicle + Scalloped Green Badge)
  // Matches Image 1 Left & Middle Cards & Image 2 Right Screen
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPostedView() {
    final String headline = _isMoving ? 'Moving Task Posted!' : 'Task Posted!';

    return Column(
      key: const ValueKey('stage2_posted'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Top Parked Vector Vehicle + Delivery Parcel Box / Mover Illustration
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            color: Colors.white,
            height: 185,
            width: double.infinity,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(275, 185),
              painter: _VectorPostedHeroPainter(
                isMoving: _isMoving,
                isRikshaw: _isRikshaw,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Bold Headline: "Task Posted!" or "Moving Task Posted!"
        Text(
          headline,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 21,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 6),

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
        const SizedBox(height: 12),

        // Detail Pill: e.g. "Delivery • 2.4 km • ₹250" or "Moving • Mini Truck • ₹850"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7.5),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            _infoPillText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// 100% PURE CODE VECTOR PAINTER: ANIMATED ROAD + LOOPING VEHICLE (STAGE 1)
// ─────────────────────────────────────────────────────────────────────────────
class _VectorVehicleScenePainter extends CustomPainter {
  final double progress; // 0.0 -> 1.0 (looping)
  final bool isMoving;
  final bool isRikshaw;

  _VectorVehicleScenePainter({
    required this.progress,
    required this.isMoving,
    required this.isRikshaw,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Winding Road Curve (Arched S-Curve)
    final roadPath = Path()
      ..moveTo(24, 102)
      ..quadraticBezierTo(85, 138, 140, 106)
      ..quadraticBezierTo(195, 72, 248, 90);

    // Road ground shadow
    final shadowPaint = Paint()
      ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(roadPath.shift(const Offset(0, 3)), shadowPaint);

    // Asphalt road surface
    final roadPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 30
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(roadPath, roadPaint);

    // Road top & bottom borders
    final borderPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final topEdge = Path()
      ..moveTo(24, 102 - 15)
      ..quadraticBezierTo(85, 138 - 15, 140, 106 - 15)
      ..quadraticBezierTo(195, 72 - 15, 248, 90 - 15);
    canvas.drawPath(topEdge, borderPaint);

    final bottomEdge = Path()
      ..moveTo(24, 102 + 15)
      ..quadraticBezierTo(85, 138 + 15, 140, 106 + 15)
      ..quadraticBezierTo(195, 72 + 15, 248, 90 + 15);
    canvas.drawPath(bottomEdge, borderPaint);

    // Center Dashed Lane Divider (flowing backwards as vehicle drives forward)
    final dashPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    final metrics = roadPath.computeMetrics().first;
    const double dashLength = 7.0;
    const double spaceLength = 6.0;
    final double flowOffset = (progress * (dashLength + spaceLength)) % (dashLength + spaceLength);

    for (double d = flowOffset; d < metrics.length; d += (dashLength + spaceLength)) {
      final t1 = metrics.getTangentForOffset(d);
      final t2 = metrics.getTangentForOffset(math.min(d + dashLength, metrics.length));
      if (t1 != null && t2 != null) {
        canvas.drawLine(t1.position, t2.position, dashPaint);
      }
    }

    // 2. Start Pin (📍) on left
    _drawStartPin(canvas, const Offset(20, 74));

    // 3. Checkered Finish Flag (🏁) on right
    _drawFinishFlag(canvas, const Offset(246, 64));

    // 4. Calculate Vehicle Position along curve
    final double safeT = 0.05 + (progress * 0.88);
    final tangent = metrics.getTangentForOffset(metrics.length * safeT);
    final double posX = tangent?.position.dx ?? (30 + (210 * progress));
    final double posY = tangent?.position.dy ?? (106 - (20 * math.sin(progress * math.pi)));
    final double angle = tangent?.angle ?? 0.0;

    // Suspension bobbing and wheel spin angle
    final double bobY = math.sin(progress * 16 * math.pi) * 1.5;
    final double wheelSpin = progress * 24 * math.pi;

    // Draw Tailpipe Exhaust Smoke Puffs (💨) and motion speed lines
    _drawExhaustPuffs(canvas, Offset(posX - 24, posY - 8 + bobY), progress);
    _drawSpeedLines(canvas, Offset(posX - 30, posY - 14 + bobY), progress);

    // 5. Draw Vehicle
    canvas.save();
    canvas.translate(posX, posY + bobY);
    canvas.rotate(angle * 0.85);

    if (isMoving) {
      _drawVectorTruck(canvas, wheelSpin);
    } else if (isRikshaw) {
      _drawVectorRikshaw(canvas, wheelSpin);
    } else {
      _drawVectorScooter(canvas, wheelSpin);
    }
    canvas.restore();
  }

  // ── SPEED MOTION LINES ───────────────────────────────────────────────────
  void _drawSpeedLines(Canvas canvas, Offset origin, double t) {
    final speedPaint = Paint()
      ..color = const Color(0xFF94A3B8).withValues(alpha: 0.50)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final double dashAnim = (t * 8) % 1.0;
    canvas.drawLine(
      Offset(origin.dx - 12 - (dashAnim * 6), origin.dy),
      Offset(origin.dx - (dashAnim * 6), origin.dy),
      speedPaint,
    );
    canvas.drawLine(
      Offset(origin.dx - 18 - (dashAnim * 8), origin.dy + 8),
      Offset(origin.dx - 4 - (dashAnim * 8), origin.dy + 8),
      speedPaint,
    );
  }

  // ── PURE VECTOR SCOOTER (Cute Cartoon with Teal trim & Delivery Box) ──────
  void _drawVectorScooter(Canvas canvas, double wheelSpin) {
    canvas.save();
    canvas.scale(0.85);
    canvas.translate(-30, -32);

    // Oval ground shadow
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.15);
    canvas.drawOval(const Rect.fromLTWH(8, 30, 48, 6), shadowPaint);

    // Rear Wheel at (14, 30)
    _drawWheel(canvas, const Offset(14, 30), 8.0, wheelSpin);
    // Front Wheel at (52, 30)
    _drawWheel(canvas, const Offset(52, 30), 8.0, wheelSpin);

    // Scooter Body / Shroud (Warm Golden Yellow Gradient)
    final yellowPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(12, 10, 44, 25));

    // Curved rear shroud
    final rearShroud = RRect.fromRectAndRadius(
      const Rect.fromLTWH(10, 18, 22, 12),
      const Radius.circular(6),
    );
    canvas.drawRRect(rearShroud, yellowPaint);

    // Teal Body Accent Trim (matches Image 1 Scooter!)
    final tealPaint = Paint()..color = const Color(0xFF0D9488);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(16, 22, 14, 4), const Radius.circular(2)),
      tealPaint,
    );

    // Footboard
    final footboardPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(26, 26, 16, 4), const Radius.circular(2)),
      footboardPaint,
    );

    // Front Fairing & Steering Column (Yellow with Teal Front Shield)
    final fairingPath = Path()
      ..moveTo(40, 26)
      ..lineTo(48, 12)
      ..lineTo(54, 12)
      ..lineTo(50, 28)
      ..close();
    canvas.drawPath(fairingPath, yellowPaint);

    // Teal front cowl accent
    final tealFront = Path()
      ..moveTo(43, 24)
      ..lineTo(48, 14)
      ..lineTo(51, 14)
      ..lineTo(48, 26)
      ..close();
    canvas.drawPath(tealFront, tealPaint);

    // Front Fender
    final fenderPaint = Paint()..color = const Color(0xFFF59E0B);
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(52, 30), radius: 10.5),
      math.pi,
      math.pi * 0.75,
      false,
      fenderPaint..style = PaintingStyle.stroke..strokeWidth = 3,
    );

    // Black Leather Seat
    final seatPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 13, 20, 6), const Radius.circular(3)),
      seatPaint,
    );

    // Handlebar & Chrome Mirror
    final chromePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(49, 12), const Offset(46, 6), chromePaint);
    canvas.drawCircle(const Offset(45, 5), 2.5, Paint()..color = const Color(0xFF94A3B8));

    // Round Headlight (Glowing)
    canvas.drawCircle(const Offset(53, 13), 3.5, Paint()..color = const Color(0xFFFEF08A));
    canvas.drawCircle(const Offset(53, 13), 2.0, Paint()..color = Colors.white);

    // Cardboard Delivery Parcel Box on Rear Rack (Image 1 Style)
    final boxPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFD97706), Color(0xFFB45309)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(4, 4, 18, 16));

    final boxRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4, 4, 18, 16),
      const Radius.circular(3),
    );
    canvas.drawRRect(boxRRect, boxPaint);

    // Yellow packaging tape
    final stripePaint = Paint()..color = const Color(0xFFFDE68A);
    canvas.drawRect(const Rect.fromLTWH(11, 4, 4, 16), stripePaint);

    // White shipping label
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(6, 12, 4, 5), const Radius.circular(1)),
      Paint()..color = Colors.white,
    );

    canvas.restore();
  }

  // ── PURE VECTOR MINI-TRUCK (White Cab + Wooden Cargo Bed with Boxes) ───────
  void _drawVectorTruck(Canvas canvas, double wheelSpin) {
    canvas.save();
    canvas.scale(0.80);
    canvas.translate(-38, -34);

    // Ground shadow
    canvas.drawOval(
      const Rect.fromLTWH(4, 32, 68, 6),
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );

    // Wheels at (18, 32) and (56, 32)
    _drawWheel(canvas, const Offset(18, 32), 8.5, wheelSpin);
    _drawWheel(canvas, const Offset(56, 32), 8.5, wheelSpin);

    // Metal Flatbed Chassis
    final bedPaint = Paint()..color = const Color(0xFF64748B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(4, 25, 42, 6), const Radius.circular(2)),
      bedPaint,
    );

    // Stacked Cardboard Moving Boxes on flatbed
    final boxPaint1 = Paint()..color = const Color(0xFFD97706);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(6, 12, 18, 14), const Radius.circular(2)),
      boxPaint1,
    );
    canvas.drawLine(const Offset(15, 12), const Offset(15, 26), Paint()..color = const Color(0xFFFDE68A)..strokeWidth = 2);

    final boxPaint2 = Paint()..color = const Color(0xFFB45309);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(22, 8, 18, 18), const Radius.circular(2)),
      boxPaint2,
    );
    canvas.drawLine(const Offset(22, 17), const Offset(40, 17), Paint()..color = const Color(0xFFFDE68A)..strokeWidth = 2);

    // Truck Cabin (White with blue windshield)
    final cabPaint = Paint()..color = const Color(0xFFF8FAFC);
    final cabPath = Path()
      ..moveTo(42, 30)
      ..lineTo(68, 30)
      ..quadraticBezierTo(72, 30, 72, 24)
      ..lineTo(70, 12)
      ..quadraticBezierTo(68, 6, 60, 6)
      ..lineTo(44, 6)
      ..close();
    canvas.drawPath(cabPath, cabPaint);
    canvas.drawPath(cabPath, Paint()..color = const Color(0xFFCBD5E1)..style = PaintingStyle.stroke..strokeWidth = 1.2);

    // Windshield (Blue Tint)
    final glassPaint = Paint()..color = const Color(0xFF93C5FD);
    final glassPath = Path()
      ..moveTo(48, 8)
      ..lineTo(60, 8)
      ..lineTo(67, 18)
      ..lineTo(48, 18)
      ..close();
    canvas.drawPath(glassPath, glassPaint);

    // Headlight
    canvas.drawCircle(const Offset(70, 24), 2.5, Paint()..color = const Color(0xFFFEF08A));

    canvas.restore();
  }

  // ── PURE VECTOR AUTO-RIKSHAW ──────────────────────────────────────────────
  void _drawVectorRikshaw(Canvas canvas, double wheelSpin) {
    canvas.save();
    canvas.scale(0.82);
    canvas.translate(-32, -32);

    // Ground shadow
    canvas.drawOval(
      const Rect.fromLTWH(6, 32, 54, 6),
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );

    // Rear Wheel at (16, 32), Front Wheel at (52, 32)
    _drawWheel(canvas, const Offset(16, 32), 8.0, wheelSpin);
    _drawWheel(canvas, const Offset(52, 32), 8.0, wheelSpin);

    // Rikshaw Lower Body (Emerald Green)
    final greenPaint = Paint()..color = const Color(0xFF059669);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(8, 20, 48, 11), const Radius.circular(4)),
      greenPaint,
    );

    // Yellow Canopy Top
    final yellowPaint = Paint()..color = const Color(0xFFFBBF24);
    final canopyPath = Path()
      ..moveTo(6, 20)
      ..lineTo(10, 6)
      ..quadraticBezierTo(30, 3, 50, 6)
      ..lineTo(54, 20)
      ..close();
    canvas.drawPath(canopyPath, yellowPaint);

    // Front Windshield
    canvas.drawRect(const Rect.fromLTWH(42, 8, 8, 12), Paint()..color = const Color(0xFF93C5FD));

    // Passenger cabin open window with delivery box
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(12, 10, 16, 12), const Radius.circular(2)),
      Paint()..color = const Color(0xFFD97706),
    );

    // Headlight
    canvas.drawCircle(const Offset(54, 23), 2.5, Paint()..color = const Color(0xFFFEF08A));

    canvas.restore();
  }

  // ── ROTATING WHEEL WITH SPOKES ───────────────────────────────────────────
  void _drawWheel(Canvas canvas, Offset center, double radius, double wheelSpin) {
    // Outer black rubber tire
    final tirePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, tirePaint);

    // Inner rim
    final rimPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.65, rimPaint);

    // Rotating Spokes
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(wheelSpin);

    final spokePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 0; i < 4; i++) {
      final double a = (i * math.pi) / 2;
      canvas.drawLine(
        Offset(-math.cos(a) * (radius * 0.55), -math.sin(a) * (radius * 0.55)),
        Offset(math.cos(a) * (radius * 0.55), math.sin(a) * (radius * 0.55)),
        spokePaint,
      );
    }

    // Central hub
    canvas.drawCircle(Offset.zero, 1.8, Paint()..color = const Color(0xFF0F172A));
    canvas.restore();
  }

  // ── ANIMATED EXHAUST SMOKE PUFFS ──────────────────────────────────────────
  void _drawExhaustPuffs(Canvas canvas, Offset tailpipe, double t) {
    final puffPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < 3; i++) {
      final double puffT = (t * 4.0 + (i * 0.33)) % 1.0;
      final double puffDist = puffT * 26.0;
      final double puffSize = 2.5 + (puffT * 4.5);
      final double puffAlpha = (1.0 - puffT).clamp(0.0, 0.6);

      puffPaint.color = const Color(0xFF94A3B8).withValues(alpha: puffAlpha);
      canvas.drawCircle(
        Offset(tailpipe.dx - puffDist, tailpipe.dy - (puffT * 4.0)),
        puffSize,
        puffPaint,
      );
    }
  }

  // ── START LOCATION PIN ───────────────────────────────────────────────────
  void _drawStartPin(Canvas canvas, Offset pos) {
    // Pulse ring
    final double pulse = (progress * 2.0) % 1.0;
    canvas.drawCircle(
      Offset(pos.dx + 4, pos.dy + 28),
      6 + (pulse * 6),
      Paint()..color = const Color(0xFF2563EB).withValues(alpha: (1.0 - pulse) * 0.3),
    );

    // Green base dot
    canvas.drawCircle(Offset(pos.dx + 4, pos.dy + 28), 3.5, Paint()..color = const Color(0xFF10B981));

    // Blue location pin
    final pinPaint = Paint()..color = const Color(0xFF2563EB);
    final path = Path()
      ..moveTo(pos.dx + 4, pos.dy + 26)
      ..quadraticBezierTo(pos.dx - 6, pos.dy + 14, pos.dx - 6, pos.dy + 8)
      ..arcToPoint(Offset(pos.dx + 14, pos.dy + 8), radius: const Radius.circular(10))
      ..quadraticBezierTo(pos.dx + 14, pos.dy + 14, pos.dx + 4, pos.dy + 26)
      ..close();
    canvas.drawPath(path, pinPaint);

    // Inner white dot
    canvas.drawCircle(Offset(pos.dx + 4, pos.dy + 8), 3.2, Paint()..color = Colors.white);
  }

  // ── CHECKERED FINISH FLAG ────────────────────────────────────────────────
  void _drawFinishFlag(Canvas canvas, Offset pos) {
    // Pole
    canvas.drawLine(
      pos,
      Offset(pos.dx, pos.dy + 28),
      Paint()..color = const Color(0xFF334155)..strokeWidth = 2.0..strokeCap = StrokeCap.round,
    );

    // Checkered Banner with subtle wave
    const double w = 18;
    const double h = 13;
    final r = Rect.fromLTWH(pos.dx, pos.dy, w, h);

    canvas.drawRect(r, Paint()..color = Colors.white);

    final checkPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(pos.dx, pos.dy, w / 2, h / 2), checkPaint);
    canvas.drawRect(Rect.fromLTWH(pos.dx + w / 2, pos.dy + h / 2, w / 2, h / 2), checkPaint);

    canvas.drawRect(
      r,
      Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.stroke..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(covariant _VectorVehicleScenePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// 100% PURE CODE VECTOR PAINTER: STAGE 2 PARKED HERO ILLUSTRATION
// Matches Image 1 Left & Middle Cards
// ─────────────────────────────────────────────────────────────────────────────
class _VectorPostedHeroPainter extends CustomPainter {
  final bool isMoving;
  final bool isRikshaw;

  _VectorPostedHeroPainter({required this.isMoving, required this.isRikshaw});

  @override
  void paint(Canvas canvas, Size size) {
    if (isMoving) {
      _paintMovingHeroScene(canvas, size);
    } else {
      _paintDeliveryHeroScene(canvas, size);
    }
  }

  // ── DELIVERY HERO SCENE (Image 1 Left Card) ──────────────────────────────
  void _paintDeliveryHeroScene(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.44, size.height * 0.58);

    // Ground platform shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.48, size.height * 0.84), width: 175, height: 16),
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );

    canvas.save();
    canvas.translate(center.dx - 48, center.dy - 38);
    canvas.scale(1.30);

    if (isRikshaw) {
      _drawParkedRikshaw(canvas);
    } else {
      _drawParkedScooter(canvas);
    }
    canvas.restore();

    // Floating Scalloped Green Checkmark Badge (✓) at top right of vehicle (Image 1 style)
    _drawScallopedBadge(canvas, Offset(size.width * 0.78, size.height * 0.35), 18.0);
  }

  // ── MOVING HERO SCENE (Image 1 Middle Card: Truck + Boxes + Waving Helper) ─
  void _paintMovingHeroScene(Canvas canvas, Size size) {
    // Ground platform shadow
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.48, size.height * 0.84), width: 220, height: 16),
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );

    // Draw Mini-Truck on left side of card
    canvas.save();
    canvas.translate(size.width * 0.12, size.height * 0.38);
    canvas.scale(1.10);
    _drawLoadedMovingTruck(canvas);
    canvas.restore();

    // Draw Friendly Cartoon Mover Helper Guy waving cheerfully beside the truck (Image 1 style!)
    _drawMoverHelper(canvas, Offset(size.width * 0.80, size.height * 0.80));
  }

  // ── PARKED CUTE CARTOON SCOOTER (Teal + Yellow + Parcel Box on Rack) ──────
  void _drawParkedScooter(Canvas canvas) {
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.14);
    canvas.drawOval(const Rect.fromLTWH(8, 30, 48, 6), shadowPaint);

    _drawStaticWheel(canvas, const Offset(14, 30), 8.0);
    _drawStaticWheel(canvas, const Offset(52, 30), 8.0);

    final yellowPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(12, 10, 44, 25));

    // Curved rear yellow body
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(10, 18, 22, 12), const Radius.circular(6)),
      yellowPaint,
    );

    // Teal body accent trim
    final tealPaint = Paint()..color = const Color(0xFF0D9488);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(16, 22, 14, 4), const Radius.circular(2)),
      tealPaint,
    );

    // Footboard
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(26, 26, 16, 4), const Radius.circular(2)),
      Paint()..color = const Color(0xFF1E293B),
    );

    // Steering Column & Fairing
    final fairingPath = Path()
      ..moveTo(40, 26)
      ..lineTo(48, 12)
      ..lineTo(54, 12)
      ..lineTo(50, 28)
      ..close();
    canvas.drawPath(fairingPath, yellowPaint);

    // Teal cowl
    final tealFront = Path()
      ..moveTo(43, 24)
      ..lineTo(48, 14)
      ..lineTo(51, 14)
      ..lineTo(48, 26)
      ..close();
    canvas.drawPath(tealFront, tealPaint);

    // Front Fender
    canvas.drawArc(
      Rect.fromCircle(center: const Offset(52, 30), radius: 10.5),
      math.pi,
      math.pi * 0.75,
      false,
      Paint()..color = const Color(0xFFF59E0B)..style = PaintingStyle.stroke..strokeWidth = 3,
    );

    // Black Leather Seat
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(14, 13, 20, 6), const Radius.circular(3)),
      Paint()..color = const Color(0xFF0F172A),
    );

    // Chrome handlebar and mirror
    final chromePaint = Paint()..color = const Color(0xFFCBD5E1)..style = PaintingStyle.stroke..strokeWidth = 2.0;
    canvas.drawLine(const Offset(49, 12), const Offset(46, 6), chromePaint);
    canvas.drawCircle(const Offset(45, 5), 2.5, Paint()..color = const Color(0xFF94A3B8));

    // Headlight
    canvas.drawCircle(const Offset(53, 13), 3.5, Paint()..color = const Color(0xFFFEF08A));

    // Chrome luggage rack holding parcel box
    canvas.drawLine(const Offset(4, 20), const Offset(12, 20), chromePaint);
    canvas.drawLine(const Offset(6, 20), const Offset(6, 25), chromePaint);

    // Cardboard Delivery Parcel Box with tape (Image 1 Style)
    final boxPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFD97706), Color(0xFFB45309)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(3, 4, 18, 16));

    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(3, 4, 18, 16), const Radius.circular(3)),
      boxPaint,
    );
    // Yellow tape
    canvas.drawRect(const Rect.fromLTWH(10, 4, 4, 16), Paint()..color = const Color(0xFFFDE68A));
    // Shipping barcode label
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(5, 11, 4, 6), const Radius.circular(1)),
      Paint()..color = Colors.white,
    );
  }

  // ── LOADED MOVING TRUCK (Cabin + Flatbed + Stacked Boxes + Sofa) ───────────
  void _drawLoadedMovingTruck(Canvas canvas) {
    // Wheels at (18, 36) and (60, 36)
    _drawStaticWheel(canvas, const Offset(18, 36), 9.0);
    _drawStaticWheel(canvas, const Offset(60, 36), 9.0);

    // Metal chassis bed
    final bedPaint = Paint()..color = const Color(0xFF64748B);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(2, 28, 48, 6), const Radius.circular(2)),
      bedPaint,
    );

    // Stacked Cardboard Moving Boxes on flatbed (Warm golden brown cartons)
    final boxPaint1 = Paint()..color = const Color(0xFFD97706);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(4, 14, 20, 14), const Radius.circular(2)),
      boxPaint1,
    );
    canvas.drawLine(const Offset(14, 14), const Offset(14, 28), Paint()..color = const Color(0xFFFDE68A)..strokeWidth = 2);

    final boxPaint2 = Paint()..color = const Color(0xFFB45309);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(16, 2, 18, 16), const Radius.circular(2)),
      boxPaint2,
    );
    canvas.drawLine(const Offset(16, 10), const Offset(34, 10), Paint()..color = const Color(0xFFFDE68A)..strokeWidth = 2);

    // Warm Armchair / Sofa Cushion loaded on top (Image 1 Style)
    final sofaPaint = Paint()..color = const Color(0xFF92400E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(28, 10, 16, 18), const Radius.circular(3)),
      sofaPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(30, 6, 12, 6), const Radius.circular(2)),
      Paint()..color = const Color(0xFF78350F),
    );

    // White Truck Cabin (Modern curved profile)
    final cabPaint = Paint()..color = const Color(0xFFF8FAFC);
    final cabPath = Path()
      ..moveTo(46, 34)
      ..lineTo(74, 34)
      ..quadraticBezierTo(78, 34, 78, 28)
      ..lineTo(76, 14)
      ..quadraticBezierTo(74, 6, 64, 6)
      ..lineTo(48, 6)
      ..close();
    canvas.drawPath(cabPath, cabPaint);
    canvas.drawPath(cabPath, Paint()..color = const Color(0xFFCBD5E1)..style = PaintingStyle.stroke..strokeWidth = 1.3);

    // Blue tinted Windshield
    final glassPaint = Paint()..color = const Color(0xFF93C5FD);
    final glassPath = Path()
      ..moveTo(52, 8)
      ..lineTo(64, 8)
      ..lineTo(72, 19)
      ..lineTo(52, 19)
      ..close();
    canvas.drawPath(glassPath, glassPaint);

    // Headlight & Door Handle
    canvas.drawCircle(const Offset(76, 26), 2.8, Paint()..color = const Color(0xFFFEF08A));
    canvas.drawLine(const Offset(54, 24), const Offset(59, 24), Paint()..color = const Color(0xFF94A3B8)..strokeWidth = 1.5);
  }

  // ── FRIENDLY CARTOON MOVER HELPER (Blue Cap & Overalls, Waving 👋) ─────────
  void _drawMoverHelper(Canvas canvas, Offset pos) {
    // 1. Shadow under feet
    canvas.drawOval(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy + 2), width: 26, height: 6),
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );

    // 2. Shoes
    final shoePaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 9, pos.dy - 4, 7, 5), const Radius.circular(2)), shoePaint);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx + 2, pos.dy - 4, 7, 5), const Radius.circular(2)), shoePaint);

    // 3. Blue Overalls Pants
    final overallPaint = Paint()..color = const Color(0xFF2563EB);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 10, pos.dy - 22, 20, 20), const Radius.circular(4)),
      overallPaint,
    );

    // White T-shirt
    canvas.drawRect(Rect.fromLTWH(pos.dx - 8, pos.dy - 34, 16, 14), Paint()..color = Colors.white);

    // Overalls upper bib & straps
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 7, pos.dy - 28, 14, 12), const Radius.circular(2)),
      overallPaint,
    );
    canvas.drawRect(Rect.fromLTWH(pos.dx - 7, pos.dy - 34, 3.5, 8), overallPaint);
    canvas.drawRect(Rect.fromLTWH(pos.dx + 3.5, pos.dy - 34, 3.5, 8), overallPaint);
    // Silver buttons
    canvas.drawCircle(Offset(pos.dx - 5, pos.dy - 26), 1.2, Paint()..color = const Color(0xFFCBD5E1));
    canvas.drawCircle(Offset(pos.dx + 5, pos.dy - 26), 1.2, Paint()..color = const Color(0xFFCBD5E1));

    // Arms & Hands
    final skinPaint = Paint()..color = const Color(0xFFFFD1A4);

    // Left arm (resting comfortably at side)
    canvas.drawLine(
      Offset(pos.dx - 8, pos.dy - 32),
      Offset(pos.dx - 13, pos.dy - 18),
      Paint()..color = const Color(0xFF2563EB)..strokeWidth = 4.0..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(pos.dx - 13, pos.dy - 16), 2.8, skinPaint);

    // Right arm (waving high! 👋)
    canvas.drawLine(
      Offset(pos.dx + 8, pos.dy - 32),
      Offset(pos.dx + 16, pos.dy - 44),
      Paint()..color = const Color(0xFF2563EB)..strokeWidth = 4.0..strokeCap = StrokeCap.round,
    );
    // Waving hand
    canvas.drawCircle(Offset(pos.dx + 17, pos.dy - 46), 3.5, skinPaint);
    final fingerPaint = Paint()
      ..color = const Color(0xFFFFD1A4)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(pos.dx + 16, pos.dy - 48), Offset(pos.dx + 16, pos.dy - 51), fingerPaint);
    canvas.drawLine(Offset(pos.dx + 19, pos.dy - 48), Offset(pos.dx + 20, pos.dy - 50), fingerPaint);

    // 4. Head & Friendly Face
    canvas.drawCircle(Offset(pos.dx, pos.dy - 42), 9.5, skinPaint);

    // Smiling eyes and smile
    final eyePaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawCircle(Offset(pos.dx - 3.5, pos.dy - 43), 1.4, eyePaint);
    canvas.drawCircle(Offset(pos.dx + 3.5, pos.dy - 43), 1.4, eyePaint);

    // Rosy cheeks
    canvas.drawCircle(Offset(pos.dx - 6, pos.dy - 41), 1.8, Paint()..color = const Color(0xFFFDA4AF).withValues(alpha: 0.6));
    canvas.drawCircle(Offset(pos.dx + 6, pos.dy - 41), 1.8, Paint()..color = const Color(0xFFFDA4AF).withValues(alpha: 0.6));

    // Happy open smile
    canvas.drawArc(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy - 40.5), width: 7.5, height: 5),
      0,
      math.pi,
      false,
      Paint()..color = const Color(0xFF0F172A)..style = PaintingStyle.stroke..strokeWidth = 1.3..strokeCap = StrokeCap.round,
    );

    // 5. Blue Worker Cap with brim (Image 1 Style)
    final capPaint = Paint()..color = const Color(0xFF1D4ED8);
    canvas.drawArc(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy - 46), width: 19, height: 14),
      math.pi,
      math.pi,
      true,
      capPaint,
    );
    // Cap brim tilted forward
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(pos.dx - 2, pos.dy - 47, 13, 3), const Radius.circular(1.5)),
      capPaint,
    );
  }

  // ── PARKED AUTO-RIKSHAW ──────────────────────────────────────────────────
  void _drawParkedRikshaw(Canvas canvas) {
    canvas.drawOval(const Rect.fromLTWH(6, 32, 54, 6), Paint()..color = Colors.black.withValues(alpha: 0.15));
    _drawStaticWheel(canvas, const Offset(16, 32), 8.0);
    _drawStaticWheel(canvas, const Offset(52, 32), 8.0);

    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(8, 20, 48, 11), const Radius.circular(4)), Paint()..color = const Color(0xFF059669));
    final canopyPath = Path()..moveTo(6, 20)..lineTo(10, 6)..quadraticBezierTo(30, 3, 50, 6)..lineTo(54, 20)..close();
    canvas.drawPath(canopyPath, Paint()..color = const Color(0xFFFBBF24));
    canvas.drawRect(const Rect.fromLTWH(42, 8, 8, 12), Paint()..color = const Color(0xFF93C5FD));
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(12, 10, 16, 12), const Radius.circular(2)), Paint()..color = const Color(0xFFD97706));
    canvas.drawCircle(const Offset(54, 23), 2.5, Paint()..color = const Color(0xFFFEF08A));
  }

  void _drawStaticWheel(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFF1E293B));
    canvas.drawCircle(center, radius * 0.65, Paint()..color = const Color(0xFFE2E8F0));
    canvas.drawCircle(center, 1.8, Paint()..color = const Color(0xFF0F172A));
  }

  // ── SCALLOPED EMERALD GREEN BADGE WITH CHECKMARK (✓) ──────────────────────
  // Matches Image 1 Left Card & Image 2 Right Screen
  void _drawScallopedBadge(Canvas canvas, Offset center, double radius) {
    // Soft green outer glow
    canvas.drawCircle(
      center,
      radius + 4,
      Paint()..color = const Color(0xFF10B981).withValues(alpha: 0.28),
    );

    // Scalloped circular badge with 12 rounded petals
    final path = Path();
    const int points = 12;
    for (int i = 0; i < points; i++) {
      final double angle = (i * 2 * math.pi) / points;
      final double nextAngle = ((i + 1) * 2 * math.pi) / points;
      final double midAngle = (angle + nextAngle) / 2;

      final double x1 = center.dx + math.cos(angle) * (radius * 0.90);
      final double y1 = center.dy + math.sin(angle) * (radius * 0.90);
      final double xBump = center.dx + math.cos(midAngle) * (radius * 1.10);
      final double yBump = center.dy + math.sin(midAngle) * (radius * 1.10);
      final double x2 = center.dx + math.cos(nextAngle) * (radius * 0.90);
      final double y2 = center.dy + math.sin(nextAngle) * (radius * 0.90);

      if (i == 0) path.moveTo(x1, y1);
      path.quadraticBezierTo(xBump, yBump, x2, y2);
    }
    path.close();

    // Emerald gradient
    final badgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(path, badgePaint);

    // Crisp white checkmark (✓)
    final checkPath = Path()
      ..moveTo(center.dx - (radius * 0.44), center.dy - (radius * 0.04))
      ..lineTo(center.dx - (radius * 0.12), center.dy + (radius * 0.28))
      ..lineTo(center.dx + (radius * 0.45), center.dy - (radius * 0.32));

    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _VectorPostedHeroPainter oldDelegate) => false;
}
