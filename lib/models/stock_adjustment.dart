import '../constants.dart';
import '../helpers/dates.dart';

/// A stock movement with no purchase or delivery behind it.
///
/// Every tap of the plus and minus stepper writes one of these rather than
/// updating a counter, which is what keeps on-hand explainable. See spec-27
/// dec-3.
class StockAdjustment {
  const StockAdjustment({
    required this.id,
    required this.productId,
    required this.qtyDelta,
    required this.reason,
    required this.date,
    this.note,
  });

  final int? id;
  final int productId;

  /// Signed. A recount stores the delta needed to reach the counted figure,
  /// never the figure itself.
  final int qtyDelta;
  final StockReason reason;
  final DateTime date;
  final String? note;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'product_id': productId,
    'qty_delta': qtyDelta,
    'reason': reason.value,
    'date': Dates.toStorage(date),
    'note': note,
  };

  factory StockAdjustment.fromMap(Map<String, Object?> map) => StockAdjustment(
    id: map['id'] as int?,
    productId: map['product_id']! as int,
    qtyDelta: map['qty_delta']! as int,
    reason: StockReason.fromValue(map['reason']! as String),
    date: Dates.fromStorage(map['date']! as String),
    note: map['note'] as String?,
  );
}
