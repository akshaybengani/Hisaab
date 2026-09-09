import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'contracts.dart';

/// People over sqflite. There is no balance column: what someone owes is
/// derived from their deliveries and money entries on every read, so it can
/// never disagree with the rows behind it. See spec-27 dec-1.
class SqflitePersonRepository implements PersonRepository {
  const SqflitePersonRepository(this._db);

  final Database _db;

  @override
  Future<List<Person>> all({bool includeArchived = false}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'people',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows.map((Map<String, Object?> row) => Person.fromMap(row)).toList();
  }

  @override
  Future<Person?> byId(int id) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'people',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Person.fromMap(rows.first);
  }

  @override
  Future<int> insert(Person person) => _db.insert('people', person.toMap());

  @override
  Future<void> update(Person person) async {
    final int? id = person.id;
    if (id == null) {
      throw ArgumentError('a person needs an id before they can be updated');
    }
    await _db.update(
      'people',
      person.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /// Hides the person from the default listing and leaves every delivery and
  /// money entry that names them intact, so an archived person's history is
  /// still readable and still adds up.
  @override
  Future<void> setArchived(int id, {required bool archived}) async {
    await _db.update(
      'people',
      <String, Object?>{'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
