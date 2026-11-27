import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/task.dart';

/// Animated task posting popup dialog with category-specific animations:
/// - Repair: Rotating gears, swinging wrench & screwdriver, golden spark stars.
/// - Home: Cozy home with glowing windows, floating cleaning bubbles & twinkles.
/// - Care Services: Pulsating heartbeat, soothing radiant compassion ripples & mini hearts.
/// - Professional: Animated laptop with rising dynamic bar-chart graph & network nodes.
/// - Other: Floating isometric 3D blocks with beacon signal radar & confetti.
/// - Shopping: Shopping cart & bag with sparkle trails.
class CategoryTaskPostingDialog extends StatefulWidget {
  final TaskCategoryGroup parentGroup;
  final TaskCategory? subCategory;
  final String category;
  final double budget;
  final String? address;
  final String? customTitle;
  final Future<bool> Function() onPostTask;
  final VoidCallback? onTrackInMyTasks;
  final VoidCallback? onBackToHome;

  const CategoryTaskPostingDialog({
    super.key,
    required this.parentGroup,
    this.subCategory,
    required this.category,
    required this.budget,
    this.address,
    this.customTitle,
    required this.onPostTask,
    this.onTrackInMyTasks,
    this.onBackToHome,
  });

  static Future<bool?> show({
    required BuildContext context,
    required TaskCategoryGroup parentGroup,
    TaskCategory? subCategory,
    required String category,
    required double budget,
    String? address,
    String? customTitle,
    required Future<bool> Function() onPostTask,
    VoidCallback? onTrackInMyTasks,
    VoidCallback? onBackToHome,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => CategoryTaskPostingDialog(
        parentGroup: parentGroup,
        subCategory: subCategory,
        category: category,
        budget: budget,
        address: address,
        customTitle: customTitle,
        onPostTask: onPostTask,
        onTrackInMyTasks: onTrackInMyTasks,
        onBackToHome: onBackToHome,
      ),
    );
  }

  @override
  State<CategoryTaskPostingDialog> createState() => _CategoryTaskPostingDialogState();
}

