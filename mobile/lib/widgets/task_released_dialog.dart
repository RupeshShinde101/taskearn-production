import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Modal dialog displayed when a helper successfully releases an accepted task.
/// Clarifies the release status, any penalty deducted, and provides a clear
/// one-tap navigation back to the Home page.
class TaskReleasedDialog extends StatefulWidget {
  final String taskTitle;
  final double releasePenalty;
  final int dailyReleasesUsed;
  final bool isSuspended;
  final String? message;
  final VoidCallback? onHome;

  const TaskReleasedDialog({
    super.key,
    required this.taskTitle,
    this.releasePenalty = 0.0,
    this.dailyReleasesUsed = 0,
    this.isSuspended = false,
    this.message,
    this.onHome,
  });

  static Future<void> show({
    required BuildContext context,
    required String taskTitle,
    double releasePenalty = 0.0,
    int dailyReleasesUsed = 0,
    bool isSuspended = false,
    String? message,
    VoidCallback? onHome,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'TaskReleasedDialog',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (ctx, anim1, anim2) => TaskReleasedDialog(
        taskTitle: taskTitle,
        releasePenalty: releasePenalty,
        dailyReleasesUsed: dailyReleasesUsed,
        isSuspended: isSuspended,
        message: message,
        onHome: onHome,
      ),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curve = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        final val = curve.value.clamp(0.001, 1.0);
        return Transform.scale(
          scale: val,
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0016)
              ..rotateX(0.18 * (1 - curve.value)),
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
  State<TaskReleasedDialog> createState() => _TaskReleasedDialogState();
}

class _TaskReleasedDialogState extends State<TaskReleasedDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  void _handleNavigateHome() {
    Navigator.of(context).pop();
    if (widget.onHome != null) {
      widget.onHome!();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final penalty = widget.releasePenalty;
    final dailyCount = widget.dailyReleasesUsed.clamp(0, 3);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleNavigateHome();
      },
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.18),
                    blurRadius: 36,
                    offset: const Offset(0, 16),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── 3D FLOATING RELEASE BADGE ──────────────────────────────
                  AnimatedBuilder(
                    animation: _floatController,
                    builder: (context, child) {
                      final val = _floatController.value;
                      final tiltX = (val - 0.5) * 0.08;
                      return Transform(
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.002)
                          ..rotateX(tiltX),
                        alignment: Alignment.center,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.assignment_return_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── TITLE ─────────────────────────────────────────────────
                  const Text(
                    'Task Released',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── DESCRIPTION ───────────────────────────────────────────
                  Text(
                    widget.message ??
                        'You have released this task. It has been made available again for other helpers.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── TASK SUMMARY CARD ─────────────────────────────────────
                  if (widget.taskTitle.trim().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.task_alt_rounded,
                            size: 18,
                            color: Color(0xFF475569),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.taskTitle.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── PENALTY NOTICE (IF ANY) ───────────────────────────────
                  if (penalty > 0) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 20,
                            color: Color(0xFFD97706),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '₹${penalty.toStringAsFixed(2)} release penalty was deducted from your wallet.',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF92400E),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── DAILY RELEASES LIMIT PILL ─────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.speed_rounded,
                          size: 18,
                          color: Color(0xFF64748B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Daily releases used: $dailyCount / 3',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF475569),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(3, (index) {
                            final used = index < dailyCount;
                            return Container(
                              margin: const EdgeInsets.only(left: 4),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: used
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFFCBD5E1),
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),

                  // ── SUSPENSION WARNING (IF EXCEEDED) ──────────────────────
                  if (widget.isSuspended) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.block_rounded,
                            size: 18,
                            color: Color(0xFFDC2626),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Account suspended for 48 hours for exceeding 3 daily releases.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF991B1B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 22),

                  // ── PRIMARY ACTION: GO TO HOME ────────────────────────────
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
                            color: const Color(0xFF2563EB).withValues(alpha: 0.30),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _handleNavigateHome,
                        icon: const Icon(Icons.home_rounded, size: 20),
                        label: const Text(
                          'Go to Home',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
