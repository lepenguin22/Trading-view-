import '../utils/indicators.dart';

/// A moving-average crossover the chart can mark.
///
/// Each one is a pair of series compared bar by bar. The labels are carried
/// here rather than derived, because the conventional names ("Golden Cross")
/// carry meaning that "50 crossed 200" does not.
class CrossoverSpec {
  const CrossoverSpec({
    required this.id,
    required this.label,
    required this.fastPeriod,
    required this.slowPeriod,
    required this.upLabel,
    required this.downLabel,
  });

  /// Stable key, used to remember which crossovers are switched on.
  final String id;

  /// Short name for the legend chip.
  final String label;

  /// The faster moving average, or null to compare the closing price itself
  /// against [slowPeriod].
  final int? fastPeriod;

  final int slowPeriod;

  /// What an upward and a downward crossing are called.
  final String upLabel;
  final String downLabel;

  String labelFor(CrossDirection direction) =>
      direction == CrossDirection.up ? upLabel : downLabel;

  /// Periods this crossover needs computed before it can be drawn.
  List<int> get periods => [?fastPeriod, slowPeriod];
}

/// The crossovers offered on the detail chart.
///
/// Deliberately short. Every extra pair adds markers to the same price line,
/// and a chart carrying every crossover at once says less than one carrying
/// two.
const crossoverSpecs = <CrossoverSpec>[
  CrossoverSpec(
    id: 'ma50x200',
    label: '50/200',
    fastPeriod: 50,
    slowPeriod: 200,
    upLabel: 'Golden Cross',
    downLabel: 'Death Cross',
  ),
  CrossoverSpec(
    id: 'closex200',
    label: 'Price/200',
    fastPeriod: null,
    slowPeriod: 200,
    upLabel: 'Price crossed above MA200',
    downLabel: 'Price crossed below MA200',
  ),
];

/// Finds every crossing [spec] describes.
///
/// Returns nothing rather than throwing when a period it needs has not been
/// computed: a crossover whose moving average is missing is one the chart
/// simply cannot draw yet.
List<Crossing> crossingsFor(
  CrossoverSpec spec, {
  required List<double> closes,
  required Map<int, List<double?>> movingAverages,
}) {
  final slow = movingAverages[spec.slowPeriod];
  if (slow == null) return const [];

  final period = spec.fastPeriod;
  final List<double?>? fast = period == null
      ? List<double?>.from(closes)
      : movingAverages[period];
  if (fast == null) return const [];

  return crossings(fast, slow);
}
