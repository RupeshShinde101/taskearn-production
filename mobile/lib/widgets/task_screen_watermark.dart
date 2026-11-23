import 'package:flutter/material.dart';

/// Renders a soft, ambient map grid with floating translucent location pin markers
/// matching the Workmate4u Ice Blue design for Browse Tasks and My Tasks screens.
class TaskScreenWatermark extends StatelessWidget {
  final Widget child;

  const TaskScreenWatermark({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base subtle ice-blue gradient
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFEFF6FF), // soft sky tint
                Color(0xFFF8FAFC), // clean near-white
                Color(0xFFF1F5F9), // subtle cool slate base
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        // Ambient map streets & pins
        const Positioned.fill(
          child: CustomPaint(
            painter: _TaskMapWatermarkPainter(),
          ),
        ),
        // Foreground content
        child,
      ],
    );
  }
}

class _TaskMapWatermarkPainter extends CustomPainter {
  const _TaskMapWatermarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final roadPaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final roadThin = Paint()
      ..color = const Color(0xFFBFDBFE).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Diagonal road network
    final p1 = Path()
      ..moveTo(-size.width * 0.2, size.height * 0.12)
      ..lineTo(size.width * 1.2, size.height * 0.42);
    canvas.drawPath(p1, roadPaint);

    final p2 = Path()
      ..moveTo(size.width * 1.1, size.height * 0.05)
      ..lineTo(-size.width * 0.1, size.height * 0.55);
    canvas.drawPath(p2, roadPaint);

    final p3 = Path()
      ..moveTo(-size.width * 0.1, size.height * 0.62)
      ..lineTo(size.width * 1.15, size.height * 0.92);
    canvas.drawPath(p3, roadPaint);

    final p4 = Path()
      ..moveTo(size.width * 1.15, size.height * 0.48)
      ..lineTo(-size.width * 0.15, size.height * 0.98);
    canvas.drawPath(p4, roadPaint);

    // Connecting street cross-links
    canvas.drawLine(
      Offset(size.width * 0.25, size.height * 0.2),
      Offset(size.width * 0.45, size.height * 0.75),
      roadThin,
    );
    canvas.drawLine(
      Offset(size.width * 0.70, size.height * 0.15),
      Offset(size.width * 0.85, size.height * 0.70),
      roadThin,
    );
    canvas.drawLine(
      Offset(size.width * 0.05, size.height * 0.38),
      Offset(size.width * 0.95, size.height * 0.38),
      roadThin,
    );
    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.78),
      Offset(size.width * 0.90, size.height * 0.78),
      roadThin,
    );

    // Floating location pins as seen in the reference designs
    final pins = <(double, double, double)>[
      (0.28, 0.02, 1.0), // top left pin
      (0.90, 0.22, 1.05), // upper right pin
      (0.16, 0.44, 0.95), // mid left pin
      (0.84, 0.42, 1.0), // mid right pin
      (0.18, 0.77, 1.1), // lower left pin
      (0.81, 0.81, 1.05), // lower right pin
    ];

    for (final (rx, ry, scale) in pins) {
      _drawPin(canvas, Offset(size.width * rx, size.height * ry), scale);
    }
  }

  void _drawPin(Canvas canvas, Offset center, double scale) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);

    final pinPaint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.32)
      ..style = PaintingStyle.fill;

    // Map pin teardrop path
    const r = 11.0;
    final path = Path()
      ..moveTo(0, r * 1.5) // tip pointing down
      ..cubicTo(-r * 1.1, r * 0.5, -r, -r * 0.4, -r, -r)
      ..arcToPoint(
        const Offset(r, -r),
        radius: const Radius.circular(r),
        clockwise: true,
      )
      ..cubicTo(r, -r * 0.4, r * 1.1, r * 0.5, 0, r * 1.5)
      ..close();

    canvas.drawPath(path, pinPaint);

    // Inner white dot
    final innerDot = Paint()
      ..color = Colors.white.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(0, -11.0), 4.2, innerDot);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

