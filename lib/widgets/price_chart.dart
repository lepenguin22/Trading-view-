import 'package:flutter/material.dart';

import '../models/types.dart';
import '../theme/app_theme.dart';
import '../utils/chart.dart';
import '../utils/format.dart';

const _defaultHeight = 220.0;
const _padding = 10.0;

/// Gap between the plot and its price axis.
const _axisGap = 6.0;

/// Type scale for the axis labels and the price tags.
const axisLabelSize = 10.0;

/// Measures the gutter a price axis needs for [labels], so the plot can be
/// narrowed before any geometry is built.
///
/// Measured rather than guessed: a four-figure price with a thousands
/// separator is far wider than a two-figure one, and a fixed gutter would
/// either clip those or waste space on every other symbol.
double priceAxisWidth(List<String> labels) {
  var widest = 0.0;
  for (final label in labels) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontSize: axisLabelSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (painter.width > widest) widest = painter.width;
  }
  return widest == 0 ? 0 : widest + _axisGap;
}

/// One horizontal gridline: where it sits in price, and what it reads.
typedef PriceTick = ({double price, String label});

/// Chooses the gridlines for a price range, in the currency's display units.
List<PriceTick> priceTicksFor(double min, double max, String currency) {
  final ticks = niceTicks(axisScale(min, currency), axisScale(max, currency));
  if (ticks.isEmpty) return const [];
  final decimals = axisDecimals(ticks);
  return [
    for (final tick in ticks)
      (
        price: axisUnscale(tick, currency),
        label: formatAxisNumber(tick, decimals),
      ),
  ];
}

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

/// A crossover marked on the price series.
class ChartMarker {
  const ChartMarker({
    required this.index,
    required this.price,
    required this.up,
    required this.label,
  });

  /// Index into the full candle series the chart was given, so the chart can
  /// place it against whatever window is on screen.
  final int index;

  /// Price level the marker is anchored to.
  final double price;

  /// An upward crossing. Drawn as an up triangle below the bar; a downward one
  /// is a down triangle above it, so the two are told apart by shape and
  /// position as well as by colour.
  final bool up;

  /// Read out in the chart's semantics label, e.g. "Golden Cross".
  final String label;
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
    this.markers = const [],
    this.currency = 'USD',
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

  /// Crossovers marked on the price series. Indexed against the full candle
  /// series, and clipped to the visible window when drawn.
  final List<ChartMarker> markers;

  /// Quoted currency, for scaling and labelling the price axis.
  final String currency;

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
            // The window is the whole story now: one candle is one day, and
            // zooming changes how many days are on screen, never what a bar
            // means.
            final window = widget.window.clampTo(
              total: widget.candles.length,
              maxBars: maxCandlesFor(constraints.maxWidth),
            );
            _drawn = window.count <= 0
                ? const []
                : widget.candles.sublist(window.start, window.end);

            // The axis is measured and subtracted before any geometry is
            // built, so the plot never draws underneath its own labels.
            final range = _priceRange(_drawn, widget.style);
            final ticks = range == null
                ? const <PriceTick>[]
                : priceTicksFor(range.min, range.max, widget.currency);
            final axisWidth = priceAxisWidth([
              for (final tick in ticks) tick.label,
            ]);
            final decimals = axisDecimals([
              for (final tick in ticks) axisScale(tick.price, widget.currency),
            ]);
            String labelFor(double price) =>
                formatAxisNumber(axisScale(price, widget.currency), decimals);
            final width = (constraints.maxWidth - axisWidth).clamp(
              1.0,
              constraints.maxWidth,
            );
            _width = width;

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

