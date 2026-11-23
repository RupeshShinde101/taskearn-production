import 'package:flutter/material.dart';

enum EmptyTasksClipboardType {
  completed,
  browse,
  posted,
  accepted,
}

class EmptyTasksClipboardIllustration extends StatelessWidget {
  final EmptyTasksClipboardType type;

  const EmptyTasksClipboardIllustration({
    super.key,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── Soft background glow & city/hill silhouette ──
          Positioned(
            bottom: 20,
            child: Container(
              width: 190,
              height: 125,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                borderRadius: BorderRadius.circular(60),
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFDCEBFF).withValues(alpha: 0.85),
                    const Color(0xFFE8F2FF).withValues(alpha: 0.45),
                    const Color(0xFFF1F6FF).withValues(alpha: 0.0),
                  ],
                  stops: const [0.2, 0.65, 1.0],
                ),
              ),
            ),
          ),

          // City skyline silhouette behind clipboard (for completed tasks as in Image 1)
          if (type == EmptyTasksClipboardType.completed)
            Positioned(
              bottom: 38,
              child: CustomPaint(
                size: const Size(190, 50),
                painter: _CitySkylinePainter(),
              ),
            ),

          // Sparkle accent rays
          if (type == EmptyTasksClipboardType.completed)
            // Left sparkles as in Image 1
            const Positioned(
              left: 36,
              top: 50,
              child: _SparkleRays(isLeft: true),
            )
          else if (type == EmptyTasksClipboardType.browse)
            // Right sparkles as in Image 2
            const Positioned(
              right: 40,
              top: 48,
              child: _SparkleRays(isLeft: false),
            ),

          // ── Main Clipboard Card ──
          Positioned(
            bottom: 36,
            child: Container(
              width: 96,
              height: 118,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF3B82F6),
                  width: 3.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  // Top clip of the clipboard
                  Positioned(
                    top: -9,
                    child: Container(
                      width: 44,
                      height: 17,
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(7),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1D4ED8).withValues(alpha: 0.25),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 14,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),

                  // Inside content of the clipboard
                  Positioned.fill(
                    top: 14,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                      child: _buildInnerClipboardContent(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom right clock badge (for completed tasks in Image 1) ──
          if (type == EmptyTasksClipboardType.completed)
            Positioned(
              right: 50,
              bottom: 22,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF2563EB),
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1D4ED8).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: CustomPaint(
                  size: const Size(22, 22),
                  painter: _ClockHandsPainter(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInnerClipboardContent() {
    switch (type) {
      case EmptyTasksClipboardType.completed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildCheckmarkRow(40),
            _buildCheckmarkRow(32),
            _buildCheckmarkRow(24),
          ],
        );

      case EmptyTasksClipboardType.browse:
        return Center(
          child: Container(
            width: 44,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFF3B82F6),
                width: 2.2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Mountain / horizon silhouette
                Positioned(
                  bottom: 4,
                  left: 4,
                  right: 4,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Container(
                        width: 10,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF60A5FA),
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                // Sun / dot
                const Positioned(
                  top: 5,
                  right: 7,
                  child: CircleAvatar(
                    radius: 3,
                    backgroundColor: Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
        );

      case EmptyTasksClipboardType.posted:
      case EmptyTasksClipboardType.accepted:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildBarRow(52),
            _buildBarRow(42),
            _buildBarRow(30),
          ],
        );
    }
  }

  Widget _buildCheckmarkRow(double barWidth) {
    return Row(
      children: [
        const Icon(
          Icons.check_rounded,
          size: 15,
          color: Color(0xFF2563EB),
        ),
        const SizedBox(width: 4),
        Container(
          width: barWidth,
          height: 3.5,
          decoration: BoxDecoration(
            color: const Color(0xFFBFDBFE),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildBarRow(double barWidth) {
    return Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(
            color: Color(0xFF3B82F6),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: barWidth,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFBFDBFE),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

class _SparkleRays extends StatelessWidget {
  final bool isLeft;
  const _SparkleRays({required this.isLeft});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(20, 20),
      painter: _SparkleRaysPainter(isLeft: isLeft),
    );
  }
}

class _SparkleRaysPainter extends CustomPainter {
  final bool isLeft;
  const _SparkleRaysPainter({required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    if (isLeft) {
      canvas.drawLine(const Offset(16, 16), const Offset(2, 6), paint);
      canvas.drawLine(const Offset(16, 18), const Offset(6, 18), paint);
      canvas.drawLine(const Offset(18, 12), const Offset(10, 0), paint);
    } else {
      canvas.drawLine(const Offset(4, 16), const Offset(18, 6), paint);
      canvas.drawLine(const Offset(4, 18), const Offset(14, 18), paint);
      canvas.drawLine(const Offset(2, 12), const Offset(10, 0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ClockHandsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final handPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    // Minute hand pointing straight up
    canvas.drawLine(
      center,
      Offset(center.dx, center.dy - size.height * 0.42),
      handPaint,
    );
    // Hour hand pointing to 3 o'clock (right)
    canvas.drawLine(
      center,
      Offset(center.dx + size.width * 0.32, center.dy),
      handPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CitySkylinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFBFDBFE).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    // Faint miniature buildings & hill silhouette
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, size.height - 12)
      ..lineTo(14, size.height - 12)
      ..lineTo(14, size.height - 24)
      ..lineTo(26, size.height - 24)
      ..lineTo(26, size.height - 16)
      ..lineTo(38, size.height - 16)
      ..lineTo(38, size.height - 30)
      ..lineTo(50, size.height - 30)
      ..lineTo(50, size.height - 10)
      ..lineTo(size.width - 50, size.height - 10)
      ..lineTo(size.width - 50, size.height - 28)
      ..lineTo(size.width - 38, size.height - 28)
      ..lineTo(size.width - 38, size.height - 18)
      ..lineTo(size.width - 24, size.height - 18)
      ..lineTo(size.width - 24, size.height - 22)
      ..lineTo(size.width - 12, size.height - 22)
      ..lineTo(size.width - 12, size.height - 8)
      ..lineTo(size.width, size.height - 8)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);

    // Soft rounded hill
    final hillPaint = Paint()
      ..color = const Color(0xFFE2EDFE).withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final hillPath = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width / 2, size.height - 28, size.width, size.height)
      ..close();

    canvas.drawPath(hillPath, hillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

