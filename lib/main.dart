import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/watchlist_screen.dart';
import 'state/watchlist.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const TickerApp());
}

class TickerApp extends StatelessWidget {
  const TickerApp({super.key, this.createModel});

  /// Overridden in tests to inject a model whose feed is faked.
  final WatchlistModel Function()? createModel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      // start() hydrates from storage and begins polling; it is kicked off
      // here rather than in a widget's initState so a rebuild cannot restart
      // it.
      create: (_) => (createModel?.call() ?? WatchlistModel())..start(),
      child: MaterialApp(
        title: 'Ticker',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        // Follows the OS appearance setting.
        themeMode: ThemeMode.system,
        home: const WatchlistScreen(),
      ),
    );
  }
}
