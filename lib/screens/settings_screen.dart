import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/valuation_store.dart';
import '../theme/app_theme.dart';

/// Where the Financial Modeling Prep API key is entered.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: context.read<ValuationModel>().apiKey,
  );
  bool _obscured = true;
  bool _saved = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    await context.read<ValuationModel>().setApiKey(_controller.text);
    if (!mounted) return;
    setState(() => _saved = true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            'Fair value',
            style: TextStyle(
              color: c.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'A discounted cash flow estimate is shown on each stock, from '
            'Financial Modeling Prep. Their free plan allows a few hundred '
            'requests a day, which is ample: a value is fetched only when you '
            'open a stock, and then kept for a week.',
            style: TextStyle(color: c.textMuted, fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscured,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(color: c.text, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'API key',
              labelStyle: TextStyle(color: c.textMuted),
              filled: true,
              fillColor: c.card,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscured = !_obscured),
                icon: Icon(
                  _obscured ? Icons.visibility_off : Icons.visibility,
                  color: c.textFaint,
                ),
                tooltip: _obscured ? 'Show key' : 'Hide key',
              ),
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
              if (_saved) setState(() => _saved = false);
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
              child: const Text('Save key'),
            ),
          ),
          if (_saved) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              child: Text(
                _controller.text.trim().isEmpty
                    ? 'Key cleared. Fair values are switched off.'
                    : 'Key saved. Open a stock to fetch its fair value.',
                style: TextStyle(color: c.up, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Getting a key',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Register at financialmodelingprep.com and copy the API key '
                  'from your dashboard. The free tier needs no card.',
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'The key is stored on this device only. It is not shared, '
                  'and it is never sent anywhere except to Financial Modeling '
                  'Prep. Anyone who can read the app’s data can read it, '
                  'so use a key you are willing to rotate.',
                  style: TextStyle(
                    color: c.textFaint,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'A DCF is a projection, not a measurement. Two providers modelling '
            'the same company will disagree, sometimes by a lot. Treat it as '
            'one opinion among several.',
            style: TextStyle(color: c.textFaint, fontSize: 12.5, height: 1.45),
          ),
        ],
      ),
    );
  }
}
