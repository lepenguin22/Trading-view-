import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/projection.dart';

const _height = 200.0;
const _padding = 8.0;

/// A stacked area of the four pots over the projection.
///
/// Stacked rather than four lines: the pots sum to a total, and the total is
/// the number the projection is for. Separate lines would show each pot but
/// leave the reader adding them by eye.
///
/// CPF's three accounts sit underneath because they are the part that is not
/// chosen — they happen out of salary whatever else is decided — so the
/// investing band reads as what the plan adds on top. Within CPF the order is
/// Ordinary, Special, MediSave: the order of the allocation tables, and of how
/// freely the money can be used.
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
                    'MediSave and investments stacked over '
                    '${(points.length - 1) ~/ 12} years, ending at '
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
        const SizedBox(height: 8),
        // A legend is always present, so identity is never carried by colour
        // alone. Top of the stack first, matching the order they are read off
        // the chart. It wraps rather than ellipsising: four keys do not fit a
        // narrow phone on one line, and a cut-off legend is worse than two.
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _Key(color: c.pots[3], label: 'Investments'),
            _Key(color: c.pots[2], label: 'MediSave'),
            _Key(color: c.pots[1], label: 'Special'),
            _Key(color: c.pots[0], label: 'Ordinary'),
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
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

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
      ],
    );
  }
}

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

  /// Bottom to top: Ordinary, Special, MediSave, investments.
  final List<Color> colors;
  final Color gridColor;
  final Color ruleColor;
  final Color surface;
  final int? scrubbed;

  /// Each band's upper edge, as a running total. Stacking is done here rather
  /// than in the model: the model holds balances, and what they add up to is a
  /// question this chart asks, not a fact about the money.
  static final _levels = <double Function(ProjectionPoint)>[
    (p) => p.oa,
    (p) => p.oa + p.sa,
    (p) => p.oa + p.sa + p.ma,
    (p) => p.total,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final maxTotal = points.fold<double>(
      0,
      (m, p) => p.total > m ? p.total : m,
    );
    if (maxTotal <= 0) return;

    final plotHeight = size.height - _padding * 2;
    double x(int i) => size.width * i / (points.length - 1);
    double y(double value) =>
        _padding + plotHeight - (value / maxTotal) * plotHeight;

    // Recessive gridlines: reference, not content.
    final grid = Paint()
      ..strokeWidth = 1
      ..color = gridColor;
    for (var i = 0; i <= 4; i++) {
      final gy = _padding + plotHeight * i / 4;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), grid);
    }

    // Painted bottom upwards, each band cut away from the one below it.
    for (var band = 0; band < _levels.length; band++) {
      _fill(
        canvas,
        size,
        x,
        y,
        _levels[band],
        band == 0 ? null : _levels[band - 1],
        colors[band],
      );
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
      // A surface ring keeps the dot legible over any band.
      final dot = Offset(mx, y(points[marker].total));
      canvas.drawCircle(dot, 5, Paint()..color = surface);
      canvas.drawCircle(dot, 3.5, Paint()..color = colors.last);
    }
  }

  /// Fills between [below] and [top], and strokes the top edge.
  ///
  /// The lower boundary is lifted 2px so stacked segments carry a surface gap
  /// between them; without it the whole stack reads as one shape.
  void _fill(
    Canvas canvas,
    Size size,
    double Function(int) x,
    double Function(double) y,
    double Function(ProjectionPoint) top,
    double Function(ProjectionPoint)? below,
    Color color,
  ) {
    final path = Path()..moveTo(x(0), y(top(points.first)));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(x(i), y(top(points[i])));
    }

    final area = Path.from(path);
    if (below == null) {
      area
        ..lineTo(x(points.length - 1), size.height)
        ..lineTo(x(0), size.height)
        ..close();
    } else {
      for (var i = points.length - 1; i >= 0; i--) {
        area.lineTo(x(i), y(below(points[i])) - 2);
      }
      area.close();
    }

    canvas.drawPath(area, Paint()..color = color.withValues(alpha: 0.22));
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