            // Markers are indexed against the full series, so they are
            // shifted into window coordinates and anything off screen is
            // dropped before the painter sees it.
            final markers = [
              for (final marker in widget.markers)
                if (marker.index >= window.start && marker.index < window.end)
                  (
                    index: marker.index - window.start,
                    price: marker.price,
                    up: marker.up,
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
                markers: markers,
                up: c.up,
                down: c.down,
                ruleColor: c.textFaint,
                baseline: widget.baseline,
                scrubIndex: _scrubIndex,
                axis: _AxisSpec(
                  ticks: ticks,
                  plotWidth: width,
                  gridColor: c.border,
                  labelColor: c.textFaint,
                  tagTextColor: c.card,
                  labelFor: labelFor,
                ),
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
                markers: markers,
                color: widget.color,
                up: c.up,
                down: c.down,
                fillColor: widget.color.withValues(alpha: 0.10),
                ruleColor: c.textFaint,
                dotBorderColor: c.card,
                baseline: widget.baseline,
                scrubIndex: _scrubIndex,
                axis: _AxisSpec(
                  ticks: ticks,
                  plotWidth: width,
                  gridColor: c.border,
                  labelColor: c.textFaint,
                  tagTextColor: c.card,
                  labelFor: labelFor,
                ),
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
                // The canvas spans the gutter too; the painter clips the plot
                // to `plotWidth` and draws the axis in what is left.
                size: Size(constraints.maxWidth, widget.height),
                painter: painter,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The vertical extent the axis must span.
///
/// Candles need every wick inside the viewport, so the range runs low-to-high;
/// the line view only draws closes, and using highs there would leave the line
/// floating in dead space.
({double min, double max})? _priceRange(List<Candle> drawn, ChartStyle style) {
  if (drawn.isEmpty) return null;
  var min = style == ChartStyle.candles ? drawn.first.low : drawn.first.close;
  var max = style == ChartStyle.candles ? drawn.first.high : drawn.first.close;
  for (final candle in drawn) {
    final low = style == ChartStyle.candles ? candle.low : candle.close;
    final high = style == ChartStyle.candles ? candle.high : candle.close;
    if (low < min) min = low;
    if (high > max) max = high;
  }
  return (min: min, max: max);
}

/// Everything the painters need to draw the price axis.
class _AxisSpec {
  const _AxisSpec({
    required this.ticks,
    required this.plotWidth,
    required this.gridColor,
    required this.labelColor,
    required this.tagTextColor,
    required this.labelFor,
  });

  final List<PriceTick> ticks;

  /// Where the plot ends and the gutter begins.
  final double plotWidth;

  final Color gridColor;
  final Color labelColor;

  /// Ink for text sitting on a filled price tag.
  final Color tagTextColor;

  /// Formats a raw quote price the way the axis labels it, so a price tag
  /// reads in the same units and precision as the gridlines beside it.
  /// Excluded from equality: it is derived from the same inputs as [ticks].
  final String Function(double price) labelFor;

  @override
  bool operator ==(Object other) =>
      other is _AxisSpec &&
      other.plotWidth == plotWidth &&
      other.gridColor == gridColor &&
      other.labelColor == labelColor &&
      _sameTicks(other.ticks, ticks);

  @override
  int get hashCode => Object.hash(plotWidth, ticks.length, gridColor);

  static bool _sameTicks(List<PriceTick> a, List<PriceTick> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].price != b[i].price || a[i].label != b[i].label) return false;
    }
    return true;
  }
}

