import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/alerts.dart';
import '../state/watchlist.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/quote_row.dart';
import 'alerts_screen.dart';
import 'detail_screen.dart';
import 'import_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// Which of the two lists a tab is showing.
///
/// They are kept apart deliberately: the watchlist is what the user chose to
/// follow, the portfolio is what a spreadsheet says they own, and an import
/// rewrites the second without touching the first.
enum SymbolList {
  watchlist('Watchlist'),
  portfolio('Portfolio');

  const SymbolList(this.label);

  final String label;
}

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    // The action button differs per tab, so a tab change has to rebuild.
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  SymbolList get _current => SymbolList.values[_tabs.index];

  Future<void> _openSearch() => Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const SearchScreen(),
    ),
  );

  Future<void> _openImport() =>
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const ImportScreen()));

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final model = context.watch<WatchlistModel>();
    final armed = context.watch<AlertsModel>().armedCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Portfolio Alerts'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const AlertsScreen())),
            tooltip: armed == 0 ? 'Price alerts' : 'Price alerts, $armed armed',
            icon: Badge(
              isLabelVisible: armed > 0,
              label: Text('$armed'),
              backgroundColor: c.accent,
              child: const Icon(Icons.notifications_none),
            ),
          ),
          // An overflow menu rather than more icons: the title is long enough
          // that a third action crowds a narrow phone.
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (value) {
              if (value == 'import') {
                _openImport();
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Import portfolio')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: c.text,
          unselectedLabelColor: c.textMuted,
          indicatorColor: c.accent,
          tabs: [
            for (final list in SymbolList.values)
              Tab(
                text: list == SymbolList.watchlist
                    ? '${list.label} (${model.symbols.length})'
                    : '${list.label} (${model.portfolio.length})',
              ),
          ],
        ),
      ),
      floatingActionButton: _current == SymbolList.watchlist
          ? FloatingActionButton(
              onPressed: _openSearch,
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
              tooltip: 'Add a symbol to your watchlist',
              child: const Icon(Icons.add),
            )
          : FloatingActionButton(
              onPressed: _openImport,
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
              tooltip: 'Import portfolio from a spreadsheet',
              child: const Icon(Icons.upload_file_outlined),
            ),
      body: model.hydrating
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                for (final list in SymbolList.values)
                  _SymbolListView(
                    list: list,
                    onAdd: list == SymbolList.watchlist
                        ? _openSearch
                        : _openImport,
                  ),
              ],
            ),
    );
  }
}

class _SymbolListView extends StatelessWidget {
  const _SymbolListView({required this.list, required this.onAdd});

  final SymbolList list;
  final VoidCallback onAdd;

  /// Long press opens the row's actions; there is no room for them inline.
  void _showRowActions(BuildContext context, String symbol) {
    final model = context.read<WatchlistModel>();
    final c = context.colors;
    final isWatchlist = list == SymbolList.watchlist;
    final index = model.symbols.indexOf(symbol);

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
            // Reordering only applies to the watchlist: the portfolio's order
            // comes from the sheet and an import would undo it.
            if (isWatchlist && index > 0)
              ListTile(
                leading: Icon(Icons.arrow_upward, color: c.text),
                title: Text('Move up', style: TextStyle(color: c.text)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  model.moveSymbol(symbol, -1);
                },
              ),
            if (isWatchlist && index >= 0 && index < model.symbols.length - 1)
              ListTile(
                leading: Icon(Icons.arrow_downward, color: c.text),
                title: Text('Move down', style: TextStyle(color: c.text)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  model.moveSymbol(symbol, 1);
                },
              ),
            if (!isWatchlist && !model.has(symbol))
              ListTile(
                leading: Icon(Icons.playlist_add, color: c.text),
                title: Text(
                  'Also add to watchlist',
                  style: TextStyle(color: c.text),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  model.addSymbol(symbol);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: c.danger),
              title: Text(
                isWatchlist ? 'Remove from watchlist' : 'Remove from portfolio',
                style: TextStyle(color: c.danger),
              ),
              subtitle: isWatchlist
                  ? null
                  : Text(
                      'Comes back on the next import unless removed from the '
                      'sheet',
                      style: TextStyle(color: c.textFaint, fontSize: 12),
                    ),
              onTap: () {
                Navigator.pop(sheetContext);
                if (isWatchlist) {
                  model.removeSymbol(symbol);
                } else {
                  model.removeFromPortfolio(symbol);
                }
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
    final symbols = list == SymbolList.watchlist
        ? model.symbols
        : model.portfolio;

    return RefreshIndicator(
      onRefresh: model.refresh,
      color: c.accent,
      backgroundColor: c.card,
      child: symbols.isEmpty
          ? _EmptyState(list: list, onAdd: onAdd)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: symbols.length + 1,
              separatorBuilder: (_, index) =>
                  SizedBox(height: index == 0 ? 0 : 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return model.lastUpdated == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            model.marketOpen
                                ? formatUpdatedAt(model.lastUpdated)
                                : '${formatUpdatedAt(model.lastUpdated)} · '
                                      'market closed',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: c.textFaint, fontSize: 12),
                          ),
                        );
                }

                final symbol = symbols[index - 1];
                return QuoteRow(
                  symbol: symbol,
                  quote: model.quotes[symbol],
                  error: model.errors[symbol],
                  hasAlert: context.watch<AlertsModel>().hasArmed(symbol),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(symbol: symbol),
                    ),
                  ),
                  onLongPress: () => _showRowActions(context, symbol),
                );
              },
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.list, required this.onAdd});

  final SymbolList list;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final watchlist = list == SymbolList.watchlist;

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
                    watchlist ? 'No symbols yet' : 'No holdings yet',
                    style: TextStyle(
                      color: c.text,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    watchlist
                        ? 'Add a company or fund to start tracking its share '
                              'price.'
                        : 'Import your holdings from a spreadsheet published '
                              'as CSV. They stay separate from your watchlist.',
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
                    child: Text(
                      watchlist ? 'Add a symbol' : 'Import portfolio',
                    ),
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
