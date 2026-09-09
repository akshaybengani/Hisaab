import 'product.dart';

/// A product's current position. [onHand] is always derived from purchases,
/// deliveries, and adjustments, never read from a stored counter. See spec-27
/// dec-3.
class StockLevel {
  const StockLevel({
    required this.product,
    required this.onHand,
    required this.purchased,
    required this.delivered,
    required this.adjusted,
  });

  final Product product;
  final int onHand;
  final int purchased;
  final int delivered;
  final int adjusted;

  /// What the stock on hand is worth at the current price. A valuation, not a
  /// cost basis, which is the honest thing to call it.
  int get valuePaise => onHand * product.currentPricePaise;

  bool get isOut => onHand <= 0;
}

/// One movement in a product's history, with the running figure after it, so
/// any number on the stock card can be traced to the rows behind it.
class StockMovement {
  const StockMovement({
    required this.date,
    required this.label,
    required this.qtyDelta,
    required this.runningOnHand,
    this.detail,
  });

  final DateTime date;
  final String label;
  final int qtyDelta;
  final int runningOnHand;
  final String? detail;
}
