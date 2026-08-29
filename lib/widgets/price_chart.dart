import 'package:flutter/material.dart';

import '../models/types.dart';
import '../theme/app_theme.dart';
import '../utils/chart.dart';

const _defaultHeight = 220.0;
const _padding = 10.0;

/// The detail screen chart: a filled price line the user can drag along to
/// read off individual points.
///
/// Drawn with a [CustomPainter] rather than a charting package — the shapes
/// are simple, and it keeps the dependency list and the app size down.
class PriceChart extends StatefulWidget {
  const PriceChart({
    super.key,
    required this.points,
    required this.color,
    this.height = _defaultHeight,
    this.baseline,
    this.onScrub,
  });

  final List<PricePoint> points;
  final Color color;
  final double height;

  /// Price level the range's change is measured from, drawn as a dashed rule.
  final double? baseline;

  /// Fires with the scrubbed index, or null when the finger lifts.
  final ValueChanged<int?>? onScrub;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _scrubIndex;
  ChartGeometry? _chart;

  void _handleTouch(double x) {
    final chart = _chart;
    if (chart == null) return;
    final index = nearestIndex(chart.xs, x);
    if (index == _scrubIndex) return;
    setState(() => _scrubIndex = index);
    widget.onScrub?.call(index);
  }

  void _endScrub() {
    if (_scrubIndex == null) return;
    setState(() => _scrubIndex = null);
    widget.onScrub?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      image: true,
      label: 'Price chart. Drag across it to read individual prices.',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _chart = buildChart(
              widget.points,
              width: constraints.maxWidth,
              height: widget.height,
              padding: _padding,
            );

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Claiming the horizontal drag stops the enclosing scroll view
              // from stealing the gesture mid-scrub; a vertical drag still
              // scrolls the page.
              onHorizontalDragStart: (d) => _handleTouch(d.localPosition.dx),
              onHorizontalDragUpdate: (d) => _handleTouch(d.localPosition.dx),
              onHorizontalDragEnd: (_) => _endScrub(),
              onHorizontalDragCancel: _endScrub,
              onTapDown: (d) => _handleTouch(d.localPosition.dx),
              onTapUp: (_) => _endScrub(),
              onTapCancel: _endScrub,
              child: CustomPaint(
                size: Size(constraints.maxWidth, widget.height),
                painter: _PriceChartPainter(
                  chart: _chart,
                  color: widget.color,
                  fillColor: widget.color.withValues(alpha: 0.10),
                  ruleColor: c.textFaint,
                  dotBorderColor: c.card,
                  baseline: widget.baseline,
                  scrubIndex: _scrubIndex,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  const _PriceChartPainter({
    required this.chart,
    required this.color,
    required this.fillColor,
    required this.ruleColor,
    required this.dotBorderColor,
    required this.baseline,
    required this.scrubIndex,
  });

  final ChartGeometry? chart;
  final Color color;
  final Color fillColor;
  final Color ruleColor;
  final Color dotBorderColor;
  final double? baseline;
  final int? scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = this.chart;
    if (chart == null) return;

    final line = Path()..moveTo(chart.xs.first, chart.ys.first);
    for (var i = 1; i < chart.xs.length; i++) {
      line.lineTo(chart.xs[i], chart.ys[i]);
    }

    final area = Path.from(line)
      ..lineTo(chart.xs.last, size.height)
      ..lineTo(chart.xs.first, size.height)
      ..close();

    canvas.drawPath(area, Paint()..color = fillColor);

    // Project the baseline price into chart space so the dashed rule lines up
    // with the series it is being compared against.
    final base = baseline;
    if (base != null) {
      final y = chart.yForPrice(base);
      if (y != null) _drawDashedLine(canvas, y, size.width);
    }

    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    final i = scrubIndex;
    if (i != null && i < chart.xs.length) {
      canvas.drawLine(
        Offset(chart.xs[i], 0),
        Offset(chart.xs[i], size.height),
        Paint()
          ..strokeWidth = 1
          ..color = ruleColor,
      );
      final dot = Offset(chart.xs[i], chart.ys[i]);
      canvas.drawCircle(dot, 5, Paint()..color = color);
      canvas.drawCircle(
        dot,
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = dotBorderColor,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, double y, double width) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = ruleColor;
    const dash = 3.0;
    const gap = 4.0;
    for (var x = 0.0; x < width; x += dash + gap) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dash).clamp(0.0, width), y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PriceChartPainter old) =>
      old.chart != chart ||
      old.color != color ||
      old.baseline != baseline ||
      old.scrubIndex != scrubIndex;
}
