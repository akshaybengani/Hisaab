import '../models/models.dart';

/// The stock arithmetic, as pure functions with no I/O.
///
/// On hand is always derived. There is no quantity column on `products`, so
/// the plus and minus stepper writes adjustment rows rather than a counter.
/// See spec-27 dec-3.
abstract final class StockMath {
  /// Purchased minus delivered plus adjustments, for one product.
  /// Verified by ac-13.
  static StockLevel level({
    required Product product,
    required List<PurchaseItem> purchaseItems,
    required List<DeliveryItem> deliveryItems,
    required List<StockAdjustment> adjustments,
  }) {
    throw UnimplementedError('owned by lane/math');
  }

  /// The delta a recount has to store so on hand ends up equal to
  /// [countedOnHand]. Never the counted figure itself, so the movement
  /// history still reconciles. Verified by ac-15.
  static int recountDelta({
    required int currentOnHand,
    required int countedOnHand,
  }) {
    throw UnimplementedError('owned by lane/math');
  }

  /// One product's movements oldest first, each carrying the running on-hand
  /// figure after it, so any number on the stock card can be traced.
  static List<StockMovement> history({
    required List<PurchaseItem> purchaseItems,
    required List<DeliveryItem> deliveryItems,
    required List<StockAdjustment> adjustments,
    required Map<int, DateTime> purchaseDates,
    required Map<int, DateTime> deliveryDates,
  }) {
    throw UnimplementedError('owned by lane/math');
  }

  /// Pending requests collapsed into one line per product, for the
  /// consolidated shopping list. Verified by ac-27.
  static List<ShoppingListLine> shoppingList({
    required List<ProductRequest> pending,
    required Map<int, Product> productsById,
  }) {
    throw UnimplementedError('owned by lane/math');
  }
}
