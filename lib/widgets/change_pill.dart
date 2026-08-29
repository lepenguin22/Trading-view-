import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Tinted percentage badge. Colour alone never carries the meaning — the sign
/// is always in the text too, for colour-blind readers.
class ChangePill extends StatelessWidget {
  const ChangePill({
    super.key,
    required this.changePercent,
    this.large = false,
  });

  final double changePercent;

  /// Larger pill for the detail screen header.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.trend(changePercent);

    return Container(
      constraints: BoxConstraints(minWidth: large ? 92 : 74),
      padding: EdgeInsets.symmetric(
        horizontal: large ? 10 : 8,
        vertical: large ? 5 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(large ? 9 : 7),
      ),
      child: Text(
        formatPercent(changePercent),
        textAlign: TextAlign.center,
        style: tabularFigures.copyWith(
          color: color,
          fontSize: large ? 16 : 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
