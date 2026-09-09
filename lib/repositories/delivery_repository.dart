import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'contracts.dart';

/// Deliveries and their lines over sqflite.
///
/// Rows come back oldest first, because that is the order payments are
/// allocated in and every reader of this list wants the same order. See
/// spec-27 dec-1.
class SqfliteDeliveryRepository implements DeliveryRepository {
  const SqfliteDeliveryRepository(this._db);

  final Database _db;

  @override
  Future<List<DeliveryWithItems>> forPerson(int personId) => _load(
    where: 'person_id = ?',
    whereArgs: <Object?>[personId],
  );

  @override
  Future<List<DeliveryWithItems>> all() => _load();

  @override
  Future<DeliveryWithItems?> byId(int id) async {
    final List<DeliveryWithItems> found = await _load(
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
    return found.isEmpty ? null : found.first;
  }

  /// Header and lines land together or not at all, so a delivery can never be
  /// read back with a total of zero because the lines failed.
  @override
  Future<int> insert(Delivery delivery, List<DeliveryItem> items) {
    return _db.transaction<int>((Transaction txn) async {
      final int id = await txn.insert('deliveries', delivery.toMap());
      await _writeItems(txn, id, items);
      return id;
    });
  }

  @override
  Future<void> update(Delivery delivery, List<DeliveryItem> items) async {
    final int? id = delivery.id;
    if (id == null) {
      throw ArgumentError('a delivery needs an id before it can be updated');
    }
    await _db.transaction((Transaction txn) async {
      final int touched = await txn.update(
        'deliveries',
        delivery.toMap(),
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      if (touched == 0) {
        throw ArgumentError('there is no delivery with id $id');
      }
      await txn.delete(
        'delivery_items',
        where: 'delivery_id = ?',
        whereArgs: <Object?>[id],
      );
      await _writeItems(txn, id, items);
    });
  }

  /// The lines go with it, by the cascade on `delivery_items.delivery_id`.
  @override
  Future<void> delete(int id) async {
    await _db.delete('deliveries', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> _writeItems(
    Transaction txn,
    int deliveryId,
    List<DeliveryItem> items,
  ) async {
    for (final DeliveryItem item in items) {
      await txn.insert(
        'delivery_items',
        item.copyWith(deliveryId: deliveryId).toMap(),
      );
    }
  }

  /// Two queries whatever the row count, rather than one per delivery.
  Future<List<DeliveryWithItems>> _load({
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'deliveries',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date ASC, id ASC',
    );
    if (rows.isEmpty) return <DeliveryWithItems>[];

    final List<Delivery> deliveries = rows
        .map((Map<String, Object?> row) => Delivery.fromMap(row))
        .toList();
    final List<Object?> ids = deliveries
        .map((Delivery delivery) => delivery.id)
        .toList();
    final String slots = List<String>.filled(ids.length, '?').join(', ');
    final List<Map<String, Object?>> itemRows = await _db.query(
      'delivery_items',
      where: 'delivery_id IN ($slots)',
      whereArgs: ids,
      orderBy: 'id ASC',
    );

    final Map<int, List<DeliveryItem>> byDelivery = <int, List<DeliveryItem>>{};
    for (final Map<String, Object?> row in itemRows) {
      final DeliveryItem item = DeliveryItem.fromMap(row);
      byDelivery
          .putIfAbsent(item.deliveryId!, () => <DeliveryItem>[])
          .add(item);
    }

    return deliveries
        .map(
          (Delivery delivery) => DeliveryWithItems(
            delivery: delivery,
            items: byDelivery[delivery.id] ?? const <DeliveryItem>[],
          ),
        )
        .toList();
  }
}
