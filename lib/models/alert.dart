/// Which side of the threshold the user wants to hear about.
enum AlertDirection {
  above('rises to or above', 'Above'),
  below('falls to or below', 'Below');

  const AlertDirection(this.phrase, this.label);

  /// Used in the notification body, e.g. "AAPL rises to or above $200.00".
  final String phrase;

  /// Button label in the create-alert sheet.
  final String label;
}

/// A one-shot price alert on a single symbol.
///
/// Alerts fire once and then disarm themselves ([enabled] false, [triggeredAt]
/// set) rather than re-notifying on every subsequent check — an alert that
/// stayed armed would fire every 15 minutes for as long as the price sat past
/// the threshold. The user can re-arm one from the alerts screen.
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.direction,
    required this.threshold,
    required this.currency,
    required this.createdAt,
    this.enabled = true,
    this.triggeredAt,
  });

  final String id;
  final String symbol;
  final AlertDirection direction;
  final double threshold;

  /// Currency the threshold is expressed in, captured from the quote when the
  /// alert was created so a notification can format it without a fetch.
  final String currency;

  final int createdAt;
  final bool enabled;

  /// Epoch ms when this alert last fired, or null if it never has.
  final int? triggeredAt;

  bool get hasTriggered => triggeredAt != null;

  /// Whether [price] satisfies this alert's condition.
  ///
  /// This is a level test, not a crossing test: it does not require having
  /// previously seen a price on the other side of the threshold. A crossing
  /// test would silently never fire for an alert set on the wrong side, which
  /// is a worse failure than firing immediately.
  bool isMet(double price) {
    if (!price.isFinite) return false;
    return switch (direction) {
      AlertDirection.above => price >= threshold,
      AlertDirection.below => price <= threshold,
    };
  }

  PriceAlert copyWith({
    bool? enabled,
    int? triggeredAt,
    bool clearTriggered = false,
  }) {
    return PriceAlert(
      id: id,
      symbol: symbol,
      direction: direction,
      threshold: threshold,
      currency: currency,
      createdAt: createdAt,
      enabled: enabled ?? this.enabled,
      triggeredAt: clearTriggered ? null : (triggeredAt ?? this.triggeredAt),
    );
  }

  factory PriceAlert.fromJson(Map<String, dynamic> json) => PriceAlert(
    id: json['id'] as String,
    symbol: json['symbol'] as String,
    direction: AlertDirection.values.firstWhere(
      (d) => d.name == json['direction'],
      orElse: () => AlertDirection.above,
    ),
    threshold: (json['threshold'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'USD',
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    enabled: json['enabled'] as bool? ?? true,
    triggeredAt: (json['triggeredAt'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'symbol': symbol,
    'direction': direction.name,
    'threshold': threshold,
    'currency': currency,
    'createdAt': createdAt,
    'enabled': enabled,
    'triggeredAt': triggeredAt,
  };
}

/// Picks out the alerts that [prices] satisfy.
///
/// Shared by the foreground refresh and the background worker so both decide
/// identically. Disabled and already-triggered alerts are skipped, as are
/// symbols missing from [prices] — a failed fetch must not be read as "the
/// condition was not met".
List<PriceAlert> firedAlerts(
  List<PriceAlert> alerts,
  Map<String, double> prices,
) {
  final fired = <PriceAlert>[];
  for (final alert in alerts) {
    if (!alert.enabled || alert.hasTriggered) continue;
    final price = prices[alert.symbol];
    if (price == null) continue;
    if (alert.isMet(price)) fired.add(alert);
  }
  return fired;
}

/// The distinct symbols the given alerts need prices for.
Set<String> symbolsToWatch(List<PriceAlert> alerts) => {
  for (final a in alerts)
    if (a.enabled && !a.hasTriggered) a.symbol,
};
