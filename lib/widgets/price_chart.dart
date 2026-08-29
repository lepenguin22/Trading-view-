import 'package:flutter/material.dart';

import '../models/types.dart';
import '../theme/app_theme.dart';
import '../utils/chart.dart';

const _defaultHeight = 220.0;
const _padding = 10.0;

/// How the detail screen draws a price series.
enum ChartStyle {
  candles('Candles', Icons.candlestick_chart),
  line('Line', Icons.show_chart);

  const ChartStyle(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The detail screen chart. Candlesticks by default, with a line alternative
/// for reading the overall shape of a long range.
///
/// Drawn with a [CustomPainter] rather than a charting package — the shapes
/// are simple, and it keeps the dependency list and the app size down.
class PriceChart extends StatefulWidget {
  const PriceChart({
    super.key,
    required this.candles,
    required this.color,
    this.style = ChartStyle.candles,
    this.height = _defaultHeight,
    this.baseline,
    this.onScrub,
  });

  final List<Candle> candles;

  /// Trend colour, used for the line view and the baseline-relative tinting.
  final Color color;
  final ChartStyle style;
  final double height;

  /// Price level the range's change is measured from, drawn as a dashed rule.
  final double? baseline;

  /// Fires with the candle under the finger, or null when it lifts. The
  /// candle is the aggregated one actually on screen, so the header reports
  /// what the user is pointing at.
  final ValueChanged<Candle?>? onScrub;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _scrubIndex;
  List<double> _xs = const [];
  List<Candle> _drawn = const [];

  void _handleTouch(double x) {
    if (_xs.isEmpty) return;
    final index = nearestIndex(_xs, x);
    if (index == _scrubIndex) return;
    setState(() => _scrubIndex = index);
    widget.onScrub?.call(index < _drawn.length ? _drawn[index] : null);
  }

  void _endScrub() {
    if (_scrubIndex == null) return;
    setState(() => _scrubIndex = null);
    widget.onScrub?.call(null);
  }

  @override
  void didUpdateWidget(PriceChart old) {
    super.didUpdateWidget(old);
    // A new series or style invalidates the index the finger was on.
    if (old.candles != widget.candles || old.style != widget.style) {
      _scrubIndex = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Semantics(
      image: true,
      label: widget.style == ChartStyle.candles
          ? 'Candlestick price chart. Drag across it to read individual bars.'
          : 'Price chart. Drag across it to read individual prices.',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            // Thin the series to what actually fits before drawing, so a long
            // range shows readable bars instead of a solid block.
            _drawn = widget.style == ChartStyle.candles
                ? aggregateCandles(widget.candles, maxCandlesFor(width))
                : widget.candles;

            final CustomPainter painter;
            if (widget.style == ChartStyle.candles) {
              final geometry = buildCandleChart(
                _drawn,
                width: width,
                height: widget.height,
                padding: _padding,
              );
              _xs = geometry?.xs ?? const [];
              painter = _CandlePainter(
                geometry: geometry,
                candles: _drawn,
                up: c.up,
                down: c.down,
                ruleColor: c.textFaint,
                baseline: widget.baseline,
                scrubIndex: _scrubIndex,
              );
            } else {
              final geometry = buildChart(
                [for (final candle in _drawn) candle.close],
                width: width,
                height: widget.height,
                padding: _padding,
              );
              _xs = geometry?.xs ?? const [];
              painter = _LinePainter(
                geometry: geometry,
                color: widget.color,
                fillColor: widget.color.withValues(alpha: 0.10),
                ruleColor: c.textFaint,
                dotBorderColor: c.card,
                baseline: widget.baseline,
                scrubIndex: _scrubIndex,
              );
            }

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
                size: Size(width, widget.height),
                painter: painter,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Draws the dashed baseline rule shared by both chart forms.
void _drawBaseline(Canvas canvas, double y, double width, Color color) {
  final paint = Paint()
    ..strokeWidth = 1
    ..color = color;
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

class _CandlePainter extends CustomPainter {
  const _CandlePainter({
    required this.geometry,
    required this.candles,
    required this.up,
    required this.down,
    required this.ruleColor,
    required this.baseline,
    required this.scrubIndex,
  });

  final CandleGeometry? geometry;
  final List<Candle> candles;
  final Color up;
  final Color down;
  final Color ruleColor;
  final double? baseline;
  final int? scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = this.geometry;
    if (geometry == null) return;

    final base = baseline;
    if (base != null) {
      final y = geometry.yForPrice(base);
      if (y != null) _drawBaseline(canvas, y, size.width, ruleColor);
    }

    // The wick is hairline-thin next to the body, and never wider than it.
    final wickWidth = (geometry.bodyWidth * 0.18).clamp(1.0, 2.0);

    for (var i = 0; i < candles.length && i < geometry.xs.length; i++) {
      final candle = candles[i];
      final x = geometry.xs[i];
      final paint = Paint()..color = candle.isUp ? up : down;

      canvas.drawRect(
        Rect.fromLTRB(
          x - wickWidth / 2,
          geometry.yFor(candle.high),
          x + wickWidth / 2,
          geometry.yFor(candle.low),
        ),
        paint,
      );

      final openY = geometry.yFor(candle.open);
      final closeY = geometry.yFor(candle.close);
      final top = openY < closeY ? openY : closeY;
      final bottom = openY < closeY ? closeY : openY;
      canvas.drawRect(
        Rect.fromLTRB(
          x - geometry.bodyWidth / 2,
          top,
          x + geometry.bodyWidth / 2,
          // An unchanged bar would be a zero-height rect and vanish; give it
          // a visible line so the session still reads as a bar.
          bottom - top < 1 ? top + 1 : bottom,
        ),
        paint,
      );
    }

    final i = scrubIndex;
    if (i != null && i < geometry.xs.length) {
      canvas.drawLine(
        Offset(geometry.xs[i], 0),
        Offset(geometry.xs[i], size.height),
        Paint()
          ..strokeWidth = 1
          ..color = ruleColor,
      );
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.candles != candles ||
      old.geometry != geometry ||
      old.baseline != baseline ||
      old.scrubIndex != scrubIndex ||
      old.up != up ||
      old.down != down;
}

class _LinePainter extends CustomPainter {
  const _LinePainter({
    required this.geometry,
    required this.color,
    required this.fillColor,
    required this.ruleColor,
    required this.dotBorderColor,
    required this.baseline,
    required this.scrubIndex,
  });

  final ChartGeometry? geometry;
  final Color color;
  final Color fillColor;
  final Color ruleColor;
  final Color dotBorderColor;
  final double? baseline;
  final int? scrubIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = geometry;
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

    final base = baseline;
    if (base != null) {
      final y = chart.yForPrice(base);
      if (y != null) _drawBaseline(canvas, y, size.width, ruleColor);
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

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.geometry != geometry ||
      old.color != color ||
      old.baseline != baseline ||
      old.scrubIndex != scrubIndex;
}
