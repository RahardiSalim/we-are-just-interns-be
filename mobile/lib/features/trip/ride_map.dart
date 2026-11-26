import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../theme.dart';

/// A drawn city map in the Gojek map style: irregular blocks split by thin white streets, large
/// parks, a river with green banks, two curved main roads, and the ride: a smooth green route from
/// the pickup pin (green, with the blue "you are here" dot) to the drop-off pin (orange).
/// Drawn, not a picture, so it stays sharp at any zoom; the rider can pan and pinch it.
///
/// shortcut: GoSafe never reads location, so the city and the route are made up from [seed]
/// (the same ride always gets the same map). The real app shows Gojek's own map here.
class RideMap extends StatelessWidget {
  const RideMap({
    super.key,
    required this.seed,
    required this.focus,
    this.view,
  });

  final int seed;

  /// The pan and zoom, so a button can put the map back (identity = the whole route).
  final TransformationController? view;

  /// Where the route goes, as fractions of the map's size: the part the sheet doesn't cover.
  final Rect focus;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: InteractiveViewer(
      transformationController: view,
      minScale: 1,
      maxScale: 4,
      child: SizedBox.expand(
        child: RepaintBoundary(
          child: Semantics(
            label: 'Map of your ride',
            image: true,
            child: CustomPaint(painter: _MapPainter(seed, focus)),
          ),
        ),
      ),
    ),
  );
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.seed, this.focus);

  final int seed;
  final Rect focus;

  static const _cell = 64.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final fill = Paint();
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(Offset.zero & size, fill..color = GoSafeColors.mapBg);

    // A grid with every corner nudged, so blocks come out irregular like a real city.
    final cols = (size.width / _cell).ceil() + 3;
    final rows = (size.height / _cell).ceil() + 3;
    final pts = List.generate(
      rows,
      (j) => List.generate(cols, (i) {
        final jx = (rnd.nextDouble() - 0.5) * _cell * 0.55;
        final jy = (rnd.nextDouble() - 0.5) * _cell * 0.55;
        return Offset((i - 1) * _cell + jx, (j - 1) * _cell + jy);
      }),
    );

    // Two or three big parks.
    final parks = [
      for (var k = 0; k < 2 + rnd.nextInt(2); k++)
        (
          Offset(
            size.width * (0.15 + 0.7 * rnd.nextDouble()),
            size.height * (0.1 + 0.8 * rnd.nextDouble()),
          ),
          70 + rnd.nextDouble() * 70,
        ),
    ];
    bool isPark(int i, int j) {
      if (i < 0 || j < 0 || i + 1 >= cols || j + 1 >= rows) return false;
      final c = (pts[j][i] + pts[j + 1][i + 1]) / 2;
      return parks.any((p) => (c - p.$1).distance < p.$2);
    }

    const tones = [
      GoSafeColors.mapBlock,
      GoSafeColors.mapBlockLight,
      GoSafeColors.mapBg,
    ];
    for (var j = 0; j + 1 < rows; j++) {
      for (var i = 0; i + 1 < cols; i++) {
        final quad = Path()
          ..moveTo(pts[j][i].dx, pts[j][i].dy)
          ..lineTo(pts[j][i + 1].dx, pts[j][i + 1].dy)
          ..lineTo(pts[j + 1][i + 1].dx, pts[j + 1][i + 1].dy)
          ..lineTo(pts[j + 1][i].dx, pts[j + 1][i].dy)
          ..close();
        final park = isPark(i, j);
        canvas.drawPath(
          quad,
          fill
            ..color = park
                ? GoSafeColors.mapPark
                : tones[rnd.nextInt(tones.length)],
        );
        // Some blocks split in two by a lane.
        if (!park && rnd.nextDouble() < 0.45) {
          final across = rnd.nextBool();
          final a = across
              ? (pts[j][i] + pts[j + 1][i]) / 2
              : (pts[j][i] + pts[j][i + 1]) / 2;
          final b = across
              ? (pts[j][i + 1] + pts[j + 1][i + 1]) / 2
              : (pts[j + 1][i] + pts[j + 1][i + 1]) / 2;
          canvas.drawLine(
            a,
            b,
            line
              ..color = GoSafeColors.mapRoad
              ..strokeWidth = 1.5,
          );
        }
      }
    }

    // Streets on every block edge, except between two park blocks.
    line
      ..color = GoSafeColors.mapRoad
      ..strokeWidth = 2.5;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        if (i + 1 < cols && !(isPark(i, j - 1) && isPark(i, j))) {
          canvas.drawLine(pts[j][i], pts[j][i + 1], line);
        }
        if (j + 1 < rows && !(isPark(i - 1, j) && isPark(i, j))) {
          canvas.drawLine(pts[j][i], pts[j + 1][i], line);
        }
      }
    }

    // The river with its green banks.
    final w = size.width, h = size.height;
    final river = Path()
      ..moveTo(-30, h * 0.42)
      ..cubicTo(w * 0.25, h * 0.48, w * 0.40, h * 0.62, w * 0.62, h * 0.74)
      ..cubicTo(w * 0.78, h * 0.83, w * 0.90, h * 0.90, w + 30, h * 0.97);
    line.strokeCap = StrokeCap.butt;
    canvas
      ..drawPath(
        river,
        line
          ..color = GoSafeColors.mapPark
          ..strokeWidth = 42,
      )
      ..drawPath(
        river,
        line
          ..color = GoSafeColors.mapWater
          ..strokeWidth = 24,
      );

    // Two main roads, gently curved, crossing the river on bridges.
    final roads = [
      Path()
        ..moveTo(w * (0.30 + rnd.nextDouble() * 0.1), -20)
        ..cubicTo(w * 0.42, h * 0.3, w * 0.30, h * 0.6, w * 0.38, h + 20),
      Path()
        ..moveTo(-20, h * (0.18 + rnd.nextDouble() * 0.1))
        ..cubicTo(w * 0.3, h * 0.26, w * 0.6, h * 0.14, w + 20, h * 0.22),
    ];
    line.strokeCap = StrokeCap.round;
    for (final r in roads) {
      canvas
        ..drawPath(
          r,
          line
            ..color = GoSafeColors.mapRoadEdge
            ..strokeWidth = 11,
        )
        ..drawPath(
          r,
          line
            ..color = GoSafeColors.mapRoad
            ..strokeWidth = 9,
        );
    }

    // The ride: pickup (bottom right of the open area) to drop-off (top left), a smooth curve.
    Offset at(double fx, double fy) => Offset(
      w * (focus.left + focus.width * fx),
      h * (focus.top + focus.height * fy),
    );
    final start = at(0.86, 0.92);
    final end = at(0.14, 0.30);
    final bend = at(0.40, 0.30);
    final route = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx - w * 0.18,
        start.dy - h * 0.06,
        bend.dx + w * 0.02,
        bend.dy + h * 0.22,
        bend.dx,
        bend.dy,
      )
      ..lineTo(bend.dx - w * 0.07, bend.dy - h * 0.01)
      ..lineTo(end.dx, end.dy);
    canvas.drawPath(
      route,
      line
        ..color = GoSafeColors.rideIcon
        ..strokeWidth = 6,
    );

    // "You are here": a blue dot in a soft halo, under the pickup pin.
    canvas
      ..drawCircle(
        start,
        22,
        Paint()..color = GoSafeColors.mapDot.withValues(alpha: 0.18),
      )
      ..drawCircle(start, 8, Paint()..color = Colors.white)
      ..drawCircle(start, 5.5, Paint()..color = GoSafeColors.mapDot);
    _pin(
      canvas,
      start,
      GoSafeColors.rideIcon,
      (c) => _glyph(canvas, Icons.arrow_upward_rounded, c, 28, Colors.white),
    );
    _pin(
      canvas,
      end,
      GoSafeColors.dropoff,
      (c) => canvas.drawCircle(c, 7, Paint()..color = Colors.white),
    );
  }

  /// A Gojek map pin: a coloured disc in a white ring with a short white point, tip at [tip].
  void _pin(
    Canvas canvas,
    Offset tip,
    Color color,
    void Function(Offset centre) mark,
  ) {
    const r = 22.0;
    final c = tip - const Offset(0, r + 12);
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final point = Path()
      ..moveTo(c.dx - 9, c.dy + r - 2)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(c.dx + 9, c.dy + r - 2)
      ..close();
    canvas
      ..drawCircle(c + const Offset(0, 3), r + 4, shadow)
      ..drawPath(point, Paint()..color = Colors.white)
      ..drawCircle(c, r + 4, Paint()..color = Colors.white)
      ..drawCircle(c, r, Paint()..color = color);
    mark(c);
  }

  void _glyph(
    Canvas canvas,
    IconData icon,
    Offset at,
    double size,
    Color color,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: size,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.seed != seed || old.focus != focus;
}
