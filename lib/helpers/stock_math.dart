import '../constants.dart';
import '../models/models.dart';
import 'money.dart';

/// The stock arithmetic, as pure functions with no I/O.
///
/// On hand is always derived. There is no quantity column on `products`, so
/// the plus and minus stepper writes adjustment rows rather than a counter.
/// See spec-27 dec-3.
///
/// Nothing here clamps a figure at zero. A negative on hand is real
/// information: it means a purchase was never recorded.
abstract final class StockMath {
  /// Purchased minus delivered plus adjustments, for one product.
  /// Verified by ac-13.
  ///
  /// Rows for another product are ignored, so a caller may pass everything it
  /// has. A product with no id yet has no movements to find.
  static StockLevel level({
    required Product product,
    required List<PurchaseItem> purchaseItems,
    required List<DeliveryItem> deliveryItems,
    required List<StockAdjustment> adjustments,
  }) {
    final int? productId = product.id;
    int purchased = 0;
    int delivered = 0;
    int adjusted = 0;
    if (productId != null) {
      for (final PurchaseItem item in purchaseItems) {
        if (item.productId == productId) purchased += item.qty;
      }
      for (final DeliveryItem item in deliveryItems) {
        if (item.productId == productId) delivered += item.qty;
      }
      for (final StockAdjustment adjustment in adjustments) {
        if (adjustment.productId == productId) adjusted += adjustment.qtyDelta;
      }
    }
    return StockLevel(
      product: product,
      onHand: purchased - delivered + adjusted,
      purchased: purchased,
      delivered: delivered,
      adjusted: adjusted,
    );
  }

  /// The delta a recount has to store so on hand ends up equal to
  /// [countedOnHand]. Never the counted figure itself, so the movement
  /// history still reconciles. Verified by ac-15.
  static int recountDelta({
    required int currentOnHand,
    required int countedOnHand,
  }) => countedOnHand - currentOnHand;

  /// One product's movements oldest first, each carrying the running on-hand
  /// figure after it, so any number on the stock card can be traced.
  ///
  /// The caller passes the rows for one product, plus the date of each
  /// purchase and delivery those rows belong to. A row whose date is not in
  /// those maps is left out, because a movement with no date cannot be placed
  /// in a history. Stock arriving on a day is counted before stock leaving
  /// it, so a running figure never dips through a purchase that landed the
  /// same morning.
  static List<StockMovement> history({
    required List<PurchaseItem> purchaseItems,
    required List<DeliveryItem> deliveryItems,
    required List<StockAdjustment> adjustments,
    required Map<int, DateTime> purchaseDates,
    required Map<int, DateTime> deliveryDates,
  }) {
    final List<_Move> moves = <_Move>[];
    for (final PurchaseItem item in purchaseItems) {
      final DateTime? date = item.purchaseId == null
          ? null
          : purchaseDates[item.purchaseId];
      if (date == null) continue;
      moves.add(
        _Move(
          date: date,
          label: 'Purchased',
          qtyDelta: item.qty,
          detail: 'Unit cost ${Money.format(item.unitCostPaise)}',
        ),
      );
    }
    for (final DeliveryItem item in deliveryItems) {
      final DateTime? date = item.deliveryId == null
          ? null
          : deliveryDates[item.deliveryId];
      if (date == null) continue;
      moves.add(
        _Move(
          date: date,
          label: 'Delivered',
          qtyDelta: -item.qty,
          detail: 'Unit price ${Money.format(item.unitPricePaise)}',
        ),
      );
    }
    for (final StockAdjustment adjustment in adjustments) {
      moves.add(
        _Move(
          date: adjustment.date,
          label: describeReason(adjustment.reason),
          qtyDelta: adjustment.qtyDelta,
          detail: _trimmed(adjustment.note),
        ),
      );
    }

    final List<StockMovement> movements = <StockMovement>[];
    int running = 0;
    for (final _Move move in _stableByDate(moves)) {
      running += move.qtyDelta;
      movements.add(
        StockMovement(
          date: move.date,
          label: move.label,
          qtyDelta: move.qtyDelta,
          runningOnHand: running,
          detail: move.detail,
        ),
      );
    }
    return movements;
  }

  /// Pending requests collapsed into one line per product, for the
  /// consolidated shopping list. Verified by ac-27.
  ///
  /// [ShoppingListLine.requestCount] counts people, not rows, so someone who
  /// asked twice still reads as one person asking. Anything past the pending
  /// stage, and anything for a product no longer in the catalogue, is left
  /// off.
  static List<ShoppingListLine> shoppingList({
    required List<ProductRequest> pending,
    required Map<int, Product> productsById,
  }) {
    final Map<int, int> qtyByProduct = <int, int>{};
    final Map<int, Set<int>> peopleByProduct = <int, Set<int>>{};
    for (final ProductRequest request in pending) {
      if (request.status != RequestStatus.pending) continue;
      if (!productsById.containsKey(request.productId)) continue;
      qtyByProduct[request.productId] =
          (qtyByProduct[request.productId] ?? 0) + request.qty;
      (peopleByProduct[request.productId] ??= <int>{}).add(request.personId);
    }

    final List<ShoppingListLine> lines = <ShoppingListLine>[
      for (final MapEntry<int, int> entry in qtyByProduct.entries)
        ShoppingListLine(
          productId: entry.key,
          productName: productsById[entry.key]!.name,
          unitLabel: productsById[entry.key]!.unitLabel,
          qty: entry.value,
          requestCount: peopleByProduct[entry.key]!.length,
        ),
    ];
    lines.sort(
      (ShoppingListLine a, ShoppingListLine b) => a.productName
          .toLowerCase()
          .compareTo(b.productName.toLowerCase()),
    );
    return lines;
  }

  /// What a stock reason reads as on the stock card.
  static String describeReason(StockReason reason) => switch (reason) {
    StockReason.personalUse => 'Personal use',
    StockReason.recount => 'Recount',
    StockReason.damaged => 'Damaged',
    StockReason.gifted => 'Gifted',
    StockReason.manual => 'Manual',
  };

  /// Sorts by date without disturbing the order of movements that share one,
  /// so the purchase, delivery, adjustment order the caller was built in
  /// survives a same-day tie. Dart's own sort makes no such promise.
  static List<_Move> _stableByDate(List<_Move> moves) {
    final List<_Move> sorted = List<_Move>.of(moves);
    for (int i = 1; i < sorted.length; i++) {
      final _Move current = sorted[i];
      int slot = i - 1;
      while (slot >= 0 && sorted[slot].date.isAfter(current.date)) {
        sorted[slot + 1] = sorted[slot];
        slot--;
      }
      sorted[slot + 1] = current;
    }
    return sorted;
  }

  static String? _trimmed(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// One movement before the running figure is known.
class _Move {
  const _Move({
    required this.date,
    required this.label,
    required this.qtyDelta,
    this.detail,
  });

  final DateTime date;
  final String label;
  final int qtyDelta;
  final String? detail;
}
