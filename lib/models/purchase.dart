import '../helpers/dates.dart';

/// One order the book owner placed and paid for.
///
/// [totalPaidPaise] is recorded independently of the line items, because
/// shipping and offers mean the two legitimately differ. The gap is shown as
/// absorbed by the owner rather than spread across units, so a unit's price
/// never depends on what else shared its order. See spec-27 dec-7.
class Purchase {
  const Purchase({
    required this.id,
    required this.date,
    required this.totalPaidPaise,
    this.vendor,
    this.note,
  });

  final int? id;
  final DateTime date;
  final int totalPaidPaise;

  /// Plain text. A vendor entity would have one row in this app.
  final String? vendor;
  final String? note;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'date': Dates.toStorage(date),
    'total_paid_paise': totalPaidPaise,
    'vendor': vendor,
    'note': note,
  };

  factory Purchase.fromMap(Map<String, Object?> map) => Purchase(
    id: map['id'] as int?,
    date: Dates.fromStorage(map['date']! as String),
    totalPaidPaise: map['total_paid_paise']! as int,
    vendor: map['vendor'] as String?,
    note: map['note'] as String?,
  );
}

/// One product line on a purchase. [unitCostPaise] is what the owner says a
/// unit cost, never derived from the purchase total.
class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.qty,
    required this.unitCostPaise,
  });

  final int? id;
  final int? purchaseId;
  final int productId;
  final int qty;
  final int unitCostPaise;

  int get totalPaise => qty * unitCostPaise;

  PurchaseItem copyWith({int? purchaseId}) => PurchaseItem(
    id: id,
    purchaseId: purchaseId ?? this.purchaseId,
    productId: productId,
    qty: qty,
    unitCostPaise: unitCostPaise,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'purchase_id': purchaseId,
    'product_id': productId,
    'qty': qty,
    'unit_cost_paise': unitCostPaise,
  };

  factory PurchaseItem.fromMap(Map<String, Object?> map) => PurchaseItem(
    id: map['id'] as int?,
    purchaseId: map['purchase_id'] as int?,
    productId: map['product_id']! as int,
    qty: map['qty']! as int,
    unitCostPaise: map['unit_cost_paise']! as int,
  );
}

/// A purchase with its lines loaded.
class PurchaseWithItems {
  const PurchaseWithItems({required this.purchase, required this.items});

  final Purchase purchase;
  final List<PurchaseItem> items;

  int get lineTotalPaise =>
      items.fold(0, (int sum, PurchaseItem i) => sum + i.totalPaise);

  /// What the owner absorbed: shipping, or an offer that made the order cost
  /// less than its lines. Positive means they paid more than the lines say.
  int get absorbedPaise => purchase.totalPaidPaise - lineTotalPaise;
}
