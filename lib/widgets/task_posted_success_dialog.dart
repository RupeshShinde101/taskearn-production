import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Creative, 3D animated popup celebrating a newly posted task.
/// Includes 3D perspective floating badge, sparkling celebratory aura,
/// task snapshot, and one-tap routing to either My Tasks or Home.
class TaskPostedSuccessDialog extends StatefulWidget {
  final String title;
  final String category;
  final double budget;
  final String? taskId;
  final VoidCallback? onViewTasks;
  final VoidCallback? onGoHome;

  const TaskPostedSuccessDialog({
    super.key,
    required this.title,
    required this.category,
    required this.budget,
    this.taskId,
    this.onViewTasks,
    this.onGoHome,
  });

  static Future<void> show({
    required BuildContext context,
    required String title,
    required String category,
    required double budget,
    String? taskId,
    VoidCallback? onViewTasks,
    VoidCallback? onGoHome,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'TaskPostedSuccessDialog',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 460),
      pageBuilder: (ctx, anim1, anim2) => TaskPostedSuccessDialog(
        title: title,
        category: category,
        budget: budget,
        taskId: taskId,
        onViewTasks: onViewTasks,
        onGoHome: onGoHome,
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final val = curve.value.clamp(0.001, 1.0);
        return Transform.scale(
          scale: val,
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0018)
              ..rotateX(0.22 * (1 - curve.value)),
            alignment: Alignment.center,
            child: Opacity(
              opacity: anim.value.clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  State<TaskPostedSuccessDialog> createState() =>
      _TaskPostedSuccessDialogState();
}

class _TaskPostedSuccessDialogState extends State<TaskPostedSuccessDialog>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _floatController;
  late final AnimationController _sparkleController;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  void _handleViewTasks() {
    Navigator.of(context).pop();
    if (widget.onViewTasks != null) {
      widget.onViewTasks!();
    } else {
      context.go('/my-tasks');
    }
  }

  void _handleGoHome() {
    Navigator.of(context).pop();
    if (widget.onGoHome != null) {
      widget.onGoHome!();
    } else {
      context.go('/home');
    }
  }

  String _categoryEmoji(String cat) {
    final c = cat.toLowerCase();
    if (c.contains('deliver') || c.contains('transport')) return '🛵';
    if (c.contains('mov') || c.contains('shift')) return '📦';
    if (c.contains('clean') || c.contains('house')) return '🧹';
    if (c.contains('cook') || c.contains('food')) return '🍳';
    if (c.contains('repair') || c.contains('fix')) return '🔧';
    if (c.contains('electric')) return '⚡';
    if (c.contains('plumb')) return '🚰';
    if (c.contains('care') || c.contains('baby') || c.contains('pet')) return '❤️';
    if (c.contains('freelanc') || c.contains('design') || c.contains('tech')) return '💻';
    if (c.contains('shop') || c.contains('grocer')) return '🛒';
    return '📋';
  }

  @override
  Widget build(BuildContext context) {
    final catEmoji = _categoryEmoji(widget.category);
    final categoryLabel = widget.category.trim().isNotEmpty
        ? widget.category.trim()
        : 'General Task';
    final taskBudget = widget.budget > 0
        ? '₹${widget.budget.toStringAsFixed(0)}'
        : 'Negotiable';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleViewTasks();
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 390),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.20),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 3D CELEBRATION BADGE WITH FLOATING PERSPECTIVE ─────────
                  SizedBox(
                    height: 110,
                    width: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // Subtle animated radial glow
                        AnimatedBuilder(
                          animation: _floatController,
                          builder: (context, _) {
                            final pulse = 0.85 + (_floatController.value * 0.25);
                            return Transform.scale(
                              scale: pulse,
                              child: Container(
                                width: 96,
                                height: 96,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      const Color(0xFF10B981).withValues(alpha: 0.32),
                                      const Color(0xFF2563EB).withValues(alpha: 0.16),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Orbiting sparkles
                        AnimatedBuilder(
                          animation: _sparkleController,
                          builder: (context, _) {
                            final angle = _sparkleController.value * 2 * math.pi;
                            return Stack(
                              children: [
                                Transform.translate(
                                  offset: Offset(
                                    math.cos(angle) * 48,
                                    math.sin(angle) * 36,
                                  ),
                                  child: const Icon(
                                    Icons.auto_awesome,
                                    color: Color(0xFFF59E0B),
                                    size: 18,
                                  ),
                                ),
                                Transform.translate(
                                  offset: Offset(
                                    math.cos(angle + math.pi) * 44,
                                    math.sin(angle + math.pi) * 38,
                                  ),
                                  child: const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFF10B981),
                                    size: 16,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        // 3D Isometric Floating Badge
                        AnimatedBuilder(
                          animation: _floatController,
                          builder: (context, child) {
                            final fVal = _floatController.value;
                            final tiltY = (fVal - 0.5) * 0.14;
                            final tiltX = (fVal - 0.5) * 0.10;
                            return Transform(
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.0022)
                                ..rotateX(tiltX)
                                ..rotateY(tiltY),
                              alignment: Alignment.center,
                              child: child,
                            );
                          },
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF2563EB), Color(0xFF10B981)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(22),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.25),
                                  blurRadius: 14,
                                  offset: const Offset(-4, 6),
                                ),
                              ],
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.40),
                                width: 1.5,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Top specular sheen
                                Positioned(
                                  top: 4,
                                  left: 6,
                                  right: 6,
                                  height: 22,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.white.withValues(alpha: 0.40),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── CATEGORY & BUDGET PILL ────────────────────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(catEmoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          categoryLabel,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFF93C5FD),
                          ),
                        ),
                        Text(
                          taskBudget,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ── HEADLINE ──────────────────────────────────────────────
                  const Text(
                    'Task Posted! 🎉',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── SUBTITLE ──────────────────────────────────────────────
                  const Text(
                    'Your task is now live! Nearby helpers and matching experts are being notified immediately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── TRUST & MATCHING HIGHLIGHTS ───────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                size: 16,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Instant Proximity Broadcast: Active within 2 km & matching skills',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.shield_outlined,
                                size: 16,
                                color: Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                '100% Escrow Guarantee: Payment releases only on your approval',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── PRIMARY ACTION: VIEW MY TASKS ─────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.32),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _handleViewTasks,
                        icon: const Icon(Icons.list_alt_rounded, size: 20),
                        label: const Text(
                          'View in My Tasks',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── SECONDARY ACTION: BACK TO HOME ────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton.icon(
                      onPressed: _handleGoHome,
                      icon: const Icon(
                        Icons.home_outlined,
                        size: 18,
                        color: Color(0xFF64748B),
                      ),
                      label: const Text(
                        'Back to Home',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
