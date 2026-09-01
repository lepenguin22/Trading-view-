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
  AlertKind kind = AlertKind.price,
  String? crossoverId,
  int createdAt = 1,
}) => PriceAlert(
  id: id,
  symbol: symbol,
  kind: kind,
  crossoverId: crossoverId,
  direction: direction,
  threshold: threshold,
  currency: 'USD',
  createdAt: createdAt,
  enabled: enabled,
  triggeredAt: triggeredAt,
);
