import 'package:flutter/material.dart';

import '../models/types.dart';
import '../theme/app_theme.dart';
import '../utils/indicators.dart';

const _paneHeight = 64.0;

/// The RSI oscillator, drawn in its own pane below the price chart.
///
/// Deliberately not overlaid on price with a second y-axis: RSI is bounded
/// 0–100 and price is not, and putting two scales on one plot invites reading
/// crossings that do not exist.
class RsiPane extends StatelessWidget {
  const RsiPane({
    super.key,
    required this.values,
    required this.window,
    this.height = _paneHeight,
  });

  /// Aligned to the raw candles, with null before the indicator warms up.
  final List<double?> values;

  /// The same slice the price chart is drawing, so the two plots stay aligned
  /// bar for bar as the user zooms and pans.
  final ChartWindow window;

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = values.length >= window.end && window.count > 0
        ? values.sublist(window.start, window.end)
        : const <double?>[];
    final latest = visible.lastWhere((v) => v != null, orElse: () => null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'RSI ($rsiPeriod)',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              latest != null ? latest.toStringAsFixed(1) : '—',
              style: tabularFigures.copyWith(color: c.text, fontSize: 12),
            ),
            if (latest != null) ...[
              const SizedBox(width: 6),
              Text(
                latest >= rsiOverbought
                    ? 'overbought'
                    : latest <= rsiOversold
                    ? 'oversold'
                    : '',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) => CustomPaint(
              size: Size(constraints.maxWidth, height),
              painter: _RsiPainter(
                values: visible,
                line: c.accent,
                guide: c.border,
                guideText: c.textFaint,
                over: c.down,
                under: c.up,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RsiPainter extends CustomPainter {
  const _RsiPainter({
    required this.values,
    required this.line,
    required this.guide,
    required this.guideText,
    required this.over,
    required this.under,
  });

  final List<double?> values;
  final Color line;
  final Color guide;
  final Color guideText;
  final Color over;
  final Color under;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0) return;

    // The scale is fixed 0–100 rather than fitted to the data: the whole point
    // of RSI is where it sits against 30 and 70, which an auto-fitted axis
    // would destroy.
    double yFor(double v) => size.height * (1 - (v.clamp(0, 100)) / 100);

    for (final level in [rsiOverbought, rsiOversold]) {
      final y = yFor(level);
      final paint = Paint()
        ..strokeWidth = 1
        ..color = guide;
      const dash = 3.0;
      const gap = 4.0;
      for (var x = 0.0; x < size.width; x += dash + gap) {
        canvas.drawLine(
          Offset(x, y),
          Offset((x + dash).clamp(0.0, size.width), y),
          paint,
        );
      }

      final label = TextPainter(
        text: TextSpan(
          text: level.toStringAsFixed(0),
          style: TextStyle(color: guideText, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(2, y - label.height - 1));
    }

    final xs = [
      for (var i = 0; i < values.length; i++)
        values.length == 1 ? 0.0 : (i / (values.length - 1)) * size.width,
    ];

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = line;

    Path? path;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      final point = Offset(xs[i], yFor(v));
      if (path == null) {
        path = Path()..moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    if (path != null) canvas.drawPath(path, paint);

    // A dot in the zone colour marks the latest reading, so the state reads at
    // a glance without tracing the line to its end.
    for (var i = values.length - 1; i >= 0; i--) {
      final v = values[i];
      if (v == null) continue;
      if (v >= rsiOverbought || v <= rsiOversold) {
        canvas.drawCircle(
          Offset(xs[i], yFor(v)),
          3,
          Paint()..color = v >= rsiOverbought ? over : under,
        );
      }
      break;
    }
  }

  @override
  bool shouldRepaint(_RsiPainter old) =>
      old.values != values || old.line != line;
}
