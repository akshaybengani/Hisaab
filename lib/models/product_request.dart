import '../constants.dart';
import '../helpers/dates.dart';

/// Something a person asked for before an order was placed.
///
/// Requests are the reason an order has the contents it has, which is why they
/// are a real stage rather than a note: they produce the consolidated shopping
/// list. See spec-27 dec-8.
class ProductRequest {
  const ProductRequest({
    required this.id,
    required this.personId,
    required this.productId,
    required this.qty,
    required this.status,
    required this.createdAt,
    this.forMember,
    this.note,
  });

  final int? id;
  final int personId;
  final int productId;
  final int qty;
  final RequestStatus status;
  final DateTime createdAt;
  final String? forMember;
  final String? note;

  ProductRequest copyWith({RequestStatus? status}) => ProductRequest(
    id: id,
    personId: personId,
    productId: productId,
    qty: qty,
    status: status ?? this.status,
    createdAt: createdAt,
    forMember: forMember,
    note: note,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'person_id': personId,
    'product_id': productId,
    'qty': qty,
    'status': status.value,
    'created_at': Dates.toStorage(createdAt),
    'for_member': forMember,
    'note': note,
  };

  factory ProductRequest.fromMap(Map<String, Object?> map) => ProductRequest(
    id: map['id'] as int?,
    personId: map['person_id']! as int,
    productId: map['product_id']! as int,
    qty: map['qty']! as int,
    status: RequestStatus.fromValue(map['status']! as String),
    createdAt: Dates.fromStorage(map['created_at']! as String),
    forMember: map['for_member'] as String?,
    note: map['note'] as String?,
  );
}

/// One line of the consolidated shopping list: total pending quantity for a
/// product across everyone who asked for it.
class ShoppingListLine {
  const ShoppingListLine({
    required this.productId,
    required this.productName,
    required this.unitLabel,
    required this.qty,
    required this.requestCount,
  });

  final int productId;
  final String productName;
  final String unitLabel;
  final int qty;

  /// How many separate people asked, so a line for one person reads
  /// differently from a line for six.
  final int requestCount;
}
