import 'package:sqflite/sqflite.dart';

import '../helpers/dates.dart';
import '../models/models.dart';
import 'contracts.dart';

/// Expenses and their categories over sqflite. Newest first, because a
/// spending list is read from the top.
class SqfliteExpenseRepository implements ExpenseRepository {
  const SqfliteExpenseRepository(this._db);

  final Database _db;

  @override
  Future<List<Expense>> all() => _load();

  /// Dates are stored as ISO 8601 text, which sorts and compares in calendar
  /// order, so a month is a plain string range rather than a date function.
  @override
  Future<List<Expense>> inMonth(int year, int month) async {
    if (month < 1 || month > 12) {
      throw ArgumentError('month must be 1 to 12, got $month');
    }
    return _load(
      where: 'date >= ? AND date < ?',
      whereArgs: <Object?>[
        Dates.toStorage(DateTime(year, month)),
        Dates.toStorage(DateTime(year, month + 1)),
      ],
    );
  }

  @override
  Future<int> insert(Expense expense) =>
      _db.insert('expenses', expense.toMap());

  @override
  Future<void> update(Expense expense) async {
    final int? id = expense.id;
    if (id == null) {
      throw ArgumentError('an expense needs an id before it can be updated');
    }
    await _db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('expenses', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  @override
  Future<List<ExpenseCategory>> categories({
    bool includeArchived = false,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'expense_categories',
      where: includeArchived ? null : 'archived = 0',
      orderBy: 'name COLLATE NOCASE ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => ExpenseCategory.fromMap(row))
        .toList();
  }

  /// Matches on the name ignoring case, so "Petrol" typed after "petrol"
  /// returns the first one instead of leaving two categories that read the
  /// same. A match that had been archived is brought back, because the user
  /// has just used it. See spec-27 dec-14.
  @override
  Future<int> ensureCategory(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('a category needs a name');
    }
    return _db.transaction<int>((Transaction txn) async {
      final List<Map<String, Object?>> existing = await txn.query(
        'expense_categories',
        where: 'name = ? COLLATE NOCASE',
        whereArgs: <Object?>[trimmed],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final ExpenseCategory found = ExpenseCategory.fromMap(existing.first);
        final int id = found.id!;
        if (found.archived) {
          await txn.update(
            'expense_categories',
            <String, Object?>{'archived': 0},
            where: 'id = ?',
            whereArgs: <Object?>[id],
          );
        }
        return id;
      }
      return txn.insert(
        'expense_categories',
        ExpenseCategory(id: null, name: trimmed).toMap(),
      );
    });
  }

  /// Hides the category from the picker and leaves every expense that points
  /// at it intact, still carrying its category id.
  @override
  Future<void> setCategoryArchived(int id, {required bool archived}) async {
    await _db.update(
      'expense_categories',
      <String, Object?>{'archived': archived ? 1 : 0},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<Expense>> _load({String? where, List<Object?>? whereArgs}) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'expenses',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC, id DESC',
    );
    return rows
        .map((Map<String, Object?> row) => Expense.fromMap(row))
        .toList();
  }
}
