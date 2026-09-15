import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/chart.dart';
import '../utils/format.dart';
import '../utils/projection.dart';

const _height = 200.0;
const _padding = 8.0;

/// Room under the plot for the year labels.
const _xAxisHeight = 16.0;

/// Between the widest y label and the plot's left edge.
const _axisGap = 6.0;

/// One line per pot over the projection, each from a common zero.
///
/// Unstacked, and that is the point. Stacked, every line is a running total,
/// so a small account sitting on a large one draws *higher* than the large
/// one — the Special Account, a third the size of the Ordinary Account, had
/// its line above it. Band thickness carried the value and nobody reads a
/// chart that way. Four pots that are meant to be compared want a shared
/// baseline, where height is the value and the eye can rank them.
///
/// The total is not lost by unstacking: it is the headline figure above the
/// plot, which is where it was actually being read from anyway.
class ProjectionChart extends StatefulWidget {
  const ProjectionChart({
    super.key,
    required this.points,
    required this.currency,
  });

  final List<ProjectionPoint> points;
  final String currency;

  @override
  State<ProjectionChart> createState() => _ProjectionChartState();
}

class _ProjectionChartState extends State<ProjectionChart> {
  int? _scrubbed;

  void _scrubTo(double x, double width) {
    if (widget.points.length < 2 || width <= 0) return;
    final fraction = (x / width).clamp(0.0, 1.0);
    final index = (fraction * (widget.points.length - 1)).round();
    if (index != _scrubbed) setState(() => _scrubbed = index);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final points = widget.points;
    if (points.length < 2) return const SizedBox(height: _height);

    final selected = points[_scrubbed ?? points.length - 1];
    final isLatest = _scrubbed == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The readout is above the plot rather than a floating tooltip: on a
        // phone a finger covers the point it is describing.
        _Readout(
          point: selected,
          currency: widget.currency,
          trailing: isLatest ? 'at the end' : 'drag to scan',
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => _scrubTo(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) =>
                  _scrubTo(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => setState(() => _scrubbed = null),
              onTapUp: (_) => setState(() => _scrubbed = null),
              onTapCancel: () => setState(() => _scrubbed = null),
              child: Semantics(
                label:
                    'Projection chart. Ordinary Account, Special Account, '
                    'MediSave and investments, each plotted over '
                    '${(points.length - 1) ~/ 12} years. Together they end at '
                    '${formatValue(points.last.total, widget.currency)}.',
                excludeSemantics: true,
                child: CustomPaint(
                  size: Size(width, _height + _xAxisHeight),
                  painter: _ProjectionPainter(
                    points: points,
                    colors: c.pots,
                    gridColor: c.border,
                    ruleColor: c.textFaint,
                    surface: c.card,
                    labelColor: c.textFaint,
                    currency: widget.currency,
                    scrubbed: _scrubbed,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        // The legend carries each line's value at the scrubbed point, so the
        // lines can be ranked without measuring them against the gridlines.
        // It is always present, so identity is never colour alone, and it
        // wraps rather than ellipsising — four keys do not fit one line on a
        // narrow phone, and a cut-off legend is worse than two rows.
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            for (var i = _series.length - 1; i >= 0; i--)
              _Key(
                color: c.pots[i],
                label: _series[i].label,
                value: formatCompactValue(
                  _series[i].of(selected),
                  widget.currency,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({
    required this.point,
    required this.currency,
    required this.trailing,
  });

  final ProjectionPoint point;
  final String currency;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final years = point.month ~/ 12;
    final months = point.month % 12;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            formatValue(point.total, currency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tabularFigures.copyWith(
              color: c.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          months == 0
              ? 'year $years · $trailing'
              : 'year $years, month $months',
          style: TextStyle(color: c.textFaint, fontSize: 12),
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        // Text stays in ink; the swatch beside it carries the identity.
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 12)),
        const SizedBox(width: 5),
        Text(
          value,
          style: tabularFigures.copyWith(
            color: c.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// The four pots, in the order they are drawn and listed.
const _series = <({String label, double Function(ProjectionPoint) of})>[
  (label: 'Ordinary', of: _oa),
  (label: 'Special', of: _sa),
  (label: 'MediSave', of: _ma),
  (label: 'Investments', of: _invested),
];

double _oa(ProjectionPoint p) => p.oa;
double _sa(ProjectionPoint p) => p.sa;
double _ma(ProjectionPoint p) => p.ma;
double _invested(ProjectionPoint p) => p.invested;

class _ProjectionPainter extends CustomPainter {
  const _ProjectionPainter({
    required this.points,
    required this.colors,
    required this.gridColor,
    required this.ruleColor,
    required this.surface,
    required this.labelColor,
    required this.currency,
    required this.scrubbed,
  });

  final List<ProjectionPoint> points;

  /// One per entry in [_series], in the same order.
  final List<Color> colors;
  final Color gridColor;
  final Color ruleColor;
  final Color surface;
  final Color labelColor;
  final String currency;
  final int? scrubbed;

  /// Lays out one axis label, ready to measure or paint.
  TextPainter _label(String text) => TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: labelColor, fontSize: axisLabelSize),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    // The scale is the largest single pot, not the sum: nothing is stacked, so
    // scaling to a total nobody plots would flatten every line into the floor.
    var maxValue = 0.0;
    for (final p in points) {
      for (final s in _series) {
        final v = s.of(p);
        if (v > maxValue) maxValue = v;
      }
    }
    if (maxValue <= 0) return;

    // Gridlines at round money values rather than at even fractions of the
    // data's own range: an axis reading 250k, 500k, 750k is one a reader can
    // use, where 308k, 616k, 925k is only a division of the maximum.
    final ticks = niceTicks(0, maxValue);
    final labels = {
      for (final t in ticks) t: _label(formatCompactValue(t, currency)),
    };

    // Measured, not guessed: "$1.2M" and "$950k" are different widths, and a
    // fixed gutter would clip one or waste space on the other.
    var gutter = 0.0;
    for (final l in labels.values) {
      if (l.width > gutter) gutter = l.width;
    }
    if (gutter > 0) gutter += _axisGap;

    final plotWidth = size.width - gutter;
    final plotHeight = _height - _padding * 2;
    if (plotWidth <= 0) return;

    double x(int i) => gutter + plotWidth * i / (points.length - 1);
    double y(double value) =>
        _padding + plotHeight - (value / maxValue) * plotHeight;

    // Recessive gridlines: reference, not content.
    final grid = Paint()
      ..strokeWidth = 1
      ..color = gridColor;
    for (final tick in ticks) {
      final gy = y(tick);
      canvas.drawLine(Offset(gutter, gy), Offset(size.width, gy), grid);
      labels[tick]!.paint(
        canvas,
        Offset(gutter - _axisGap - labels[tick]!.width, gy - axisLabelSize),
      );
    }

    _paintYears(canvas, size, x, plotWidth);

    for (var i = 0; i < _series.length; i++) {
      _line(canvas, x, y, _series[i].of, colors[i]);
    }

    final marker = scrubbed;
    if (marker != null && marker < points.length) {
      final mx = x(marker);
      canvas.drawLine(
        Offset(mx, 0),
        Offset(mx, _height),
        Paint()
          ..strokeWidth = 1
          ..color = ruleColor,
      );
      // A dot on every line, since every line is now being read. The surface
      // ring keeps one legible where two lines cross.
      for (var i = 0; i < _series.length; i++) {
        final dot = Offset(mx, y(_series[i].of(points[marker])));
        canvas.drawCircle(dot, 5, Paint()..color = surface);
        canvas.drawCircle(dot, 3.5, Paint()..color = colors[i]);
      }
    }
  }

  /// Year labels under the plot, at a spacing the width can hold.
  ///
  /// Every fifth year where they fit, then every tenth, and so on — a label
  /// per year on a twenty-year projection would overlap into a smear, which
  /// is worse than no axis at all.
  void _paintYears(
    Canvas canvas,
    Size size,
    double Function(int) x,
    double plotWidth,
  ) {
    final years = (points.length - 1) ~/ 12;
    if (years <= 0) return;

    final sample = _label('$years');
    // Each label needs its own width plus a gap; the step is the first of
    // 1, 2, 5, 10, 20… that clears it. Measured against the plot rather than
    // the whole canvas, since the gutter is not somewhere labels can go.
    final room = plotWidth / (sample.width + 14);
    var step = 1;
    for (final candidate in [1, 2, 5, 10, 20, 25, 50]) {
      step = candidate;
      if (years / candidate <= room) break;
    }

    for (var year = 0; year <= years; year += step) {
      final label = _label(year == 0 ? 'now' : '$year');
      // Centred on its year, then pulled back inside the canvas at either
      // end — the first would otherwise sit under the y-axis labels and the
      // last would hang off the right edge.
      var left = x(year * 12) - label.width / 2;
      if (left + label.width > size.width) left = size.width - label.width;
      if (left < 0) left = 0;
      label.paint(canvas, Offset(left, _height + 2));
    }
  }

  void _line(
    Canvas canvas,
    double Function(int) x,
    double Function(double) y,
    double Function(ProjectionPoint) value,
    Color color,
  ) {
    final path = Path()..moveTo(x(0), y(value(points.first)));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(value(points[i])));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_ProjectionPainter old) =>
      old.points != points || old.scrubbed != scrubbed || old.colors != colors;
}
