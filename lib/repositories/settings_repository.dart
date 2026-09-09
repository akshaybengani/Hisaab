import 'package:sqflite/sqflite.dart';

import 'contracts.dart';

/// Settings over sqflite. Values are always text, so a new setting never needs
/// a column and never needs a migration.
class SqfliteSettingsRepository implements SettingsRepository {
  const SqfliteSettingsRepository(this._db);

  final Database _db;

  @override
  Future<String?> read(String key) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'app_settings',
      columns: <String>['value'],
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value']! as String;
  }

  @override
  Future<Map<String, String>> readAll() async {
    final List<Map<String, Object?>> rows = await _db.query(
      'app_settings',
      orderBy: 'key ASC',
    );
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        row['key']! as String: row['value']! as String,
    };
  }

  @override
  Future<void> write(String key, String value) async {
    await _db.insert(
      'app_settings',
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
