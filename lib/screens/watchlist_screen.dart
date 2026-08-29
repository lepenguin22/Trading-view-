import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/watchlist.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/quote_row.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

class WatchlistScreen extends StatelessWidget {
  const WatchlistScreen({super.key});

  Future<void> _openSearch(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SearchScreen(),
      ),
    );
  }

  /// Long press opens the row's actions; there is no room for them inline.
  void _showRowActions(BuildContext context, String symbol) {
    final model = context.read<WatchlistModel>();
    final index = model.symbols.indexOf(symbol);
    final c = context.colors;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.card,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                symbol,
                style: TextStyle(
                  color: c.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (index > 0)
              ListTile(
                leading: Icon(Icons.arrow_upward, color: c.text),
                title: Text('Move up', style: TextStyle(color: c.text)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  model.moveSymbol(symbol, -1);
                },
              ),
            if (index >= 0 && index < model.symbols.length - 1)
              ListTile(
                leading: Icon(Icons.arrow_downward, color: c.text),
                title: Text('Move down', style: TextStyle(color: c.text)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  model.moveSymbol(symbol, 1);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text(
                'Remove from watchlist',
                style: TextStyle(color: c.danger),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                model.removeSymbol(symbol);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<WatchlistModel>();

    return Scaffold(
      appBar: AppBar(title: const Text('Watchlist')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openSearch(context),
        backgroundColor: c.accent,
        foregroundColor: Colors.white,
        tooltip: 'Add a symbol to your watchlist',
        child: const Icon(Icons.add),
      ),
      body: model.hydrating
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: model.refresh,
              color: c.accent,
              backgroundColor: c.card,
              child: model.symbols.isEmpty
                  ? _EmptyState(onAdd: () => _openSearch(context))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: model.symbols.length + 1,
                      separatorBuilder: (_, index) =>
                          SizedBox(height: index == 0 ? 0 : 8),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return model.lastUpdated == null
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    formatUpdatedAt(model.lastUpdated),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: c.textFaint,
                                      fontSize: 12,
                                    ),
                                  ),
                                );
                        }

                        final symbol = model.symbols[index - 1];
                        return QuoteRow(
                          symbol: symbol,
                          quote: model.quotes[symbol],
                          error: model.errors[symbol],
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DetailScreen(symbol: symbol),
                            ),
                          ),
                          onLongPress: () => _showRowActions(context, symbol),
                        );
                      },
                    ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // A scroll view even though it fits, so pull-to-refresh still works here.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'No symbols yet',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a company or fund to start tracking its share price.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.textMuted,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: onAdd,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Add a symbol'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
