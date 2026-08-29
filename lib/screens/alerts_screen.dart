import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../background/alert_worker.dart';
import '../models/alert.dart';
import '../state/alerts.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'detail_screen.dart';

/// Every alert across every symbol, armed ones first.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<AlertsModel>();

    final alerts = model.alerts.toList()
      ..sort((a, b) {
        final aArmed = a.enabled && !a.hasTriggered;
        final bArmed = b.enabled && !b.hasTriggered;
        if (aArmed != bArmed) return aArmed ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: alerts.isEmpty
          ? _empty(c)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
              itemCount: alerts.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == alerts.length) return _footer(c);
                return _AlertTile(alert: alerts[index]);
              },
            ),
    );
  }

  Widget _empty(AppColors c) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 40, color: c.textFaint),
          const SizedBox(height: 12),
          Text(
            'No alerts yet',
            style: TextStyle(
              color: c.text,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open a symbol and tap "Add price alert" to be notified when '
            'it crosses a price you choose.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, fontSize: 15, height: 1.4),
          ),
        ],
      ),
    ),
  );

  Widget _footer(AppColors c) => Padding(
    padding: const EdgeInsets.fromLTRB(6, 16, 6, 0),
    child: Text(
      'Alerts are checked about every '
      '${alertCheckInterval.inMinutes} minutes in the background, and '
      'immediately whenever the app is open. An alert fires once, then '
      'switches off — turn it back on to arm it again.',
      style: TextStyle(color: c.textFaint, fontSize: 12, height: 1.45),
    ),
  );
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final PriceAlert alert;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.read<AlertsModel>();
    final armed = alert.enabled && !alert.hasTriggered;
    final tint = alert.direction == AlertDirection.above ? c.up : c.down;

    return Dismissible(
      key: ValueKey(alert.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 18),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(Icons.delete_outline, color: c.danger),
      ),
      onDismissed: (_) => model.remove(alert.id),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailScreen(symbol: alert.symbol),
            ),
          ),
          borderRadius: BorderRadius.circular(13),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.border),
            ),
            padding: const EdgeInsets.fromLTRB(13, 10, 6, 10),
            child: Row(
              children: [
                Icon(
                  alert.direction == AlertDirection.above
                      ? Icons.trending_up
                      : Icons.trending_down,
                  color: armed ? tint : c.textFaint,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        alert.symbol,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${alert.direction.phrase} '
                        '${formatPrice(alert.threshold, alert.currency)}',
                        style: TextStyle(color: c.textMuted, fontSize: 13),
                      ),
                      if (alert.hasTriggered) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Fired ${formatUpdatedAt(alert.triggeredAt).replaceFirst('Updated ', '')}',
                          style: TextStyle(color: c.textFaint, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Switch(
                  value: armed,
                  activeThumbColor: c.accent,
                  onChanged: (v) => model.setEnabled(alert.id, v),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