class _CategoryTaskPostingDialogState extends State<CategoryTaskPostingDialog>
    with TickerProviderStateMixin {
  late AnimationController _loopController;
  late AnimationController _progressController;
  late AnimationController _morphController;
  late AnimationController _idleController;

  bool _isPosted = false;
  bool _apiCompleted = false;
  bool _postSuccess = false;

  String get _groupLabel => widget.parentGroup.label.toLowerCase();

  bool get _isRepair => _groupLabel.contains('repair');
  bool get _isHome => _groupLabel.contains('home');
  bool get _isCare => _groupLabel.contains('care');
  bool get _isProfessional => _groupLabel.contains('professional');
  bool get _isShopping => _groupLabel.contains('shopping') || _groupLabel.contains('grocery');

  Color get _themePrimaryColor {
    if (_isRepair) return const Color(0xFF0284C7);
    if (_isHome) return const Color(0xFF059669);
    if (_isCare) return const Color(0xFFDB2777);
    if (_isProfessional) return const Color(0xFF1D4ED8);
    if (_isShopping) return const Color(0xFF7C3AED);
    return const Color(0xFF4338CA); // Other
  }

  Color get _themeAccentColor {
    if (_isRepair) return const Color(0xFF2563EB);
    if (_isHome) return const Color(0xFF10B981);
    if (_isCare) return const Color(0xFFEC4899);
    if (_isProfessional) return const Color(0xFF3B82F6);
    if (_isShopping) return const Color(0xFF8B5CF6);
    return const Color(0xFF6366F1); // Other
  }

  String get _infoPillText {
    final catLabel = widget.subCategory?.label ?? widget.parentGroup.label;
    final budgetStr = '₹${widget.budget.toInt()}';
    if (widget.address != null && widget.address!.trim().isNotEmpty) {
      final shortAddr = widget.address!.split(',').first.trim();
      return '$catLabel • $shortAddr • $budgetStr';
    }
    return '$catLabel • $budgetStr';
  }

  String _getStatusText(double progress) {
    if (_isRepair) {
      if (progress < 0.35) return 'Searching verified technicians nearby...';
      if (progress < 0.70) return 'Matching tool requirements & skills...';
      if (progress < 0.90) return 'Preparing repair request...';
      return 'Ready — notifying nearby technicians!';
    } else if (_isHome) {
      if (progress < 0.35) return 'Finding trusted home helpers nearby...';
      if (progress < 0.70) return 'Checking availability in your area...';
      if (progress < 0.90) return 'Preparing household task details...';
      return 'Ready — helpers are reviewing your task!';
    } else if (_isCare) {
      if (progress < 0.35) return 'Connecting with compassionate caregivers...';
      if (progress < 0.70) return 'Checking specialized care preferences...';
      if (progress < 0.90) return 'Locating available caregivers nearby...';
      return 'Ready — notifying local caregivers!';
    } else if (_isProfessional) {
      if (progress < 0.35) return 'Matching verified professional experts...';
      if (progress < 0.70) return 'Reviewing task scope and skills...';
      if (progress < 0.90) return 'Broadcasting to qualified professionals...';
      return 'Ready — experts are preparing proposals!';
    } else if (_isShopping) {
      if (progress < 0.35) return 'Finding personal shoppers nearby...';
      if (progress < 0.70) return 'Checking store routes and availability...';
      if (progress < 0.90) return 'Preparing shopping checklist...';
      return 'Ready — notifying local shoppers!';
    } else {
      if (progress < 0.35) return 'Broadcasting custom task to helpers...';
      if (progress < 0.70) return 'Matching available local assistants...';
      if (progress < 0.90) return 'Finalizing task request...';
      return 'Ready — notifying local helpers!';
    }
  }

  @override
  void initState() {
    super.initState();

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

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
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _isPosted,
      child: Center(
        child: SingleChildScrollView(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 320,
              margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 40,
                    offset: const Offset(0, 16),
                  ),
                  BoxShadow(
                    color: _themePrimaryColor.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 380),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeInQuad,
                child: _isPosted ? _buildStage2Posted() : _buildStage1Posting(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Stage 1: Posting in progress ──────────────────────────────
  Widget _buildStage1Posting() {
    return AnimatedBuilder(
      animation: Listenable.merge([_loopController, _progressController]),
      builder: (context, _) {
        final progress = _progressController.value;
        final loopT = _loopController.value;
        final percentText = '${(progress * 100).toInt()}%';

        return Column(
          key: const ValueKey('stage1_posting'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row: Headline on left, Animated % on right
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Posting your task...',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: _themePrimaryColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    percentText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _themePrimaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Animated Visual Canvas according to Category
            Container(
              height: 155,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _themePrimaryColor.withValues(alpha: 0.06),
                    _themePrimaryColor.withValues(alpha: 0.14),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _themePrimaryColor.withValues(alpha: 0.18),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(19),
                child: _buildCategoryVectorStage1(loopT),
              ),
            ),
            const SizedBox(height: 16),

            // Gradient Progress Bar
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 7,
                child: Stack(
                  children: [
                    Container(color: const Color(0xFFE2E8F0)),
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.04, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_themePrimaryColor, _themeAccentColor],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Status Caption
            Text(
              _getStatusText(progress),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                letterSpacing: -0.1,
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Stage 2: Task Posted Celebration ─────────────────────────
  Widget _buildStage2Posted() {
    final parentName = widget.parentGroup.label;
    final headline = parentName == 'Other' ? 'Task Posted!' : '$parentName Task Posted!';

    return AnimatedBuilder(
      animation: _idleController,
      builder: (context, _) {
        final idleT = _idleController.value;

        return Column(
          key: const ValueKey('stage2_posted'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top verified icon badge with celebratory heading
            Center(
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_themePrimaryColor, _themeAccentColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _themePrimaryColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
              ),
            ),
            const SizedBox(height: 12),

            // Headline
            Text(
              headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),

            // Subtitle
            const Text(
              'Finding the best helpers nearby...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 14),

            // Category-Specific Vector Stage 2 Illustration
            Container(
              height: 135,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    _themePrimaryColor.withValues(alpha: 0.05),
                    _themePrimaryColor.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _themePrimaryColor.withValues(alpha: 0.16),
                  width: 1.2,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: _buildCategoryVectorStage2(idleT),
              ),
            ),
            const SizedBox(height: 14),

            // Task detail pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                _infoPillText,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Button: Track in My Tasks
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop(true);
                  widget.onTrackInMyTasks?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _themePrimaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Track in My Tasks',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Custom Category Vector Painters (Stage 1 & Stage 2)
  // ─────────────────────────────────────────────────────────────

  Widget _buildCategoryVectorStage1(double t) {
    if (_isRepair) {
      return CustomPaint(
        painter: _RepairStage1Painter(t: t, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isHome) {
      return CustomPaint(
        painter: _HomeStage1Painter(t: t, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isCare) {
      return CustomPaint(
        painter: _CareStage1Painter(t: t, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isProfessional) {
      return CustomPaint(
        painter: _ProfessionalStage1Painter(t: t, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isShopping) {
      return CustomPaint(
        painter: _ShoppingStage1Painter(t: t, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else {
      // Other (Isometric Cubes)
      return CustomPaint(
        painter: _OtherStage1Painter(t: t, color: _themePrimaryColor),
        size: Size.infinite,
      );
    }
  }

  Widget _buildCategoryVectorStage2(double idleT) {
    if (_isRepair) {
      return CustomPaint(
        painter: _RepairStage2Painter(idleT: idleT, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isHome) {
      return CustomPaint(
        painter: _HomeStage2Painter(idleT: idleT, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isCare) {
      return CustomPaint(
        painter: _CareStage2Painter(idleT: idleT, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isProfessional) {
      return CustomPaint(
        painter: _ProfessionalStage2Painter(idleT: idleT, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else if (_isShopping) {
      return CustomPaint(
        painter: _ShoppingStage2Painter(idleT: idleT, color: _themePrimaryColor),
        size: Size.infinite,
      );
    } else {
      // Other
      return CustomPaint(
        painter: _OtherStage2Painter(idleT: idleT, color: _themePrimaryColor),
        size: Size.infinite,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────
// 1. REPAIR PAINTERS
// ─────────────────────────────────────────────────────────────
class _RepairStage1Painter extends CustomPainter {
  final double t;
  final Color color;
  _RepairStage1Painter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 1. Concentric radar ripples
    final radarPaint = Paint()
      ..color = color.withValues(alpha: 0.12 * (1.0 - (t % 1.0)))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 30 + (45 * (t % 1.0)), radarPaint);

    // 2. Large rotating Gear (Blue)
    final gear1Center = Offset(center.dx - 28, center.dy + 8);
    _drawGear(canvas, gear1Center, radius: 30, teeth: 8, angle: t * 2 * math.pi, gearColor: color);

    // 3. Small interlocking Gear (Amber/Steel)
    final gear2Center = Offset(center.dx + 28, center.dy - 12);
    _drawGear(canvas, gear2Center, radius: 22, teeth: 6, angle: -t * 2 * math.pi * 1.33 + 0.3, gearColor: const Color(0xFFF59E0B));

    // 4. Swinging Wrench Tool in foreground
    final wrenchAngle = math.sin(t * 2 * math.pi) * 0.45;
    canvas.save();
    canvas.translate(center.dx + 4, center.dy + 4);
    canvas.rotate(wrenchAngle);

    final wrenchBody = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(-28, -28), const Offset(20, 20), wrenchBody);

    // Wrench metallic head
    final headPaint = Paint()..color = const Color(0xFF64748B);
    canvas.drawCircle(const Offset(-28, -28), 12, headPaint);
    final cutoutPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromCenter(center: const Offset(-28, -28), width: 7, height: 16), cutoutPaint);

    canvas.restore();

    // 5. Golden spark particles
    for (int i = 0; i < 4; i++) {
      final pAngle = (i * math.pi / 2) + (t * 2 * math.pi);
      final pDist = 38 + math.sin((t + i) * math.pi) * 14;
      final pPos = Offset(center.dx + math.cos(pAngle) * pDist, center.dy + math.sin(pAngle) * pDist);
      final sparkPaint = Paint()..color = const Color(0xFFFBBF24);
      canvas.drawCircle(pPos, 2.5, sparkPaint);
    }
  }

  void _drawGear(Canvas canvas, Offset c, {required double radius, required int teeth, required double angle, required Color gearColor}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);

    final p = Paint()..color = gearColor;
    canvas.drawCircle(Offset.zero, radius, p);

    // Teeth
    for (int i = 0; i < teeth; i++) {
      final th = (i * 2 * math.pi) / teeth;
      canvas.save();
      canvas.rotate(th);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(0, -radius - 4), width: 8, height: 10), const Radius.circular(2)),
        p,
      );
      canvas.restore();
    }

    // Inner Hole
    final holeP = Paint()..color = Colors.white;
    canvas.drawCircle(Offset.zero, radius * 0.38, holeP);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RepairStage1Painter old) => old.t != t;
}

class _RepairStage2Painter extends CustomPainter {
  final double idleT;
  final Color color;
  _RepairStage2Painter({required this.idleT, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final bobY = math.sin(idleT * 2 * math.pi) * 3;

    // Toolbox base
    final boxRect = Rect.fromCenter(center: Offset(center.dx, center.dy + bobY), width: 88, height: 50);
    final boxPaint = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(10)), boxPaint);

    // Toolbox lid / handle
    final lidPaint = Paint()..color = color.withValues(alpha: 0.85);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy - 24 + bobY), width: 92, height: 12), const Radius.circular(4)), lidPaint);

    final handlePaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCenter(center: Offset(center.dx, center.dy - 30 + bobY), width: 34, height: 24), math.pi, math.pi, false, handlePaint);

    // Screwdriver sticking out
    final tool1 = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - 22, center.dy - 22 + bobY), Offset(center.dx - 36, center.dy - 46 + bobY), tool1);

    // Wrench sticking out
    final tool2 = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx + 20, center.dy - 22 + bobY), Offset(center.dx + 34, center.dy - 48 + bobY), tool2);

    // Floating emerald checkmark
    final checkCenter = Offset(center.dx + 36, center.dy - 10 + bobY);
    final checkBg = Paint()..color = const Color(0xFF10B981);
    canvas.drawCircle(checkCenter, 15, checkBg);

    final checkPath = Path()
      ..moveTo(checkCenter.dx - 6, checkCenter.dy)
      ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
      ..lineTo(checkCenter.dx + 6, checkCenter.dy - 4);
    final checkP = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(checkPath, checkP);
  }

  @override
  bool shouldRepaint(covariant _RepairStage2Painter old) => old.idleT != idleT;
}

// ─────────────────────────────────────────────────────────────
// 2. HOME PAINTERS
// ─────────────────────────────────────────────────────────────
class _HomeStage1Painter extends CustomPainter {
  final double t;
  final Color color;
  _HomeStage1Painter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);

    // 1. Gentle green aura
    final auraP = Paint()
      ..color = color.withValues(alpha: 0.12 * (1.0 - (t % 1.0)))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 35 + (40 * (t % 1.0)), auraP);

    // 2. House Base
    final houseRect = Rect.fromCenter(center: Offset(center.dx, center.dy + 8), width: 68, height: 50);
    final wallPaint = Paint()..color = const Color(0xFFFEF3C7);
    canvas.drawRRect(RRect.fromRectAndRadius(houseRect, const Radius.circular(6)), wallPaint);

    // Door
    final doorRect = Rect.fromCenter(center: Offset(center.dx, center.dy + 19), width: 18, height: 28);
    final doorPaint = Paint()..color = const Color(0xFFB45309);
    canvas.drawRRect(RRect.fromRectAndRadius(doorRect, const Radius.circular(4)), doorPaint);

    // Roof (Green/Teal Triangle)
    final roofPath = Path()
      ..moveTo(center.dx - 42, center.dy - 17)
      ..lineTo(center.dx, center.dy - 50)
      ..lineTo(center.dx + 42, center.dy - 17)
      ..close();
    final roofPaint = Paint()..color = color;
    canvas.drawPath(roofPath, roofPaint);

    // Glowing window with pulse
    final winGlow = 0.5 + 0.5 * math.sin(t * 2 * math.pi);
    final winPaint = Paint()..color = Color.lerp(const Color(0xFFFDE68A), const Color(0xFFFBBF24), winGlow)!;
    canvas.drawCircle(Offset(center.dx, center.dy - 34), 6, winPaint);

    // Floating cleaning bubbles
    for (int i = 0; i < 5; i++) {
      final bubbleT = (t + (i * 0.2)) % 1.0;
      final bx = center.dx - 40 + (i * 20) + math.sin(bubbleT * 2 * math.pi) * 8;
      final by = center.dy + 15 - (bubbleT * 70);
      final bubblePaint = Paint()
        ..color = const Color(0xFF6EE7B7).withValues(alpha: (1.0 - bubbleT) * 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8;
      canvas.drawCircle(Offset(bx, by), 4 + (i % 3) * 2.5, bubblePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HomeStage1Painter old) => old.t != t;
}

class _HomeStage2Painter extends CustomPainter {
  final double idleT;
  final Color color;
  _HomeStage2Painter({required this.idleT, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final bobY = math.sin(idleT * 2 * math.pi) * 3;

    // House Base
    final houseRect = Rect.fromCenter(center: Offset(center.dx, center.dy + 8 + bobY), width: 72, height: 52);
    final wallPaint = Paint()..color = const Color(0xFFFFFBEB);
    canvas.drawRRect(RRect.fromRectAndRadius(houseRect, const Radius.circular(8)), wallPaint);

    // Roof
    final roofPath = Path()
      ..moveTo(center.dx - 46, center.dy - 18 + bobY)
      ..lineTo(center.dx, center.dy - 54 + bobY)
      ..lineTo(center.dx + 46, center.dy - 18 + bobY)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = color);

    // Warm door
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy + 19 + bobY), width: 20, height: 30), const Radius.circular(4)),
      Paint()..color = const Color(0xFFD97706),
    );

    // Floating check badge
    final checkCenter = Offset(center.dx + 38, center.dy - 14 + bobY);
    canvas.drawCircle(checkCenter, 16, Paint()..color = const Color(0xFF10B981));
    final checkPath = Path()
      ..moveTo(checkCenter.dx - 6, checkCenter.dy)
      ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
      ..lineTo(checkCenter.dx + 6, checkCenter.dy - 4);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeStage2Painter old) => old.idleT != idleT;
}

// ─────────────────────────────────────────────────────────────
// 3. CARE SERVICES PAINTERS
// ─────────────────────────────────────────────────────────────
class _CareStage1Painter extends CustomPainter {
  final double t;
  final Color color;
  _CareStage1Painter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Rhythmic heart beat pulse (lub-dub)
    final beatT = (t * 2) % 1.0;
    final scale = 1.0 + (0.16 * math.sin(beatT * math.pi));

    // Compassion ripple rings
    final rippleP = Paint()
      ..color = color.withValues(alpha: 0.16 * (1.0 - (t % 1.0)))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 32 + (46 * (t % 1.0)), rippleP);

    // Heart drawing
    canvas.save();
    canvas.translate(center.dx, center.dy + 4);
    canvas.scale(scale);

    final heartPath = Path();
    heartPath.moveTo(0, 10);
    heartPath.cubicTo(-26, -24, -42, 6, 0, 36);
    heartPath.moveTo(0, 10);
    heartPath.cubicTo(26, -24, 42, 6, 0, 36);
    heartPath.close();

    final heartP = Paint()..color = color;
    canvas.drawPath(heartPath, heartP);

    // Medical Cross inside heart
    final crossP = Paint()..color = Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 14), width: 8, height: 22), const Radius.circular(2)), crossP);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 14), width: 22, height: 8), const Radius.circular(2)), crossP);

    canvas.restore();

    // Floating mini hearts
    for (int i = 0; i < 4; i++) {
      final ht = (t + (i * 0.25)) % 1.0;
      final hx = center.dx - 36 + (i * 24);
      final hy = center.dy + 20 - (ht * 60);
      final miniHP = Paint()..color = const Color(0xFFF472B6).withValues(alpha: (1.0 - ht) * 0.8);
      canvas.drawCircle(Offset(hx, hy), 3.5, miniHP);
    }
  }

  @override
  bool shouldRepaint(covariant _CareStage1Painter old) => old.t != t;
}

class _CareStage2Painter extends CustomPainter {
  final double idleT;
  final Color color;
  _CareStage2Painter({required this.idleT, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 4);
    final bobY = math.sin(idleT * 2 * math.pi) * 3;

    // Glowing Heart
    canvas.save();
    canvas.translate(center.dx, center.dy + bobY);

    final heartPath = Path();
    heartPath.moveTo(0, 8);
    heartPath.cubicTo(-28, -26, -46, 6, 0, 38);
    heartPath.moveTo(0, 8);
    heartPath.cubicTo(28, -26, 46, 6, 0, 38);
    heartPath.close();

    canvas.drawPath(heartPath, Paint()..color = color);

    // White Cross
    final crossP = Paint()..color = Colors.white;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 15), width: 9, height: 24), const Radius.circular(3)), crossP);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 15), width: 24, height: 9), const Radius.circular(3)), crossP);

    canvas.restore();

    // Floating emerald check badge
    final checkCenter = Offset(center.dx + 38, center.dy - 12 + bobY);
    canvas.drawCircle(checkCenter, 16, Paint()..color = const Color(0xFF10B981));
    final checkPath = Path()
      ..moveTo(checkCenter.dx - 6, checkCenter.dy)
      ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
      ..lineTo(checkCenter.dx + 6, checkCenter.dy - 4);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CareStage2Painter old) => old.idleT != idleT;
}

