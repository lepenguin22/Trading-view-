import 'package:flutter/material.dart';

import '../state/storage.dart';
import '../theme/app_theme.dart';
import '../utils/analysis_prompt.dart';

/// Where the Claude project an analysis should start in is set.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.storage});

  /// Injected by tests; the real screen uses the shared preferences store.
  final WatchlistStorage? storage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final WatchlistStorage _storage = widget.storage ?? WatchlistStorage();
  final _controller = TextEditingController();
  bool _loading = true;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = await _storage.loadClaudeProjectUrl();
    if (!mounted) return;
    setState(() {
      _controller.text = url ?? '';
      _loading = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final text = _controller.text.trim();

    // An empty field means "forget it", which is a valid choice rather than a
    // mistake: analyses then start in a new chat.
    if (text.isEmpty) {
      await _storage.saveClaudeProjectUrl('');
      if (!mounted) return;
      setState(() {
        _error = null;
        _saved = 'Cleared. Analyses will start in a new chat.';
      });
      return;
    }

    final parsed = parseClaudeProjectUrl(text);
    if (parsed == null) {
      setState(() {
        _error =
            'That is not a Claude project link. Open the project in Claude '
            'and copy the address — it looks like '
            'claude.ai/project/<id>.';
        _saved = null;
      });
      return;
    }

    await _storage.saveClaudeProjectUrl(parsed.toString());
    if (!mounted) return;
    setState(() {
      _controller.text = parsed.toString();
      _error = null;
      _saved = 'Saved. Analyses will start in this project.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                Text(
                  'Analysis project',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Run framework analysis opens Claude with the prompt ready. '
                  'Paste a project link here and it opens that project '
                  'instead, so an analysis starts where the framework and its '
                  'history already are.',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: c.text, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Claude project link',
                    hintText: 'https://claude.ai/project/…',
                    labelStyle: TextStyle(color: c.textMuted),
                    filled: true,
                    fillColor: c.card,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                  ),
                  onChanged: (_) {
                    if (_error != null || _saved != null) {
                      setState(() {
                        _error = null;
                        _saved = null;
                      });
                    }
                  },
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: c.danger,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                if (_saved != null) ...[
                  const SizedBox(height: 10),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _saved!,
                      style: TextStyle(color: c.up, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Claude has no documented way to open a new chat already '
                  'inside a project, so the button lands on the project and '
                  'the prompt is on your clipboard to paste. If a future '
                  'Claude fills it in for you, it will start working on its '
                  'own — nothing here needs changing.',
                  style: TextStyle(
                    color: c.textFaint,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
    );
  }
}
