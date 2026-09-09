import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'contracts.dart';

/// Products over sqflite.
///
/// The product row carries the current price only. What a handover cost lives
/// on the delivery line, so nothing here can rewrite a statement that has
/// already gone out. See spec-27 dec-2.
class SqfliteProductRepository implements ProductRepository {
  const SqfliteProductRepository(this._db);

  final Database _db;

  @override
  Future<List<Product>> all({bool includeArchived = false}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'products',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => Product.fromMap(row))
        .toList();
  }

  @override
  Future<Product?> byId(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'products',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  @override
  Future<int> insert(Product product) =>
      _db.insert('products', product.toMap());

  /// Reads the stored price, writes the row, and appends to the price history
  /// only where the two prices differ. Existing delivery lines are never
  /// touched, whatever changed here.
  @override
  Future<void> update(Product product) async {
    final int? id = product.id;
    if (id == null) {
      throw ArgumentError('a product needs an id before it can be updated');
    }
    await _db.transaction((Transaction txn) async {
      final List<Map<String, Object?>> stored = await txn.query(
        'products',
        columns: <String>['current_price_paise'],
        where: 'id = ?',
        whereArgs: <Object?>[id],
        limit: 1,
      );
      if (stored.isEmpty) {
        throw ArgumentError('there is no product with id $id');
      }
      final int before = stored.first['current_price_paise']! as int;
      await txn.update(
        'products',
        product.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (before != product.currentPricePaise) {
        await txn.insert(
          'product_price_history',
          PriceChange(
            id: null,
            productId: id,
            pricePaise: product.currentPricePaise,
            effectiveFrom: DateTime.now(),
          ).toMap(),
        );
      }
    });
  }

  /// Archiving hides the product from the default listing. Every delivery
  /// line, purchase line, request, and adjustment that names it stays exactly
  /// as it was, which is why there is no delete.
  @override
  Future<void> setArchived(int id, {required bool archived}) async {
    await _db.update(
      'products',
      <String, Object?>{'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<List<PriceChange>> priceHistory(int productId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'product_price_history',
      where: 'product_id = ?',
      whereArgs: <Object?>[productId],
      orderBy: 'effective_from ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => PriceChange.fromMap(row))
        .toList();
  }
}
