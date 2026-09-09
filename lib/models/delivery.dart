import '../helpers/dates.dart';

/// One handover of units to one person on one day.
class Delivery {
  const Delivery({
    required this.id,
    required this.personId,
    required this.date,
    this.forMember,
    this.note,
  });

  final int? id;
  final int personId;
  final DateTime date;

  /// Who in the household actually took these units. A free-text label, so a
  /// household keeps one balance and one payer. See spec-27 dec-5.
  final String? forMember;
  final String? note;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'person_id': personId,
    'date': Dates.toStorage(date),
    'for_member': forMember,
    'note': note,
  };

  factory Delivery.fromMap(Map<String, Object?> map) => Delivery(
    id: map['id'] as int?,
    personId: map['person_id']! as int,
    date: Dates.fromStorage(map['date']! as String),
    forMember: map['for_member'] as String?,
    note: map['note'] as String?,
  );
}

/// One product line on a delivery.
///
/// [unitPricePaise] is copied from the product at the moment of the handover
/// and is never re-read from the product afterwards. That is what stops a
/// price edit from rewriting a statement already sent. See spec-27 dec-2.
class DeliveryItem {
  const DeliveryItem({
    required this.id,
    required this.deliveryId,
    required this.productId,
    required this.qty,
    required this.unitPricePaise,
  });

  final int? id;
  final int? deliveryId;
  final int productId;
  final int qty;
  final int unitPricePaise;

  int get totalPaise => qty * unitPricePaise;

  DeliveryItem copyWith({int? deliveryId}) => DeliveryItem(
    id: id,
    deliveryId: deliveryId ?? this.deliveryId,
    productId: productId,
    qty: qty,
    unitPricePaise: unitPricePaise,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'delivery_id': deliveryId,
    'product_id': productId,
    'qty': qty,
    'unit_price_paise': unitPricePaise,
  };

  factory DeliveryItem.fromMap(Map<String, Object?> map) => DeliveryItem(
    id: map['id'] as int?,
    deliveryId: map['delivery_id'] as int?,
    productId: map['product_id']! as int,
    qty: map['qty']! as int,
    unitPricePaise: map['unit_price_paise']! as int,
  );
}

/// A delivery with its lines loaded, which is how every screen wants it.
class DeliveryWithItems {
  const DeliveryWithItems({required this.delivery, required this.items});

  final Delivery delivery;
  final List<DeliveryItem> items;

  int get totalPaise =>
      items.fold(0, (int sum, DeliveryItem i) => sum + i.totalPaise);
}
