/// A checklist score as the sheet states it: a mark and the scale it was out
/// of, e.g. 12 out of 17.
///
/// The scale is carried rather than assumed. The analysis framework scores
/// financials out of 19, but not every criterion applies to every company —
/// an ETF has no management to assess, a young company no long record — so a
/// sheet legitimately holds 12/17 beside 15/18. Fixing the denominator would
/// make most real scores unreadable, and normalising them to a common scale
/// would invent a judgement nobody made.
class Score {
  const Score(this.value, this.outOf);

  /// The mark awarded.
  final int value;

  /// What it was out of, as the sheet said.
  final int outOf;

  /// The mark as a proportion, for comparing scores on different scales.
  ///
  /// Null when the scale is zero, which is not a score anyone can read.
  double? get fraction => outOf <= 0 ? null : value / outOf;

  @override
  String toString() => '$value/$outOf';

  @override
  bool operator ==(Object other) =>
      other is Score && other.value == value && other.outOf == outOf;

  @override
  int get hashCode => Object.hash(value, outOf);

  Map<String, dynamic> toJson() => {'value': value, 'outOf': outOf};

  /// Reads a stored score.
  ///
  /// Accepts the bare integer written by builds before scales were carried,
  /// reading it against [fallbackOutOf] — the framework's own scale, which is
  /// what those builds assumed.
  static Score? fromJson(Object? raw, int fallbackOutOf) {
    if (raw is int) return Score.of(raw, fallbackOutOf);
    if (raw is! Map) return null;
    final value = raw['value'];
    final outOf = raw['outOf'];
    if (value is! int || outOf is! int) return null;
    return Score.of(value, outOf);
  }

  /// A score, or null if the pair is not one that can be read.
  ///
  /// A mark above its own scale, a negative mark, or a scale of zero is a
  /// misread cell rather than a score, and inventing a value from it would be
  /// worse than having none.
  static Score? of(int value, int outOf) {
    if (outOf <= 0 || outOf > _maxScale) return null;
    if (value < 0 || value > outOf) return null;
    return Score(value, outOf);
  }
}

/// Above this, a denominator is being misread — a year, a price, a row count.
/// No checklist in the framework runs to a hundred criteria.
const _maxScale = 99;
