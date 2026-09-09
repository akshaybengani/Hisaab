import '../helpers/dates.dart';

/// A category the user created. Nothing is seeded, so the expense form has to
/// be able to create one inline. See spec-27 dec-14.
class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    this.archived = false,
  });

  final int? id;
  final String name;
  final bool archived;

  ExpenseCategory copyWith({String? name, bool? archived}) => ExpenseCategory(
    id: id,
    name: name ?? this.name,
    archived: archived ?? this.archived,
  );

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'name': name,
    'archived': archived ? 1 : 0,
  };

  factory ExpenseCategory.fromMap(Map<String, Object?> map) => ExpenseCategory(
    id: map['id'] as int?,
    name: map['name']! as String,
    archived: (map['archived']! as int) == 1,
  );
}

/// The book owner's own spending.
///
/// [stockAdjustmentId] links an expense written automatically when the owner
/// consumed a unit themselves. That link is the single point where the ledger
/// half and the expense half of the app touch. See spec-27 dec-3.
class Expense {
  const Expense({
    required this.id,
    required this.date,
    required this.amountPaise,
    this.categoryId,
    this.note,
    this.stockAdjustmentId,
  });

  final int? id;
  final DateTime date;
  final int amountPaise;
  final int? categoryId;
  final String? note;
  final int? stockAdjustmentId;

  bool get isFromPersonalUse => stockAdjustmentId != null;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'date': Dates.toStorage(date),
    'amount_paise': amountPaise,
    'category_id': categoryId,
    'note': note,
    'stock_adjustment_id': stockAdjustmentId,
  };

  factory Expense.fromMap(Map<String, Object?> map) => Expense(
    id: map['id'] as int?,
    date: Dates.fromStorage(map['date']! as String),
    amountPaise: map['amount_paise']! as int,
    categoryId: map['category_id'] as int?,
    note: map['note'] as String?,
    stockAdjustmentId: map['stock_adjustment_id'] as int?,
  );
}
