/// Builds the message that starts a framework analysis in Claude.
///
/// The app cannot run the analysis itself: the framework's financial criteria
/// need multi-year statements, and several of its moat criteria are outright
/// qualitative. This hands the job over, already addressed to a symbol.
library;

/// Where a fresh Claude conversation lives.
///
/// The prompt is passed as a query parameter, which fills the composer where
/// that is supported. It is only ever a convenience: the prompt is put on the
/// clipboard first, so the handoff still works if this link merely opens
/// Claude without carrying the text.
const claudeNewChat = 'https://claude.ai/new';

/// The message to send about [symbol].
///
/// Phrased as "Run the framework on X" because that is one of the wordings the
/// analysis framework itself lists as a trigger — a paraphrase risks a plain
/// answer instead of the structured deep dive.
///
/// Deliberately carries nothing but the ticker. Position size and the chart's
/// current technicals were considered and left out: the first anchors the
/// analysis to a position already held, and the second answers a question the
/// framework asks for itself.
String analysisPromptFor(String symbol) {
  final ticker = symbol.trim().toUpperCase();
  if (ticker.isEmpty) return '';
  return 'Run the framework on $ticker';
}

/// A link to Claude carrying [prompt], or the bare new-chat URL when there is
/// nothing to carry.
Uri claudeUriFor(String prompt) {
  if (prompt.isEmpty) return Uri.parse(claudeNewChat);
  return Uri.parse(claudeNewChat).replace(queryParameters: {'q': prompt});
}
