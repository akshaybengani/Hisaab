import '../helpers/dates.dart';

/// A thing that gets bought and handed out. Price is the current price only;
/// what a delivery cost is snapshotted onto the delivery line instead, so
/// editing this never rewrites history. See spec-27 dec-2.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.unitLabel,
    required this.currentPricePaise,
    this.category,
    this.archived = false,
  });

  final int? id;
  final String name;

  /// What one unit is called: bottle, pack, tub, strip. Shown beside every
  /// quantity so "3" is never ambiguous.
  final String unitLabel;
  final int currentPricePaise;
  final String? category;
  final bool archived;

  Product copyWith({
    int? id,
    String? name,
    String? unitLabel,
    int? currentPricePaise,
    String? category,
    bool? archived,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      unitLabel: unitLabel ?? this.unitLabel,
      currentPricePaise: currentPricePaise ?? this.currentPricePaise,
      category: category ?? this.category,
      archived: archived ?? this.archived,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'name': name,
    'unit_label': unitLabel,
    'current_price_paise': currentPricePaise,
    'category': category,
    'archived': archived ? 1 : 0,
  };

  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id'] as int?,
    name: map['name']! as String,
    unitLabel: map['unit_label']! as String,
    currentPricePaise: map['current_price_paise']! as int,
    category: map['category'] as String?,
    archived: (map['archived']! as int) == 1,
  );
}

/// An append-only record of what a product's price used to be. Written on
/// every price edit so a past figure can always be explained.
class PriceChange {
  const PriceChange({
    required this.id,
    required this.productId,
    required this.pricePaise,
    required this.effectiveFrom,
  });

  final int? id;
  final int productId;
  final int pricePaise;
  final DateTime effectiveFrom;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'product_id': productId,
    'price_paise': pricePaise,
    'effective_from': Dates.toStorage(effectiveFrom),
  };

  factory PriceChange.fromMap(Map<String, Object?> map) => PriceChange(
    id: map['id'] as int?,
    productId: map['product_id']! as int,
    pricePaise: map['price_paise']! as int,
    effectiveFrom: Dates.fromStorage(map['effective_from']! as String),
  );
}
