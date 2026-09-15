import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/projection.dart';

const _height = 200.0;
const _padding = 8.0;

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
                  size: Size(width, _height),
                  painter: _ProjectionPainter(
                    points: points,
                    colors: c.pots,
                    gridColor: c.border,
                    ruleColor: c.textFaint,
                    surface: c.card,
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
    required this.scrubbed,
  });

  final List<ProjectionPoint> points;

  /// One per entry in [_series], in the same order.
  final List<Color> colors;
  final Color gridColor;
  final Color ruleColor;
  final Color surface;
  final int? scrubbed;

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

    final plotHeight = size.height - _padding * 2;
    double x(int i) => size.width * i / (points.length - 1);
    double y(double value) =>
        _padding + plotHeight - (value / maxValue) * plotHeight;

    // Recessive gridlines: reference, not content.
    final grid = Paint()
      ..strokeWidth = 1
      ..color = gridColor;
    for (var i = 0; i <= 4; i++) {
      final gy = _padding + plotHeight * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    for (var i = 0; i < _series.length; i++) {
      _line(canvas, x, y, _series[i].of, colors[i]);
    }

    final marker = scrubbed;
    if (marker != null && marker < points.length) {
      final mx = x(marker);
      canvas.drawLine(
        Offset(mx, 0),
        Offset(mx, size.height),
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