// ─────────────────────────────────────────────────────────────
// 4. PROFESSIONAL PAINTERS
// ─────────────────────────────────────────────────────────────
class _ProfessionalStage1Painter extends CustomPainter {
  final double t;
  final Color color;
  _ProfessionalStage1Painter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);

    // Laptop Base
    final baseRect = Rect.fromCenter(center: Offset(center.dx, center.dy + 26), width: 104, height: 8);
    canvas.drawRRect(RRect.fromRectAndRadius(baseRect, const Radius.circular(4)), Paint()..color = const Color(0xFF64748B));

    // Laptop Screen
    final screenRect = Rect.fromCenter(center: Offset(center.dx, center.dy - 10), width: 84, height: 56);
    canvas.drawRRect(RRect.fromRectAndRadius(screenRect, const Radius.circular(6)), Paint()..color = const Color(0xFF0F172A));

    // Screen Bezel Inner Display
    final displayRect = Rect.fromCenter(center: Offset(center.dx, center.dy - 10), width: 76, height: 48);
    canvas.drawRect(displayRect, Paint()..color = const Color(0xFF1E293B));

    // Dynamic Rising Bar Chart on Screen
    for (int i = 0; i < 4; i++) {
      final barT = (t + (i * 0.22)) % 1.0;
      final barHeight = 10 + (22 * math.sin(barT * math.pi));
      final barX = center.dx - 26 + (i * 17);
      final barY = (center.dy + 10) - (barHeight / 2);

      final barColor = i == 3 ? const Color(0xFF38BDF8) : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(barX, barY), width: 10, height: barHeight), const Radius.circular(2)),
        Paint()..color = barColor,
      );
    }

    // Network Signal Nodes
    for (int i = 0; i < 4; i++) {
      final nAngle = (i * math.pi / 2) + (t * 2 * math.pi);
      const nDist = 45.0;
      final nx = center.dx + math.cos(nAngle) * nDist;
      final ny = center.dy - 10 + math.sin(nAngle) * (nDist * 0.6);

      canvas.drawCircle(Offset(nx, ny), 3, Paint()..color = const Color(0xFF38BDF8));
      canvas.drawLine(Offset(center.dx, center.dy - 10), Offset(nx, ny), Paint()..color = const Color(0xFF38BDF8).withValues(alpha: 0.25)..strokeWidth = 1.2);
    }
  }

  @override
  bool shouldRepaint(covariant _ProfessionalStage1Painter old) => old.t != t;
}

