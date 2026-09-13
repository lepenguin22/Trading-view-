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

  group('parseClaudeProjectUrl', () {
    test('reads a project link', () {
      expect(
        parseClaudeProjectUrl('https://claude.ai/project/abc123').toString(),
        'https://claude.ai/project/abc123',
      );
    });

    test('accepts what a user actually copies', () {
      // Trailing slash, query junk, www, no scheme, surrounding spaces.
      for (final raw in [
        'https://claude.ai/project/abc123/',
        'https://claude.ai/project/abc123?foo=bar',
        'https://www.claude.ai/project/abc123',
        'claude.ai/project/abc123',
        '  https://claude.ai/project/abc123  ',
      ]) {
        expect(
          parseClaudeProjectUrl(raw).toString(),
          'https://claude.ai/project/abc123',
          reason: 'should read "$raw"',
        );
      }
    });

    test('a chat inside a project resolves to the project', () {
      // Copying the address bar mid-conversation is the likely mistake, and
      // the project is what was meant.
      expect(
        parseClaudeProjectUrl('https://claude.ai/project/abc123/chat/xyz789')
            .toString(),
        'https://claude.ai/project/abc123',
      );
    });

    test('refuses anything that is not a claude.ai project link', () {
      for (final raw in [
        '',
        '   ',
        'https://example.com/project/abc123',
        'https://claude.ai/new',
        'https://claude.ai/chat/abc123',
        'https://claude.ai/project',
        'https://claude.ai/project/',
        'not a url at all',
      ]) {
        expect(
          parseClaudeProjectUrl(raw),
          isNull,
          reason: 'should refuse "$raw"',
        );
      }
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

    test('targets the project when one is set', () {
      final uri = claudeUriFor(
        'Run the framework on NVDA',
        projectUrl: Uri.https('claude.ai', '/project/abc123'),
      );

      expect(uri.path, '/project/abc123');
      expect(uri.queryParameters['q'], 'Run the framework on NVDA');
    });

    test('falls back to a new chat when no project is set', () {
      final uri = claudeUriFor('Run the framework on NVDA');

      expect(uri.path, '/new');
      expect(uri.queryParameters['q'], 'Run the framework on NVDA');
    });

    test('an empty prompt leaves a project link untouched', () {
      expect(
        claudeUriFor(
          '',
          projectUrl: Uri.https('claude.ai', '/project/abc123'),
        ).toString(),
        'https://claude.ai/project/abc123',
      );
    });
  });
}
