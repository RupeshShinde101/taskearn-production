import 'package:flutter/material.dart';

/// Returns the bundled hero illustration asset matching the user's [gender].
String heroAvatarAssetForGender(String? gender) {
  final normalized = (gender ?? '').trim().toLowerCase();
  if (normalized == 'female' ||
      normalized == 'f' ||
      normalized == 'girl' ||
      normalized == 'woman') {
    return 'assets/images/header_avatar_girl.png';
  }
  return 'assets/images/header_avatar.png';
}

/// Illustrated 3D-style neighborhood map + location radar background used in
/// hero headers across Home and Post Task screens.
class HeroMapBackgroundPainter extends CustomPainter {
  final bool fadeBottom;
  final bool showRadarBeacon;
  final double beaconTop;
  final double beaconRightOffset;
  final double beaconLeftMinFactor;
  final double mapCenterYFactor;

  const HeroMapBackgroundPainter({
    this.fadeBottom = true,
    this.showRadarBeacon = true,
    this.beaconTop = 58.0,
    this.beaconRightOffset = 172.0,
    this.beaconLeftMinFactor = 0.46,
    this.mapCenterYFactor = 0.46,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final bounds = Offset.zero & size;
    canvas.saveLayer(bounds, Paint());

    // Soft sky-ice radial glow behind the right hero side
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.55, -0.25),
          radius: 0.95,
          colors: [
            const Color(0xFFE3EEFE),
            const Color(0xFFECF3FF).withValues(alpha: 0.65),
            const Color(0xFFF4F8FF).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(bounds),
    );

    // Tilted neighborhood map grid with varied parcels, parks & 3D buildings
    canvas.save();
    canvas.translate(size.width * 0.69, size.height * mapCenterYFactor);
    canvas.rotate(-0.36);

    final parcelBlueA = Paint()..color = const Color(0xFFD2E2FA);
    final parcelBlueB = Paint()..color = const Color(0xFFDEEAFD);
    final parcelSoft = Paint()..color = const Color(0xFFE9F2FF);
    final parkPaint = Paint()..color = const Color(0xFFD3EEDF);
    final parkInnerPaint = Paint()..color = const Color(0xFFC2E5D3);

    void drawParcel(Rect rect, Paint fill, {double radius = 6}) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        fill,
      );
    }

    void drawMiniBuilding(Rect base, {double heightOffset = 4.0}) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          base.translate(1.5, heightOffset * 0.7),
          const Radius.circular(3.5),
        ),
        Paint()..color = const Color(0xFFB4CCF2).withValues(alpha: 0.75),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          base,
          const Radius.circular(3.5),
        ),
        Paint()..color = const Color(0xFFC4D8F7),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          base.translate(-1.2, -heightOffset * 0.55),
          const Radius.circular(3.5),
        ),
        Paint()..color = const Color(0xFFEEF5FF),
      );
    }

    // Curated asymmetric city parcels
    final parcels = <(Rect, int)>[
      (const Rect.fromLTWH(-180, -110, 62, 42), 1),
      (const Rect.fromLTWH(-110, -110, 48, 42), 3),
      (const Rect.fromLTWH(-54, -110, 74, 42), 0),
      (const Rect.fromLTWH(28, -110, 58, 42), 2),
      (const Rect.fromLTWH(94, -110, 64, 42), 1),
      (const Rect.fromLTWH(-180, -60, 46, 52), 2),
      (const Rect.fromLTWH(-126, -60, 64, 24), 0),
      (const Rect.fromLTWH(-126, -30, 64, 22), 1),
      (const Rect.fromLTWH(-54, -60, 40, 52), 3),
      (const Rect.fromLTWH(-6, -60, 66, 52), 0),
      (const Rect.fromLTWH(68, -60, 50, 26), 1),
      (const Rect.fromLTWH(68, -28, 50, 20), 2),
      (const Rect.fromLTWH(126, -60, 52, 52), 0),
      (const Rect.fromLTWH(-170, 2, 52, 38), 1),
      (const Rect.fromLTWH(-110, 2, 48, 38), 2),
      (const Rect.fromLTWH(-54, 2, 74, 38), 1),
      (const Rect.fromLTWH(28, 2, 54, 38), 3),
      (const Rect.fromLTWH(90, 2, 70, 38), 0),
      (const Rect.fromLTWH(-140, 48, 72, 44), 2),
      (const Rect.fromLTWH(-60, 48, 56, 44), 0),
      (const Rect.fromLTWH(4, 48, 78, 44), 1),
      (const Rect.fromLTWH(90, 48, 66, 44), 3),
    ];

    for (final (rect, kind) in parcels) {
      final fill = switch (kind) {
        0 => parcelBlueA,
        1 => parcelBlueB,
        3 => parkPaint,
        _ => parcelSoft,
      };
      drawParcel(rect, fill);
      if (kind == 3) {
        drawParcel(rect.deflate(5), parkInnerPaint, radius: 4);
      }
    }

    // Crisp white road network
    final mainBoulevard = Paint()
      ..color = Colors.white
      ..strokeWidth = 9.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final boulevardCasing = Paint()
      ..color = const Color(0xFFC4D8F8).withValues(alpha: 0.70)
      ..strokeWidth = 11.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final crossStreet = Paint()
      ..color = Colors.white.withValues(alpha: 0.96)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final laneStroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.90)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;

    for (final y in [-64.0, -4.0, 44.0]) {
      final p1 = Offset(-210, y);
      final p2 = Offset(200, y);
      if (y == -4.0) {
        canvas.drawLine(p1, p2, boulevardCasing);
        canvas.drawLine(p1, p2, mainBoulevard);
      } else {
        canvas.drawLine(p1, p2, crossStreet);
      }
    }
    for (final x in [-114.0, -58.0, 24.0, 86.0]) {
      final p1 = Offset(x, -140);
      final p2 = Offset(x, 130);
      if (x == 24.0) {
        canvas.drawLine(p1, p2, boulevardCasing);
        canvas.drawLine(p1, p2, mainBoulevard);
      } else {
        canvas.drawLine(p1, p2, crossStreet);
      }
    }
    canvas.drawLine(const Offset(-128, -32), const Offset(-60, -32), laneStroke);
    canvas.drawLine(const Offset(66, -30), const Offset(120, -30), laneStroke);

    const plaza = Offset(24, -4);
    canvas.drawCircle(
      plaza,
      14,
      Paint()..color = const Color(0xFFC4D8F8).withValues(alpha: 0.65),
    );
    canvas.drawCircle(plaza, 12.2, Paint()..color = Colors.white);
    canvas.drawCircle(plaza, 5.2, Paint()..color = const Color(0xFFD5EDE0));

    final curvePath = Path()
      ..moveTo(-190, 92)
      ..quadraticBezierTo(-20, 74, 175, -92);
    canvas.drawPath(
      curvePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.85)
        ..strokeWidth = 6.0
        ..style = PaintingStyle.stroke,
    );

    drawMiniBuilding(const Rect.fromLTWH(-44, -100, 26, 20), heightOffset: 4.5);
    drawMiniBuilding(const Rect.fromLTWH(-12, -96, 22, 16), heightOffset: 3.5);
    drawMiniBuilding(const Rect.fromLTWH(2, -50, 28, 22), heightOffset: 5.0);
    drawMiniBuilding(const Rect.fromLTWH(34, -46, 18, 26), heightOffset: 4.0);
    drawMiniBuilding(const Rect.fromLTWH(98, -100, 28, 22), heightOffset: 5.0);
    drawMiniBuilding(const Rect.fromLTWH(134, -48, 26, 24), heightOffset: 4.5);
    drawMiniBuilding(const Rect.fromLTWH(98, 12, 32, 20), heightOffset: 4.0);

    canvas.restore();

    void drawTree(Offset pos, double scale) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(pos.dx + 1.5 * scale, pos.dy + 11 * scale),
          width: 9 * scale,
          height: 3.6 * scale,
        ),
        Paint()..color = const Color(0xFF94A3B8).withValues(alpha: 0.22),
      );
      canvas.drawLine(
        Offset(pos.dx, pos.dy + 3.5 * scale),
        Offset(pos.dx, pos.dy + 11 * scale),
        Paint()
          ..color = const Color(0xFF8C7A6B).withValues(alpha: 0.55)
          ..strokeWidth = 2.0 * scale
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        pos,
        7.0 * scale,
        Paint()..color = const Color(0xFF8FD0A8).withValues(alpha: 0.90),
      );
      canvas.drawCircle(
        Offset(pos.dx - 1.8 * scale, pos.dy - 1.8 * scale),
        4.3 * scale,
        Paint()..color = const Color(0xFFBBE6CB).withValues(alpha: 0.92),
      );
    }

    drawTree(Offset(size.width * 0.49, 14), 0.95);
    drawTree(Offset(size.width * 0.54, 42), 0.78);
    drawTree(Offset(size.width - 54, 18), 1.05);
    drawTree(Offset(size.width - 26, 28), 0.92);
    drawTree(Offset(size.width - 14, 56), 0.78);

    final routeOrigin = Offset(size.width - 20, size.height * 0.56);
    final beaconPos = Offset(
      (size.width - beaconRightOffset)
          .clamp(size.width * beaconLeftMinFactor, size.width - 116),
      beaconTop,
    );
    final routeCtrl = Offset(
      (routeOrigin.dx + beaconPos.dx) * 0.5,
      beaconTop * 0.42,
    );
    final routePath = Path()
      ..moveTo(routeOrigin.dx, routeOrigin.dy)
      ..quadraticBezierTo(routeCtrl.dx, routeCtrl.dy, beaconPos.dx, beaconPos.dy);
    final dotPaint = Paint()..color = const Color(0xFF2563EB).withValues(alpha: 0.30);
    for (final metric in routePath.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 9.0) {
        final tangent = metric.getTangentForOffset(d);
        if (tangent != null) {
          canvas.drawCircle(tangent.position, 1.8, dotPaint);
        }
      }
    }

    // Horizontal fade so left typography remains crisp over bright background
    final leftFade = Paint()
      ..blendMode = BlendMode.dstIn
      ..shader = LinearGradient(
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0.96),
          Colors.white.withValues(alpha: 0.24),
          Colors.transparent,
        ],
        stops: const [0.0, 0.46, 0.68, 0.88],
      ).createShader(bounds);
    canvas.drawRect(bounds, leftFade);

    if (fadeBottom) {
      final bottomFade = Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.74, 1.0],
        ).createShader(bounds);
      canvas.drawRect(bounds, bottomFade);
    }

    canvas.restore();

    if (showRadarBeacon) {
      final dotCenter = Offset(
        (size.width - beaconRightOffset)
            .clamp(size.width * beaconLeftMinFactor, size.width - 116),
        beaconTop,
      );
      canvas.drawCircle(
        dotCenter,
        22,
        Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.08),
      );
      canvas.drawCircle(
        dotCenter,
        15,
        Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.14),
      );
      canvas.drawCircle(
        dotCenter.translate(0, 1.5),
        10,
        Paint()..color = const Color(0xFF102A56).withValues(alpha: 0.08),
      );
      canvas.drawCircle(
        dotCenter,
        9.8,
        Paint()..color = Colors.white,
      );
      canvas.drawCircle(
        dotCenter,
        5.4,
        Paint()..color = const Color(0xFF2563EB),
      );
      canvas.drawCircle(
        dotCenter.translate(-1.5, -1.5),
        1.6,
        Paint()..color = Colors.white.withValues(alpha: 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HeroMapBackgroundPainter oldDelegate) =>
      oldDelegate.fadeBottom != fadeBottom ||
      oldDelegate.showRadarBeacon != showRadarBeacon ||
      oldDelegate.beaconTop != beaconTop ||
      oldDelegate.beaconRightOffset != beaconRightOffset ||
      oldDelegate.beaconLeftMinFactor != beaconLeftMinFactor ||
      oldDelegate.mapCenterYFactor != mapCenterYFactor;
}
