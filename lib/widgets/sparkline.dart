import 'package:flutter/material.dart';

import '../models/types.dart';
import '../utils/chart.dart';

/// The small trend line on each watchlist row. Decorative, so it is hidden
/// from screen readers — the row already announces price and change.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.points,
    required this.width,
    required this.height,
    required this.color,
  });

  final List<PricePoint> points;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _SparklinePainter(points, color)),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.points, this.color);

  final List<PricePoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = buildChart(
      [for (final p in points) p.c],
      width: size.width,
      height: size.height,
      padding: 2,
    );
    if (chart == null) return;

    final path = Path()..moveTo(chart.xs.first, chart.ys.first);
    for (var i = 1; i < chart.xs.length; i++) {
      path.lineTo(chart.xs[i], chart.ys[i]);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.points != points || old.color != color;
}
