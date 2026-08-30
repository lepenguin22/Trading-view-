/// Pure technical-indicator maths.
///
/// Every function returns a list the same length as its input, with null for
/// the leading bars where the indicator has not warmed up yet. Callers can
/// therefore index an indicator by bar without offsetting anything.
library;

/// Simple moving average of [values] over [period] bars.
///
/// Uses a running sum rather than re-adding a window per bar, so a 200 SMA
/// over a long series stays O(n).
List<double?> simpleMovingAverage(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0) return out;

  var sum = 0.0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Wilder's Relative Strength Index over [period] bars.
///
/// This is the original smoothing from Wilder's *New Concepts in Technical
/// Trading Systems*, not a simple average of gains and losses: the seed is the
/// mean of the first [period] changes, and every later bar carries
/// `(previous * (period - 1) + current) / period`. The two agree on the first
/// value and diverge after it, so using the simple form would quietly disagree
/// with every charting package.
List<double?> relativeStrengthIndex(List<double> closes, [int period = 14]) {
  final out = List<double?>.filled(closes.length, null);
  // One extra bar is needed because the first change spans two closes.
  if (period <= 0 || closes.length < period + 1) return out;

  var avgGain = 0.0;
  var avgLoss = 0.0;
  for (var i = 1; i <= period; i++) {
    final delta = closes[i] - closes[i - 1];
    if (delta > 0) {
      avgGain += delta;
    } else {
      avgLoss -= delta;
    }
  }
  avgGain /= period;
  avgLoss /= period;
  out[period] = _rsi(avgGain, avgLoss);

  for (var i = period + 1; i < closes.length; i++) {
    final delta = closes[i] - closes[i - 1];
    final gain = delta > 0 ? delta : 0.0;
    final loss = delta < 0 ? -delta : 0.0;
    avgGain = (avgGain * (period - 1) + gain) / period;
    avgLoss = (avgLoss * (period - 1) + loss) / period;
    out[i] = _rsi(avgGain, avgLoss);
  }
  return out;
}

double _rsi(double avgGain, double avgLoss) {
  if (avgLoss == 0) {
    // The ratio is undefined with no losses. A run of pure gains is the
    // textbook 100, but a dead-flat stretch has no momentum in either
    // direction, and reporting "maximally overbought" for a flat line would
    // be actively misleading — so that degenerate case reads neutral.
    return avgGain == 0 ? 50 : 100;
  }
  if (avgGain == 0) return 0;
  return 100 - 100 / (1 + avgGain / avgLoss);
}

/// The RSI levels conventionally drawn as guides.
const rsiOverbought = 70.0;
const rsiOversold = 30.0;

/// Default RSI lookback.
const rsiPeriod = 14;

/// Moving-average periods overlaid on the price chart, in trading days.
///
/// 200 needs roughly ten months of history before it can be drawn at all, and
/// the chart fetches five years, so it is available for everything but the
/// oldest bars of a newly listed symbol.
const maPeriods = [20, 50, 200];
