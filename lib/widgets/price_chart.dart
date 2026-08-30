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

/// One moving-average line drawn over the price series.
class MaOverlay {
  const MaOverlay({
    required this.period,
    required this.color,
    required this.values,
  });

  final int period;
  final Color color;

  /// Aligned to the raw candles the chart was given, with null before the
  /// average has warmed up. Sampled to the drawn bars alongside them.
  final List<double?> values;
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
    required this.window,
    required this.onWindowChanged,
    this.style = ChartStyle.candles,
    this.overlays = const [],
    this.height = _defaultHeight,
    this.baseline,
    this.onScrub,
    this.onInteractingChanged,
  });

  /// The whole fetched daily series. The window decides what is drawn.
  final List<Candle> candles;

  /// Trend colour, used for the line view and the baseline-relative tinting.
  final Color color;

  /// The visible slice, owned by the screen so the header and the RSI pane
  /// stay in step with the chart.
  final ChartWindow window;

  /// Fires with a new window as the user pinches or pans.
  final ValueChanged<ChartWindow> onWindowChanged;
  final ChartStyle style;

  /// Moving averages drawn on top of the price series.
  final List<MaOverlay> overlays;

  final double height;

  /// Price level the range's change is measured from, drawn as a dashed rule.
  final double? baseline;

  /// Fires with the candle under the finger, or null when it lifts.
  final ValueChanged<Candle?>? onScrub;

  /// Fires true while a gesture owns the chart, so the page can stop
  /// scrolling underneath it.
  final ValueChanged<bool>? onInteractingChanged;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _scrubIndex;
  List<double> _xs = const [];
  List<Candle> _drawn = const [];
  double _width = 0;

  /// Window and accumulated pan at the moment a pinch began. Zoom is applied
  /// against this rather than the live window, so rounding does not compound
  /// over the dozens of updates a single pinch delivers.
  ChartWindow? _gestureStart;
  double _panRemainder = 0;

  int get _maxBars => maxCandlesFor(_width);

  void _emit(ChartWindow next) {
    final clamped = next.clampTo(
      total: widget.candles.length,
      maxBars: _maxBars,
    );
    if (clamped != widget.window) widget.onWindowChanged(clamped);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStart = widget.window;
    _panRemainder = 0;
    widget.onInteractingChanged?.call(true);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final base = _gestureStart;
    if (base == null || _width <= 0) return;

    if (details.scale != 1.0) {
      final focal = (details.localFocalPoint.dx / _width).clamp(0.0, 1.0);
      _emit(base.zoomed(details.scale, focal: focal));
      return;
    }

    // A drag moves the chart with the finger: dragging right reveals older
    // bars, so the window start decreases.
    final barsPerPixel = widget.window.count / _width;
    _panRemainder -= details.focalPointDelta.dx * barsPerPixel;
    final whole = _panRemainder.truncate();
    if (whole != 0) {
      _panRemainder -= whole;
      _emit(widget.window.panned(whole));
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gestureStart = null;
    widget.onInteractingChanged?.call(false);
  }

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
    widget.onInteractingChanged?.call(false);
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
          ? 'Daily candlestick chart. Pinch to zoom, drag to pan, '
                'long press and drag to read individual bars.'
          : 'Daily price chart. Pinch to zoom, drag to pan, long press and '
                'drag to read individual prices.',
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            _width = width;

            // The window is the whole story now: one candle is one day, and
            // zooming changes how many days are on screen, never what a bar
            // means.
            final window = widget.window.clampTo(
              total: widget.candles.length,
              maxBars: maxCandlesFor(width),
            );
            _drawn = window.count <= 0
                ? const []
                : widget.candles.sublist(window.start, window.end);

            // Indicators are computed over the full series, so slicing to the
            // window keeps a 20 SMA correct at the left edge — it still uses
            // the bars before the window, which is why they are not
            // recomputed on the slice.
            final overlays = [
              for (final overlay in widget.overlays)
                (
                  color: overlay.color,
                  values: overlay.values.length >= window.end
                      ? overlay.values.sublist(window.start, window.end)
                      : const <double?>[],
                ),
            ];

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
                overlays: overlays,
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
                overlays: overlays,
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
              // Scale covers both pinch and drag. Scrubbing is on long press
              // instead, so a plain drag pans the chart the way it does in
              // every trading app rather than fighting the crosshair.
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onLongPressStart: (d) {
                widget.onInteractingChanged?.call(true);
                _handleTouch(d.localPosition.dx);
              },
              onLongPressMoveUpdate: (d) => _handleTouch(d.localPosition.dx),
              onLongPressEnd: (_) => _endScrub(),
              onLongPressCancel: _endScrub,
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

/// A sampled overlay ready to draw: one colour, one value per drawn bar.
typedef _Overlay = ({Color color, List<double?> values});

/// Draws each moving average, breaking the line across bars where the average
/// has not warmed up rather than joining across the gap.
void _drawOverlays(
  Canvas canvas,
  List<_Overlay> overlays,
  List<double> xs,
  double Function(double) yFor,
) {
  for (final overlay in overlays) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = overlay.color;

    Path? path;
    for (var i = 0; i < xs.length && i < overlay.values.length; i++) {
      final value = overlay.values[i];
      if (value == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      final point = Offset(xs[i], yFor(value));
      if (path == null) {
        path = Path()..moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);
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
    required this.overlays,
    required this.up,
    required this.down,
    required this.ruleColor,
    required this.baseline,
    required this.scrubIndex,
  });

  final CandleGeometry? geometry;
  final List<Candle> candles;
  final List<_Overlay> overlays;
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

    _drawOverlays(canvas, overlays, geometry.xs, geometry.yFor);

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
      old.overlays != overlays ||
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
    required this.overlays,
    required this.color,
    required this.fillColor,
    required this.ruleColor,
    required this.dotBorderColor,
    required this.baseline,
    required this.scrubIndex,
  });

  final ChartGeometry? geometry;
  final List<_Overlay> overlays;
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

    _drawOverlays(canvas, overlays, chart.xs, chart.yFor);

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
      old.overlays != overlays ||
      old.geometry != geometry ||
      old.color != color ||
      old.baseline != baseline ||
      old.scrubIndex != scrubIndex;
}
