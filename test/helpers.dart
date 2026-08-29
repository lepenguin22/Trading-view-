import 'package:ticker/models/alert.dart';
import 'package:ticker/notifications/notifications.dart';

/// Records what would have been posted instead of touching the platform.
class FakeNotifier extends AlertNotifier {
  final fired = <PriceAlert>[];
  final prices = <double>[];

  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showAlert(PriceAlert alert, double price) async {
    fired.add(alert);
    prices.add(price);
  }
}

PriceAlert testAlert({
  required String id,
  String symbol = 'AAPL',
  AlertDirection direction = AlertDirection.above,
  required double threshold,
  bool enabled = true,
  int? triggeredAt,
}) => PriceAlert(
  id: id,
  symbol: symbol,
  direction: direction,
  threshold: threshold,
  currency: 'USD',
  createdAt: 1,
  enabled: enabled,
  triggeredAt: triggeredAt,
);
