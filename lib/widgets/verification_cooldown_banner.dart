import 'dart:async';
import 'package:flutter/material.dart';

/// Reusable banner widget for KYC, Onboarding, and Vehicle Verification.
///
/// Features:
/// 1. Shows "Verification complete in 24 hrs" when pending review.
/// 2. If rejected, displays the rejection reason, exact rejection timestamp,
///    and an active 24-hour countdown showing the remaining time to reapply.
/// 3. Updates dynamically while the user is actively checking the screen.
/// 4. When 24 hours have elapsed, shows an "Eligible to Reapply" badge and notification.
class VerificationCooldownBanner extends StatefulWidget {
  final String verificationTitle;
  final String status; // 'pending', 'rejected', 'verified', 'none'
  final String? rejectionReason;
  final DateTime? rejectedAt;
  final VoidCallback? onCooldownEnded;

  const VerificationCooldownBanner({
    super.key,
    required this.verificationTitle,
    required this.status,
    this.rejectionReason,
    this.rejectedAt,
    this.onCooldownEnded,
  });

  @override
  State<VerificationCooldownBanner> createState() => _VerificationCooldownBannerState();
}

class _VerificationCooldownBannerState extends State<VerificationCooldownBanner> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _cooldownActive = false;

  @override
  void initState() {
    super.initState();
    _calculateRemaining();
    if (_cooldownActive) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        _calculateRemaining();
      });
    }
  }

  @override
  void didUpdateWidget(covariant VerificationCooldownBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status || oldWidget.rejectedAt != widget.rejectedAt) {
      _calculateRemaining();
      _timer?.cancel();
      if (_cooldownActive) {
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          _calculateRemaining();
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _calculateRemaining() {
    if (widget.status != 'rejected' || widget.rejectedAt == null) {
      if (_cooldownActive && mounted) {
        setState(() {
          _cooldownActive = false;
          _remaining = Duration.zero;
        });
      }
      return;
    }

    final cooldownEnd = widget.rejectedAt!.toLocal().add(const Duration(hours: 24));
    final now = DateTime.now();
    final diff = cooldownEnd.difference(now);

    if (diff.isNegative || diff == Duration.zero) {
      if (_cooldownActive) {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _cooldownActive = false;
            _remaining = Duration.zero;
          });
          widget.onCooldownEnded?.call();
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _cooldownActive = true;
          _remaining = diff;
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    final local = dt.toLocal();
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} ${local.year}, $hour:$minute $period';
  }

  String _formatCountdown(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}h ${minutes.toString().padLeft(2, '0')}m ${seconds.toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == 'pending') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFBFDBFE)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1E40AF).withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFDBEAFE),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded, color: Color(0xFF1D4ED8), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.verificationTitle} Under Review',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDBEAFE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Review completes in 24 hrs',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1D4ED8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Your request has been submitted to the administrative verification team. Review will be completed within 24 hours. You will receive an instant notification once approved.',
              style: TextStyle(
                fontSize: 12.5,
                color: Color(0xFF334155),
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.status == 'rejected') {
      final reason = (widget.rejectionReason != null && widget.rejectionReason!.trim().isNotEmpty)
          ? widget.rejectionReason!.trim()
          : 'Verification criteria not met. Please provide clear, valid details.';

      if (_cooldownActive) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFECACA), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Color(0xFFFEE2E2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.verificationTitle} Rejected',
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: const Text(
                            '24h Reapply Cooldown Active',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Rejection reason card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Reason: $reason',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7F1D1D),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              if (widget.rejectedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Rejected on: ${_formatDateTime(widget.rejectedAt!)}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF991B1B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // Remaining countdown container
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF7F1D1D),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer_outlined, color: Colors.white, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'You can reapply in',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatCountdown(_remaining),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Form submission is locked until the 24-hour review period finishes.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.white60,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      // 24 hours have passed! Ready to reapply
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFD97706).withValues(alpha: 0.06),
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
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.replay_rounded, color: Color(0xFFD97706), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ready to Reapply for ${widget.verificationTitle}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF92400E),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD1FAE5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: const Text(
                          '24h Cooldown Completed',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF065F46),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Your previous submission was rejected: $reason\n\nThe 24-hour cooldown period has passed. You may now update your details and submit a fresh application.',
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF78350F),
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

