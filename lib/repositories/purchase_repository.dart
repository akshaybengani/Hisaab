import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'contracts.dart';

/// Purchases and their lines over sqflite.
///
/// Newest first, because a purchase list is a record of orders placed rather
/// than an input to any allocation.
class SqflitePurchaseRepository implements PurchaseRepository {
  const SqflitePurchaseRepository(this._db);

  final Database _db;

  @override
  Future<List<PurchaseWithItems>> all() => _load();

  @override
  Future<PurchaseWithItems?> byId(int id) async {
    final List<PurchaseWithItems> found = await _load(
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return found.isEmpty ? null : found.first;
  }

  @override
  Future<int> insert(Purchase purchase, List<PurchaseItem> items) {
    return _db.transaction<int>((Transaction txn) async {
      final int id = await txn.insert('purchases', purchase.toMap());
      await _writeItems(txn, id, items);
      return id;
    });
  }

  @override
  Future<void> update(Purchase purchase, List<PurchaseItem> items) async {
    final int? id = purchase.id;
    if (id == null) {
      throw ArgumentError('a purchase needs an id before it can be updated');
    }
    await _db.transaction((Transaction txn) async {
      final int touched = await txn.update(
        'purchases',
        purchase.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (touched == 0) {
        throw ArgumentError('there is no purchase with id $id');
      }
      await txn.delete(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: <Object?>[id],
      );
      await _writeItems(txn, id, items);
    });
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('purchases', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> _writeItems(
    Transaction txn,
    int purchaseId,
    List<PurchaseItem> items,
  ) async {
    for (final PurchaseItem item in items) {
      await txn.insert(
        'purchase_items',
        item.copyWith(purchaseId: purchaseId).toMap(),
      );
    }
  }

  Future<List<PurchaseWithItems>> _load({
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'purchases',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC, id DESC',
    );
    if (rows.isEmpty) return <PurchaseWithItems>[];

    final List<Purchase> purchases = rows
        .map((Map<String, Object?> row) => Purchase.fromMap(row))
        .toList();
    final List<Object?> ids = purchases
        .map((Purchase purchase) => purchase.id)
        .toList();
    final String slots = List<String>.filled(ids.length, '?').join(', ');
    final List<Map<String, Object?>> itemRows = await _db.query(
      'purchase_items',
      where: 'purchase_id IN ($slots)',
      whereArgs: ids,
      orderBy: 'id ASC',
    );

    final Map<int, List<PurchaseItem>> byPurchase = <int, List<PurchaseItem>>{};
    for (final Map<String, Object?> row in itemRows) {
      final PurchaseItem item = PurchaseItem.fromMap(row);
      byPurchase
          .putIfAbsent(item.purchaseId!, () => <PurchaseItem>[])
          .add(item);
    }

    return purchases
        .map(
          (Purchase purchase) => PurchaseWithItems(
            purchase: purchase,
            items: byPurchase[purchase.id] ?? const <PurchaseItem>[],
          ),
        )
        .toList();
  }
}