class _ProfessionalStage2Painter extends CustomPainter {
  final double idleT;
  final Color color;
  _ProfessionalStage2Painter({required this.idleT, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 10);
    final bobY = math.sin(idleT * 2 * math.pi) * 3;

    // Laptop Base
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy + 26 + bobY), width: 108, height: 9), const Radius.circular(4)),
      Paint()..color = const Color(0xFF64748B),
    );

    // Screen
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(center.dx, center.dy - 10 + bobY), width: 88, height: 60), const Radius.circular(6)),
      Paint()..color = const Color(0xFF0F172A),
    );

    // Completed Chart
    for (int i = 0; i < 4; i++) {
      final h = 12.0 + (i * 9);
      final bx = center.dx - 28 + (i * 18);
      final by = (center.dy + 12 + bobY) - (h / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx, by), width: 10, height: h), const Radius.circular(2)),
        Paint()..color = i == 3 ? const Color(0xFF38BDF8) : color,
      );
    }

    // Upward arrow line
    final arrowP = Paint()
      ..color = const Color(0xFFFBBF24)
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - 32, center.dy + 8 + bobY), Offset(center.dx + 30, center.dy - 22 + bobY), arrowP);

    // Check badge
    final checkCenter = Offset(center.dx + 42, center.dy - 24 + bobY);
    canvas.drawCircle(checkCenter, 16, Paint()..color = const Color(0xFF10B981));
    final checkPath = Path()
      ..moveTo(checkCenter.dx - 6, checkCenter.dy)
      ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
      ..lineTo(checkCenter.dx + 6, checkCenter.dy - 4);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ProfessionalStage2Painter old) => old.idleT != idleT;
}

