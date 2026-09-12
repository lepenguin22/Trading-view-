import 'package:flutter/material.dart';

import '../models/holding.dart';
import '../models/types.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/portfolio_csv.dart' show financialScoreMax, moatScoreMax;
import 'change_pill.dart';
import 'sparkline.dart';

const _sparkWidth = 56.0;
const _sparkHeight = 28.0;

/// One watchlist row: identity on the left, sparkline and price on the right.
class QuoteRow extends StatelessWidget {
  const QuoteRow({
    super.key,
    required this.symbol,
    required this.quote,
    required this.error,
    required this.onTap,
    required this.onLongPress,
    this.hasAlert = false,
    this.shares,
    this.costPerShare,
    this.holding,
  });

  final String symbol;
  final Quote? quote;

  /// Message from the last refresh, if this symbol failed.
  final String? error;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  /// Shows a small bell beside the symbol when an armed alert is set on it.
  final bool hasAlert;

  /// Shares held, on the portfolio list. Null on the watchlist, and null for
  /// a holding whose sheet did not state a quantity — in which case the row
  /// shows no value rather than implying one.
  final double? shares;

  /// Average price paid, when the sheet has a cost column. Drives the return
  /// shown beside the position's value.
  final double? costPerShare;

  /// The portfolio entry, when this row is a holding. Carries the checklist
  /// scores; null on the watchlist.
  final Holding? holding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = quote;
    final change = q?.change ?? 0;
    final color = c.trend(change);

    // A cached quote from a previous session is still worth showing; it is
    // just labelled so nobody mistakes it for a live price.
    final stale = error != null && q != null;

    final held = shares;
    final value = q == null || held == null ? null : held * q.price;
    final paid = costPerShare;
    final cost = held == null || paid == null ? null : held * paid;
    final gain = value == null || cost == null ? null : value - cost;
    final gainPercent = gain == null || cost == null || cost == 0
        ? null
        : gain / cost * 100;

    final label = q != null
        ? '$symbol, ${q.name}, ${formatPrice(q.price, q.currency)}, '
              '${change >= 0 ? 'up' : 'down'} '
              '${q.changePercent.abs().toStringAsFixed(2)} percent'
              '${value == null ? '' : ', holding worth '
                        '${formatValue(value, q.currency)}'}'
              '${gain == null ? '' : ', ${gain >= 0 ? 'up' : 'down'} '
                        '${formatValue(gain.abs(), q.currency)} since bought'}'
              '${stale ? ', last known price' : ''}'
              '${hasAlert ? ', price alert set' : ''}'
        : '$symbol, ${error ?? 'loading'}';

    return Semantics(
      button: true,
      label: label,
      hint: 'Opens the price chart. Long press for options.',
      excludeSemantics: true,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(14),
          highlightColor: c.cardPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              symbol,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          if (hasAlert) ...[
                            const SizedBox(width: 5),
                            Icon(
                              Icons.notifications_active,
                              size: 13,
                              color: c.textFaint,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        q?.name ?? error ?? 'Loading…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                      if (held != null) ...[
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                value == null
                                    ? '${formatShares(held)} shares'
                                    : '${formatShares(held)} shares · '
                                          '${formatValue(value, q!.currency)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tabularFigures.copyWith(
                                  color: c.textFaint,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            // The return since purchase is coloured because it
                            // is the number with a good and a bad direction;
                            // the value beside it has neither.
                            if (gain != null && gainPercent != null) ...[
                              Text(
                                ' · ',
                                style: TextStyle(
                                  color: c.textFaint,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                formatPercent(gainPercent),
                                maxLines: 1,
                                style: tabularFigures.copyWith(
                                  color: stale ? c.textFaint : c.trend(gain),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      if (holding?.hasScores ?? false) ...[
                        const SizedBox(height: 4),
                        _Scores(holding: holding!),
                      ],
                    ],
                  ),
                ),
                if (q != null) ...[
                  const SizedBox(width: 10),
                  Sparkline(
                    points: q.spark,
                    width: _sparkWidth,
                    height: _sparkHeight,
                    color: stale ? c.textFaint : color,
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatPrice(q.price, q.currency),
                        maxLines: 1,
                        style: tabularFigures.copyWith(
                          color: c.text,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatChange(q.change),
                            maxLines: 1,
                            style: tabularFigures.copyWith(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          ChangePill(changePercent: q.changePercent),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The analysis checklist scores, and how old they are.
///
/// The age is never omitted when it is known: a score is a snapshot of a
/// judgement, and one from six months ago may predate two earnings reports.
/// Presenting it without its date would be the way this misleads.
class _Scores extends StatelessWidget {
  const _Scores({required this.holding});

  final Holding holding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scoredAt = holding.scoredAt;
    final stale = scoredAt != null && isScoreStale(scoredAt);

    final parts = <String>[
      if (holding.financialScore != null)
        'Fin ${holding.financialScore}/$financialScoreMax',
      if (holding.moatScore != null) 'Moat ${holding.moatScore}/$moatScoreMax',
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            parts.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tabularFigures.copyWith(
              color: c.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            // A date the sheet had but could not be read says so, rather than
            // leaving a score looking timeless.
            scoredAt == null
                ? 'no date'
                : stale
                ? '${formatScoredAt(scoredAt)} · stale'
                : formatScoredAt(scoredAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              // Staleness is said in words and shown by contrast, never by
              // colour: red already means a loss on this row, and a stale date
              // in the same red would read as a bad number rather than an old
              // one. Amber is no better — it sits too close to the down-red
              // under common colour vision deficiencies.
              color: stale ? c.textMuted : c.textFaint,
              fontSize: 11.5,
              fontStyle: FontStyle.italic,
              fontWeight: stale ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