/// Draws the gridlines and their labels. Gridlines run only across the plot so
/// they never cross into the gutter and collide with the text.
void _paintAxis(
  Canvas canvas,
  _AxisSpec axis,
  Size size,
  double Function(double) yFor,
) {
  for (final tick in axis.ticks) {
    final y = yFor(tick.price);
    if (y < 0 || y > size.height) continue;

    canvas.drawLine(
      Offset(0, y),
      Offset(axis.plotWidth, y),
      Paint()
        ..strokeWidth = 1
        ..color = axis.gridColor,
    );

    final label = TextPainter(
      text: TextSpan(
        text: tick.label,
        style: TextStyle(color: axis.labelColor, fontSize: axisLabelSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(
      canvas,
      Offset(axis.plotWidth + _axisGap, y - label.height / 2),
    );
  }
}

/// Draws a filled price tag in the gutter — the current price, or the one
/// under the finger. This is what makes a level readable at a glance rather
/// than by interpolating between gridlines.
void _paintPriceTag(
  Canvas canvas,
  _AxisSpec axis,
  Size size,
  double y,
  String label,
  Color fill,
) {
  if (y < 0 || y > size.height) return;

  final painter = TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        color: axis.tagTextColor,
        fontSize: axisLabelSize,
        fontWeight: FontWeight.w600,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final rect = Rect.fromLTWH(
    axis.plotWidth + 2,
    y - painter.height / 2 - 2,
    (size.width - axis.plotWidth - 4).clamp(0.0, double.infinity),
    painter.height + 4,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, const Radius.circular(3)),
    Paint()..color = fill,
  );
  painter.paint(
    canvas,
    Offset(rect.left + (rect.width - painter.width) / 2, rect.top + 2),
  );
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

/// A marker sampled to the drawn bars: an index into them, and where it sits.
typedef _Marker = ({int index, double price, bool up});

/// Height and width of a crossover triangle, and its clearance from the bar.
const _markerSize = 7.0;
const _markerGap = 5.0;

/// Draws each crossover as a triangle clear of the bar it belongs to.
///
/// Bullish crossings point up from below the bar and bearish point down from
/// above, so the two are distinguishable without relying on colour — the up
/// and down greens and reds are close enough under common colour vision
/// deficiencies that shape has to carry the meaning too.
void _drawMarkers(
  Canvas canvas,
  List<_Marker> markers,
  List<double> xs,
  double Function(double) yFor,
  Color up,
  Color down,
  double height,
) {
  const half = _markerSize / 2;

  for (final marker in markers) {
    if (marker.index < 0 || marker.index >= xs.length) continue;
    final x = xs[marker.index];
    final anchor = yFor(marker.price);
    if (!anchor.isFinite) continue;

    // Nudged back inside when a crossing lands against the top or bottom of
    // the plot, where the triangle would otherwise be drawn off-canvas.
    final Path path;
    if (marker.up) {
      var tip = anchor + _markerGap;
      if (tip + _markerSize > height) tip = height - _markerSize;
      path = Path()
        ..moveTo(x, tip)
        ..lineTo(x - half, tip + _markerSize)
        ..lineTo(x + half, tip + _markerSize)
        ..close();
    } else {
      var tip = anchor - _markerGap;
      if (tip - _markerSize < 0) tip = _markerSize;
      path = Path()
        ..moveTo(x, tip)
        ..lineTo(x - half, tip - _markerSize)
        ..lineTo(x + half, tip - _markerSize)
        ..close();
    }
    canvas.drawPath(path, Paint()..color = marker.up ? up : down);
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
    required this.markers,
    required this.up,
    required this.down,
    required this.ruleColor,
    required this.baseline,
    required this.scrubIndex,
    required this.axis,
  });

  final CandleGeometry? geometry;
  final List<Candle> candles;
  final List<_Overlay> overlays;
  final List<_Marker> markers;
  final Color up;
  final Color down;
  final Color ruleColor;
  final double? baseline;
  final int? scrubIndex;
  final _AxisSpec axis;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = this.geometry;
    if (geometry == null) return;

    // Behind everything: gridlines are reference, not content.
    _paintAxis(canvas, axis, size, geometry.yFor);

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
    _drawMarkers(
      canvas,
      markers,
      geometry.xs,
      geometry.yFor,
      up,
      down,
      size.height,
    );

    final i = scrubIndex;
    if (i != null && i < geometry.xs.length && i < candles.length) {
      canvas.drawLine(
        Offset(geometry.xs[i], 0),
        Offset(geometry.xs[i], size.height),
        Paint()
          ..strokeWidth = 1
          ..color = ruleColor,
      );
      // While scrubbing the tag follows the finger, so the bar's close can be
      // read straight off the axis.
      final scrubbed = candles[i];
      _paintPriceTag(
        canvas,
        axis,
        size,
        geometry.yFor(scrubbed.close),
        axis.labelFor(scrubbed.close),
        scrubbed.isUp ? up : down,
      );
    } else if (candles.isNotEmpty) {
      final latest = candles.last;
      _paintPriceTag(
        canvas,
        axis,
        size,
        geometry.yFor(latest.close),
        axis.labelFor(latest.close),
        latest.isUp ? up : down,
      );
    }
  }

  @override
  bool shouldRepaint(_CandlePainter old) =>
      old.axis != axis ||
      old.overlays != overlays ||
      old.markers != markers ||
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
    required this.markers,
    required this.color,
    required this.up,
    required this.down,
    required this.fillColor,
    required this.ruleColor,
    required this.dotBorderColor,
    required this.baseline,
    required this.scrubIndex,
    required this.axis,
  });

  final ChartGeometry? geometry;
  final List<_Overlay> overlays;
  final List<_Marker> markers;
  final Color color;
  final Color up;
  final Color down;
  final Color fillColor;
  final Color ruleColor;
  final Color dotBorderColor;
  final double? baseline;
  final int? scrubIndex;
  final _AxisSpec axis;

  @override
  void paint(Canvas canvas, Size size) {
    final chart = geometry;
    if (chart == null) return;

    _paintAxis(canvas, axis, size, chart.yFor);

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
    _drawMarkers(canvas, markers, chart.xs, chart.yFor, up, down, size.height);

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
      old.axis != axis ||
      old.overlays != overlays ||
      old.markers != markers ||
      old.geometry != geometry ||
      old.color != color ||
      old.baseline != baseline ||
      old.scrubIndex != scrubIndex;
}