// ─────────────────────────────────────────────────────────────
// 5. OTHER (3D Isometric Cubes) PAINTERS
// ─────────────────────────────────────────────────────────────
class _OtherStage1Painter extends CustomPainter {
  final double t;
  final Color color;
  _OtherStage1Painter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Beacon signal pulse rings
    final beaconP = Paint()
      ..color = color.withValues(alpha: 0.14 * (1.0 - (t % 1.0)))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, 30 + (45 * (t % 1.0)), beaconP);

    // 3 Floating isometric cubes
    final bob1 = math.sin(t * 2 * math.pi) * 6;
    final bob2 = math.sin((t + 0.33) * 2 * math.pi) * 6;
    final bob3 = math.sin((t + 0.66) * 2 * math.pi) * 6;

    // Cube 1 (Center Top)
    _drawIsoCube(canvas, Offset(center.dx, center.dy - 20 + bob1), size: 26, topColor: const Color(0xFF93C5FD), leftColor: const Color(0xFF3B82F6), rightColor: const Color(0xFF1D4ED8));

    // Cube 2 (Bottom Left)
    _drawIsoCube(canvas, Offset(center.dx - 28, center.dy + 16 + bob2), size: 26, topColor: const Color(0xFFA78BFA), leftColor: const Color(0xFF7C3AED), rightColor: const Color(0xFF5B21B6));

    // Cube 3 (Bottom Right)
    _drawIsoCube(canvas, Offset(center.dx + 28, center.dy + 16 + bob3), size: 26, topColor: const Color(0xFF67E8F9), leftColor: const Color(0xFF06B6D4), rightColor: const Color(0xFF0891B2));
  }

  void _drawIsoCube(Canvas canvas, Offset c, {required double size, required Color topColor, required Color leftColor, required Color rightColor}) {
    final halfW = size * 0.866;
    final halfH = size * 0.5;

    // Top face
    final topP = Path()
      ..moveTo(c.dx, c.dy - size)
      ..lineTo(c.dx + halfW, c.dy - halfH)
      ..lineTo(c.dx, c.dy)
      ..lineTo(c.dx - halfW, c.dy - halfH)
      ..close();
    canvas.drawPath(topP, Paint()..color = topColor);

    // Left face
    final leftP = Path()
      ..moveTo(c.dx - halfW, c.dy - halfH)
      ..lineTo(c.dx, c.dy)
      ..lineTo(c.dx, c.dy + size)
      ..lineTo(c.dx - halfW, c.dy + halfH)
      ..close();
    canvas.drawPath(leftP, Paint()..color = leftColor);

    // Right face
    final rightP = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx + halfW, c.dy - halfH)
      ..lineTo(c.dx + halfW, c.dy + halfH)
      ..lineTo(c.dx, c.dy + size)
      ..close();
    canvas.drawPath(rightP, Paint()..color = rightColor);
  }

  @override
  bool shouldRepaint(covariant _OtherStage1Painter old) => old.t != t;
}

