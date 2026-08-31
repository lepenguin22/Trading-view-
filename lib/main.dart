import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';

import 'api/yahoo.dart';
import 'background/alert_worker.dart';
import 'screens/watchlist_screen.dart';
import 'state/alerts.dart';
import 'state/watchlist.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Registering the dispatcher is what lets a scheduled task wake the app;
  // the schedule itself is (de)registered by AlertsModel as alerts come and
  // go. A failure here must not stop the app launching — the user still gets
  // a working watchlist, just no background alerts.
  try {
    await Workmanager().initialize(alertCallbackDispatcher);
  } catch (error, stack) {
    debugPrint('Background alerts unavailable: $error\n$stack');
  }

  runApp(const TickerApp());
}

class TickerApp extends StatelessWidget {
  const TickerApp({super.key, this.createApi, this.createAlerts});

  /// Overridden in tests to supply an API over a faked HTTP client.
  final YahooApi Function()? createApi;

  /// Overridden in tests to avoid touching real notifications or scheduling.
  final AlertsModel Function()? createAlerts;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // One client for the whole app: the watchlist poll, the detail chart
        // and search all share it, so connections are reused rather than a
        // fresh pool being opened per screen.
        Provider<YahooApi>(
          create: (_) => createApi?.call() ?? YahooApi(),
          dispose: (_, api) => api.dispose(),
          lazy: false,
        ),
        // start() hydrates from storage and begins polling; it is kicked off
        // here rather than in a widget's initState so a rebuild cannot restart
        // it.
        ChangeNotifierProvider(
          create: (_) => (createAlerts?.call() ?? AlertsModel())..start(),
        ),
        ChangeNotifierProxyProvider<AlertsModel, WatchlistModel>(
          create: (context) =>
              WatchlistModel(api: context.read<YahooApi>())..start(),
          // Handing the watchlist a reference to the alerts model lets a
          // foreground refresh fire due alerts immediately, rather than
          // leaving them to the next background pass.
          update: (_, alerts, watchlist) =>
              watchlist!..onQuotes = alerts.evaluateAgainst,
        ),
      ],
      child: MaterialApp(
        title: 'Portfolio Alerts',
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
