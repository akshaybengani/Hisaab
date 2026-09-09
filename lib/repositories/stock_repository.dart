import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import 'contracts.dart';

/// Stock adjustments over sqflite. Every stepper tap writes a row rather than
/// updating a counter, which is what keeps on-hand explainable. See spec-27
/// dec-3.
///
/// Oldest first, so a running on-hand figure can be built by walking the list
/// once.
class SqfliteStockRepository implements StockRepository {
  const SqfliteStockRepository(this._db);

  final Database _db;

  @override
  Future<List<StockAdjustment>> forProduct(int productId) =>
      _load(where: 'product_id = ?', whereArgs: <Object?>[productId]);

  @override
  Future<List<StockAdjustment>> all() => _load();

  @override
  Future<int> insert(StockAdjustment adjustment) =>
      _db.insert('stock_adjustments', adjustment.toMap());

  /// The adjustment and the expense that mirrors it land together. The expense
  /// carries the new adjustment's id, which is the one place the ledger half
  /// and the expense half of the app touch.
  @override
  Future<int> insertWithExpense(StockAdjustment adjustment, Expense expense) {
    return _db.transaction<int>((Transaction txn) async {
      final int id = await txn.insert('stock_adjustments', adjustment.toMap());
      final Map<String, Object?> row = expense.toMap();
      row['stock_adjustment_id'] = id;
      await txn.insert('expenses', row);
      return id;
    });
  }

  /// An expense written by personal use goes with it, by the cascade on
  /// `expenses.stock_adjustment_id`. An expense the user typed themselves has
  /// no such link and is untouched.
  @override
  Future<void> delete(int id) async {
    await _db.delete(
      'stock_adjustments',
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<List<StockAdjustment>> _load({
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final List<Map<String, Object?>> rows = await _db.query(
      'stock_adjustments',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date ASC, id ASC',
    );
    return rows
        .map((Map<String, Object?> row) => StockAdjustment.fromMap(row))
        .toList();
  }
}
