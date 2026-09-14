import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/models/holding.dart';
import 'package:ticker/models/score.dart';

void main() {
  group('Score', () {
    test('keeps the scale it was given', () {
      const score = Score(12, 17);

      expect(score.value, 12);
      expect(score.outOf, 17);
      expect(score.toString(), '12/17');
    });

    test('compares scores on different scales by proportion', () {
      // 12/17 is the better score, and only the proportion says so. Nothing
      // rescales the stored marks to find that out.
      expect(
        const Score(12, 17).fraction,
        greaterThan(const Score(12, 19).fraction!),
      );
    });

    test('refuses a pair that is not a score', () {
      expect(Score.of(20, 17), isNull, reason: 'mark above its own scale');
      expect(Score.of(-1, 17), isNull, reason: 'negative mark');
      expect(Score.of(5, 0), isNull, reason: 'scale of zero');
      expect(Score.of(5, -3), isNull, reason: 'negative scale');
      expect(Score.of(5, 2026), isNull, reason: 'a year, not a checklist');
      expect(Score.of(0, 17), const Score(0, 17));
      expect(Score.of(17, 17), const Score(17, 17));
    });
  });

  group('Holding score storage', () {
    test('round trips a score with its scale', () {
      const holding = Holding(
        symbol: 'UNH',
        shares: 16,
        financialScore: Score(12, 17),
        moatScore: Score(8, 14),
      );
      final back = Holding.fromJson(holding.toJson())!;

      expect(back.financialScore, const Score(12, 17));
      expect(back.moatScore, const Score(8, 14));
    });

    test('reads a bare number written before scales were carried', () {
      // Builds before this stored the mark alone, against the framework's own
      // scale. A portfolio saved by one of those must still load rather than
      // losing every score it holds.
      final back = Holding.fromJson({
        'symbol': 'AAPL',
        'financialScore': 14,
        'moatScore': 11,
      })!;

      expect(back.financialScore, const Score(14, 19));
      expect(back.moatScore, const Score(11, 14));
    });

    test('refuses a stored score that is not one', () {
      final back = Holding.fromJson({
        'symbol': 'AAPL',
        'financialScore': {'value': 30, 'outOf': 17},
        'moatScore': {'value': 5},
      })!;

      expect(back.financialScore, isNull);
      expect(back.moatScore, isNull);
      expect(back.hasScores, isFalse);
    });
  });
}
