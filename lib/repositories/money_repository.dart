import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'contracts.dart';

/// Money entries over sqflite. One table carries payments, cash loans either
/// way, repayments, round-offs, and write-offs, so a person has one history
/// and a negative balance needs no special case. See spec-27 dec-4.
///
/// Oldest first, because payments are allocated in that order.
class SqfliteMoneyRepository implements MoneyRepository {
  const SqfliteMoneyRepository(this._db);

  final Database _db;

  @override
  Future<List<MoneyEntry>> forPerson(int personId) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'money_entries',
      where: 'person_id = ?',
      whereArgs: <Object?>[personId],
      orderBy: 'date ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => MoneyEntry.fromMap(row))
        .toList();
  }

  @override
  Future<int> insert(MoneyEntry entry) =>
      _db.insert('money_entries', entry.toMap());

  @override
  Future<void> update(MoneyEntry entry) async {
    final int? id = entry.id;
    if (id == null) {
      throw ArgumentError('a money entry needs an id before it can be updated');
    }
    await _db.update(
      'money_entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete(
      'money_entries',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