class _OtherStage2Painter extends CustomPainter {
  final double idleT;
  final Color color;
  _OtherStage2Painter({required this.idleT, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 4);
    final bobY = math.sin(idleT * 2 * math.pi) * 3;

    // Perfectly stacked cubes
    _drawIsoCube(canvas, Offset(center.dx, center.dy - 18 + bobY), size: 28, topColor: const Color(0xFF93C5FD), leftColor: const Color(0xFF3B82F6), rightColor: const Color(0xFF1D4ED8));
    _drawIsoCube(canvas, Offset(center.dx - 26, center.dy + 14 + bobY), size: 28, topColor: const Color(0xFFA78BFA), leftColor: const Color(0xFF7C3AED), rightColor: const Color(0xFF5B21B6));
    _drawIsoCube(canvas, Offset(center.dx + 26, center.dy + 14 + bobY), size: 28, topColor: const Color(0xFF67E8F9), leftColor: const Color(0xFF06B6D4), rightColor: const Color(0xFF0891B2));

    // Check badge
    final checkCenter = Offset(center.dx + 42, center.dy - 18 + bobY);
    canvas.drawCircle(checkCenter, 16, Paint()..color = const Color(0xFF10B981));
    final checkPath = Path()
      ..moveTo(checkCenter.dx - 6, checkCenter.dy)
      ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
      ..lineTo(checkCenter.dx + 6, checkCenter.dy - 4);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawIsoCube(Canvas canvas, Offset c, {required double size, required Color topColor, required Color leftColor, required Color rightColor}) {
    final halfW = size * 0.866;
    final halfH = size * 0.5;

    final topP = Path()
      ..moveTo(c.dx, c.dy - size)
      ..lineTo(c.dx + halfW, c.dy - halfH)
      ..lineTo(c.dx, c.dy)
      ..lineTo(c.dx - halfW, c.dy - halfH)
      ..close();
    canvas.drawPath(topP, Paint()..color = topColor);

    final leftP = Path()
      ..moveTo(c.dx - halfW, c.dy - halfH)
      ..lineTo(c.dx, c.dy)
      ..lineTo(c.dx, c.dy + size)
      ..lineTo(c.dx - halfW, c.dy + halfH)
      ..close();
    canvas.drawPath(leftP, Paint()..color = leftColor);

    final rightP = Path()
      ..moveTo(c.dx, c.dy)
      ..lineTo(c.dx + halfW, c.dy - halfH)
      ..lineTo(c.dx + halfW, c.dy + halfH)
      ..lineTo(c.dx, c.dy + size)
      ..close();
    canvas.drawPath(rightP, Paint()..color = rightColor);
  }

  @override
  bool shouldRepaint(covariant _OtherStage2Painter old) => old.idleT != idleT;
}

// ─────────────────────────────────────────────────────────────
// 6. SHOPPING PAINTERS
// ─────────────────────────────────────────────────────────────
class _ShoppingStage1Painter extends CustomPainter {
  final double t;
  final Color color;
  _ShoppingStage1Painter({required this.t, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final bagRect = Rect.fromCenter(center: Offset(center.dx, center.dy + 4), width: 62, height: 60);
    canvas.drawRRect(RRect.fromRectAndRadius(bagRect, const Radius.circular(8)), Paint()..color = color);

    // Bag handles
    final handleP = Paint()
      ..color = const Color(0xFF5B21B6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCenter(center: Offset(center.dx, center.dy - 22), width: 28, height: 26), math.pi, math.pi, false, handleP);

    // Sparkles
    for (int i = 0; i < 4; i++) {
      final st = (t + (i * 0.25)) % 1.0;
      final sx = center.dx - 34 + (i * 22);
      final sy = center.dy + 12 - (st * 50);
      canvas.drawCircle(Offset(sx, sy), 3, Paint()..color = const Color(0xFFFBBF24));
    }
  }

  @override
  bool shouldRepaint(covariant _ShoppingStage1Painter old) => old.t != t;
}

class _ShoppingStage2Painter extends CustomPainter {
  final double idleT;
  final Color color;
  _ShoppingStage2Painter({required this.idleT, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final bobY = math.sin(idleT * 2 * math.pi) * 3;

    final bagRect = Rect.fromCenter(center: Offset(center.dx, center.dy + 4 + bobY), width: 64, height: 62);
    canvas.drawRRect(RRect.fromRectAndRadius(bagRect, const Radius.circular(8)), Paint()..color = color);

    final handleP = Paint()
      ..color = const Color(0xFF5B21B6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCenter(center: Offset(center.dx, center.dy - 24 + bobY), width: 30, height: 28), math.pi, math.pi, false, handleP);

    final checkCenter = Offset(center.dx + 34, center.dy - 12 + bobY);
    canvas.drawCircle(checkCenter, 16, Paint()..color = const Color(0xFF10B981));
    final checkPath = Path()
      ..moveTo(checkCenter.dx - 6, checkCenter.dy)
      ..lineTo(checkCenter.dx - 1, checkCenter.dy + 5)
      ..lineTo(checkCenter.dx + 6, checkCenter.dy - 4);
    canvas.drawPath(
      checkPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ShoppingStage2Painter old) => old.idleT != idleT;
}
