import 'package:flutter/material.dart';

import '../models/holding.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// What the portfolio is worth, above its list of holdings.
///
/// One block per currency. Holdings quoted in different currencies are never
/// added together — that needs an exchange rate this app does not have, and a
/// single invented number would be worse than two honest ones.
class PortfolioSummary extends StatelessWidget {
  const PortfolioSummary({super.key, required this.totals});

  final List<PortfolioTotal> totals;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Nothing valued means no quantities in the sheet, or no quotes yet.
    // Showing a zero would claim the portfolio is worth nothing.
    if (totals.isEmpty) return const SizedBox.shrink();

    final unpriced = totals.fold(0, (sum, t) => sum + t.unpriced);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Sizes to its content: this sits in a list item today, but a bounded
        // parent would otherwise stretch it down the screen.
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < totals.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 10),
            ],
            _Total(total: totals[i], showCurrency: totals.length > 1),
          ],
          if (unpriced > 0) ...[
            const SizedBox(height: 8),
            Text(
              unpriced == 1
                  ? '1 holding not counted — no share count or no price yet'
                  : '$unpriced holdings not counted — no share count or no '
                        'price yet',
              style: TextStyle(color: c.textFaint, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.total, required this.showCurrency});

  final PortfolioTotal total;

  /// Names the currency when more than one is in play. With a single currency
  /// the symbol on the figure already says it.
  final bool showCurrency;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final change = total.dayChange;
    final color = c.trend(change);
    final percent = total.dayChangePercent;

    final label =
        'Portfolio value '
        '${formatValue(total.value, total.currency)}'
        '${showCurrency ? ' ${total.currency}' : ''}, '
        '${change >= 0 ? 'up' : 'down'} '
        '${formatValue(change.abs(), total.currency)} today'
        '${total.hasGain ? ', ${total.gain >= 0 ? 'up' : 'down'} '
                  '${formatValue(total.gain.abs(), total.currency)} since bought'
                  '${total.gainCoversEverything ? '' : ', over '
                            '${total.invested} of ${total.priced} holdings'}' : ''}';

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                showCurrency ? 'Value (${total.currency})' : 'Value',
                style: TextStyle(color: c.textMuted, fontSize: 12),
              ),
              const Spacer(),
              Text(
                total.priced == 1 ? '1 holding' : '${total.priced} holdings',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  formatValue(total.value, total.currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tabularFigures.copyWith(
                    color: c.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                percent == null
                    ? formatSignedValue(change, total.currency)
                    : '${formatSignedValue(change, total.currency)} '
                          '(${formatPercent(percent)})',
                maxLines: 1,
                style: tabularFigures.copyWith(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ' today',
                style: TextStyle(color: c.textFaint, fontSize: 12),
              ),
            ],
          ),
          if (total.hasGain) _gain(context, total),
        ],
      ),
    );
  }

  /// The return since purchase, under the day's move.
  ///
  /// Named "since bought" rather than left to sit beside the day change, which
  /// is a different question over a different period; two unlabelled signed
  /// numbers in a column would be read as one.
  Widget _gain(BuildContext context, PortfolioTotal total) {
    final c = context.colors;
    final percent = total.gainPercent;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Text(
            'Since bought',
            style: TextStyle(color: c.textMuted, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              percent == null
                  ? formatSignedValue(total.gain, total.currency)
                  : '${formatSignedValue(total.gain, total.currency)} '
                        '(${formatPercent(percent)})',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tabularFigures.copyWith(
                color: c.trend(total.gain),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // A return measured over fewer holdings than the value above it must
          // say so, or it reads as the whole portfolio's.
          if (!total.gainCoversEverything) ...[
            const SizedBox(width: 6),
            Text(
              'of ${total.invested}',
              style: TextStyle(color: c.textFaint, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
