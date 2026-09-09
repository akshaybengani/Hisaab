import 'package:sqflite/sqflite.dart';

import '../constants.dart';
import '../helpers/dates.dart';
import '../models/models.dart';
import 'contracts.dart';

/// Requests over sqflite. Oldest first, so a request nobody has acted on stays
/// at the top of the list instead of sinking. See spec-27 dec-8.
class SqfliteRequestRepository implements RequestRepository {
  const SqfliteRequestRepository(this._db);

  final Database _db;

  @override
  Future<List<ProductRequest>> byStatus(RequestStatus status) =>
      _load(where: 'status = ?', whereArgs: <Object?>[status.value]);

  @override
  Future<List<ProductRequest>> forPerson(int personId) =>
      _load(where: 'person_id = ?', whereArgs: <Object?>[personId]);

  @override
  Future<int> insert(ProductRequest request) =>
      _db.insert('requests', request.toMap());

  /// Reads the stored status and refuses a move the lifecycle does not allow,
  /// rather than writing it and leaving the book in a state no screen can
  /// explain.
  @override
  Future<void> setStatus(int id, RequestStatus status) async {
    await _db.transaction((Transaction txn) async {
      final ProductRequest request = await _require(txn, id);
      if (!request.status.canMoveTo(status)) {
        throw ArgumentError(
          'a request cannot move from ${request.status.value} to '
          '${status.value}',
        );
      }
      await _setStatus(txn, id, status);
    });
  }

  /// The delivery, its one line, and the status change land together. The
  /// person, the household member label, and the note come from the request,
  /// so the delivery reads the way the request did.
  @override
  Future<int> convertToDelivery(int requestId, DeliveryItem item) {
    return _db.transaction<int>((Transaction txn) async {
      final ProductRequest request = await _require(txn, requestId);
      if (!request.status.canMoveTo(RequestStatus.delivered)) {
        throw ArgumentError(
          'a request in ${request.status.value} cannot become a delivery',
        );
      }
      final int deliveryId = await txn.insert(
        'deliveries',
        Delivery(
          id: null,
          personId: request.personId,
          date: Dates.today(),
          forMember: request.forMember,
          note: request.note,
        ).toMap(),
      );
      await txn.insert(
        'delivery_items',
        item.copyWith(deliveryId: deliveryId).toMap(),
      );
      await _setStatus(txn, requestId, RequestStatus.delivered);
      return deliveryId;
    });
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('requests', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<ProductRequest> _require(Transaction txn, int id) async {
    final List<Map<String, Object?>> rows = await txn.query(
      'requests',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError('there is no request with id $id');
    }
    return ProductRequest.fromMap(rows.first);
  }

  Future<void> _setStatus(Transaction txn, int id, RequestStatus status) async {
    await txn.update(
      'requests',
      <String, Object?>{'status': status.value},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<ProductRequest>> _load({
    required String where,
    required List<Object?> whereArgs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'requests',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => ProductRequest.fromMap(row))
        .toList();
  }
}
