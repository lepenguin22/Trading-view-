import 'package:flutter_test/flutter_test.dart';
import 'package:ticker/utils/analysis_prompt.dart';

void main() {
  group('analysisPromptFor', () {
    test('uses a wording the framework lists as a trigger', () {
      // "Run the framework on X" is one of the skill's own trigger phrases. A
      // paraphrase risks a plain answer instead of the structured deep dive.
      expect(analysisPromptFor('NVDA'), 'Run the framework on NVDA');
    });

    test('normalises the ticker the way the rest of the app does', () {
      expect(analysisPromptFor('nvda'), 'Run the framework on NVDA');
      expect(analysisPromptFor('  tsm  '), 'Run the framework on TSM');
    });

    test('keeps exchange suffixes and class dashes intact', () {
      expect(analysisPromptFor('VOD.L'), 'Run the framework on VOD.L');
      expect(analysisPromptFor('BRK-B'), 'Run the framework on BRK-B');
    });

    test('carries nothing but the ticker', () {
      // Position size would anchor the analysis to a holding already owned,
      // and the chart's technicals answer a question the framework asks for
      // itself. Both were considered and left out.
      final prompt = analysisPromptFor('AAPL');

      expect(prompt.split(' ').length, 5);
      expect(prompt, isNot(contains(r'$')));
      expect(prompt.toLowerCase(), isNot(contains('shares')));
      expect(prompt.toLowerCase(), isNot(contains('rsi')));
    });

    test('an empty symbol produces nothing to send', () {
      expect(analysisPromptFor(''), '');
      expect(analysisPromptFor('   '), '');
    });
  });

  group('claudeUriFor', () {
    test('carries the prompt as a query parameter', () {
      final uri = claudeUriFor('Run the framework on NVDA');

      expect(uri.scheme, 'https');
      expect(uri.host, 'claude.ai');
      expect(uri.path, '/new');
      expect(uri.queryParameters['q'], 'Run the framework on NVDA');
    });

    test('escapes a prompt so the link stays valid', () {
      // Spaces and any punctuation must survive the round trip rather than
      // truncating the link.
      final uri = claudeUriFor('Run the framework on BRK-B');

      expect(uri.toString(), isNot(contains(' ')));
      expect(
        Uri.parse(uri.toString()).queryParameters['q'],
        'Run the framework on BRK-B',
      );
    });

    test('an empty prompt still gives a usable Claude link', () {
      // Worth opening Claude even with nothing to carry; the button copies
      // the prompt regardless.
      expect(claudeUriFor('').toString(), claudeNewChat);
    });
  });
}
