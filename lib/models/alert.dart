import 'crossover.dart';
import '../utils/indicators.dart';

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

/// What an alert watches.
enum AlertKind {
  /// The live price against a threshold.
  price,

  /// The 14-period RSI against a level, typically 30 or 70.
  rsi,

  /// A named crossover firing in a given direction.
  crossover,
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
    this.kind = AlertKind.price,
    this.crossoverId,
    this.enabled = true,
    this.triggeredAt,
  });

  final String id;
  final String symbol;

  /// What this alert watches. Older stored alerts have no kind and load as
  /// [AlertKind.price], which is what they were.
  final AlertKind kind;

  /// For [AlertKind.crossover], which [CrossoverSpec] to watch. Null otherwise.
  final String? crossoverId;

  final AlertDirection direction;

  /// The level for a price or RSI alert. Unused by a crossover alert, whose
  /// condition is the crossing itself.
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

  /// The crossover this alert watches, or null if it does not watch one.
  CrossoverSpec? get crossover {
    final id = crossoverId;
    if (kind != AlertKind.crossover || id == null) return null;
    for (final spec in crossoverSpecs) {
      if (spec.id == id) return spec;
    }
    // A stored alert naming a crossover this build no longer offers. It stays
    // in the list, visible and deletable, rather than firing on nothing.
    return null;
  }

  /// Whether [inputs] satisfy this alert.
  ///
  /// Price and RSI are level tests, matching [isMet]: they do not require
  /// having seen the other side first, because an alert set on the wrong side
  /// would otherwise never fire at all.
  ///
  /// A crossover is not a level, so it is an event test instead — it fires on
  /// a crossing dated at or after the alert was created. Creating a Golden
  /// Cross alert therefore does not fire on a cross from last month, and a
  /// cross that happened while the phone was off still fires at the next
  /// check rather than being missed.
  bool isMetBy(AlertInputs inputs) {
    switch (kind) {
      case AlertKind.price:
        final price = inputs.price;
        return price != null && isMet(price);

      case AlertKind.rsi:
        final rsi = inputs.rsi;
        if (rsi == null || !rsi.isFinite) return false;
        return switch (direction) {
          AlertDirection.above => rsi >= threshold,
          AlertDirection.below => rsi <= threshold,
        };

      case AlertKind.crossover:
        final spec = crossover;
        if (spec == null) return false;
        final wanted = direction == AlertDirection.above
            ? CrossDirection.up
            : CrossDirection.down;
        for (final event in inputs.crossings) {
          if (event.crossoverId != spec.id) continue;
          if (event.direction != wanted) continue;
          if (event.at >= createdAt) return true;
        }
        return false;
    }
  }

  /// The condition alone, for a row that already names the symbol.
  String condition(String Function(double) formatPrice) {
    switch (kind) {
      case AlertKind.price:
        return '${direction.phrase} ${formatPrice(threshold)}';
      case AlertKind.rsi:
        final side = direction == AlertDirection.above ? 'above' : 'below';
        return 'RSI $side ${threshold.toStringAsFixed(0)}';
      case AlertKind.crossover:
        final spec = crossover;
        // A stored alert naming a crossover this build no longer offers.
        // Saying so beats a blank row the user cannot account for.
        if (spec == null) return 'Crossover no longer available';
        return spec.labelFor(
          direction == AlertDirection.above
              ? CrossDirection.up
              : CrossDirection.down,
        );
    }
  }

  /// The whole sentence, for a notification body.
  String describe(String Function(double) formatPrice) =>
      kind == AlertKind.price
      ? '$symbol ${condition(formatPrice)}'
      : '$symbol: ${condition(formatPrice)}';

  PriceAlert copyWith({
    bool? enabled,
    int? triggeredAt,
    bool clearTriggered = false,
  }) {
    return PriceAlert(
      id: id,
      symbol: symbol,
      kind: kind,
      crossoverId: crossoverId,
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
    // Absent in anything stored before indicator alerts existed, and those
    // were all price alerts.
    kind: AlertKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => AlertKind.price,
    ),
    crossoverId: json['crossoverId'] as String?,
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
    'kind': kind.name,
    if (crossoverId != null) 'crossoverId': crossoverId,
    'direction': direction.name,
    'threshold': threshold,
    'currency': currency,
    'createdAt': createdAt,
    'enabled': enabled,
    'triggeredAt': triggeredAt,
  };
}

/// One crossing that happened, and when.
typedef CrossingEvent = ({
  String crossoverId,
  CrossDirection direction,
  int at,
});

/// What one symbol's alerts are evaluated against.
///
/// [rsi] and [crossings] are only ever populated where daily history was
/// fetched. Everything absent is genuinely unknown, and an alert needing it
/// simply does not fire this round — an unfetched indicator must never be read
/// as "the condition was not met".
class AlertInputs {
  const AlertInputs({this.price, this.rsi, this.crossings = const []});

  final double? price;

  /// Latest 14-period RSI.
  final double? rsi;

  /// Crossings found in the fetched history, each dated by its bar (epoch ms).
  final List<CrossingEvent> crossings;
}

/// Picks out the alerts that [inputs] satisfy.
///
/// Shared by the foreground refresh and the background worker so both decide
/// identically. Disabled and already-triggered alerts are skipped, as are
/// symbols missing from [inputs] — a failed fetch must not be read as "the
/// condition was not met".
List<PriceAlert> firedAlerts(
  List<PriceAlert> alerts,
  Map<String, AlertInputs> inputs,
) {
  final fired = <PriceAlert>[];
  for (final alert in alerts) {
    if (!alert.enabled || alert.hasTriggered) continue;
    final symbol = inputs[alert.symbol];
    if (symbol == null) continue;
    if (alert.isMetBy(symbol)) fired.add(alert);
  }
  return fired;
}

/// Wraps a plain price map as inputs, for callers that have only quotes.
Map<String, AlertInputs> priceInputs(Map<String, double> prices) => {
  for (final entry in prices.entries)
    entry.key: AlertInputs(price: entry.value),
};

/// The distinct symbols the given alerts need data for.
Set<String> symbolsToWatch(List<PriceAlert> alerts) => {
  for (final a in alerts)
    if (a.enabled && !a.hasTriggered) a.symbol,
};

/// The symbols whose alerts need daily history, not just a quote.
///
/// Kept separate so a portfolio of price alerts still costs one cheap request
/// per symbol; only the symbols actually carrying an indicator alert pay for
/// history.
Set<String> symbolsNeedingHistory(List<PriceAlert> alerts) => {
  for (final a in alerts)
    if (a.enabled && !a.hasTriggered && a.kind != AlertKind.price) a.symbol,
};
