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

/// Normalises a pasted Claude project link, or returns null if it is not one.
///
/// Accepts what a user actually copies out of the address bar — extra query
/// parameters, a trailing slash, a chat opened inside the project. Anything
/// that is not a claude.ai project link is refused rather than opened: sending
/// the button somewhere arbitrary would be worse than falling back to a new
/// chat.
Uri? parseClaudeProjectUrl(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final uri = Uri.tryParse(text.startsWith('http') ? text : 'https://$text');
  if (uri == null) return null;
  if (uri.host != 'claude.ai' && uri.host != 'www.claude.ai') return null;

  final segments = [
    for (final s in uri.pathSegments)
      if (s.isNotEmpty) s,
  ];
  final index = segments.indexOf('project');
  if (index == -1 || index + 1 >= segments.length) return null;

  final id = segments[index + 1];
  if (id.isEmpty) return null;

  // Rebuilt rather than passed through, so a link copied from a chat inside
  // the project still points at the project itself.
  return Uri.https('claude.ai', '/project/$id');
}

/// A link to Claude carrying [prompt].
///
/// Targets [projectUrl] when one is set, so an analysis starts where the
/// framework and its history already live. The prompt is attached as a query
/// parameter either way: it fills the composer where that is supported, and is
/// harmlessly ignored where it is not — the button copies the prompt to the
/// clipboard first, which is what actually guarantees the handoff.
Uri claudeUriFor(String prompt, {Uri? projectUrl}) {
  final base = projectUrl ?? Uri.parse(claudeNewChat);
  if (prompt.isEmpty) return base;
  return base.replace(queryParameters: {'q': prompt});
}
