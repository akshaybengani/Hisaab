import '../constants.dart';
import '../helpers/dates.dart';

/// Any movement of money against a person: a payment, a cash loan either way,
/// a repayment, a round-off, or a write-off.
///
/// One table carries all of them so a person has one balance and a negative
/// figure needs no special case. What an entry settles is decided by its
/// [kind], never by its date alone, so a product payment can never pay down a
/// cash loan. See spec-27 dec-4 and dec-12.
class MoneyEntry {
  const MoneyEntry({
    required this.id,
    required this.personId,
    required this.date,
    required this.amountPaise,
    required this.direction,
    required this.kind,
    this.method,
    this.note,
  });

  final int? id;
  final int personId;
  final DateTime date;

  /// Always positive. Which way it moved is [direction], so a sign convention
  /// can never disagree with a kind.
  final int amountPaise;
  final MoneyDirection direction;
  final MoneyKind kind;

  /// Cash, UPI, or whatever the user typed. Free text, because the app does
  /// not integrate with any payment rail.
  final String? method;
  final String? note;

  /// The effect on what this person owes. Positive means they owe more.
  int get signedPaise =>
      direction == MoneyDirection.incoming ? -amountPaise : amountPaise;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'person_id': personId,
    'date': Dates.toStorage(date),
    'amount_paise': amountPaise,
    'direction': direction.value,
    'kind': kind.value,
    'method': method,
    'note': note,
  };

  factory MoneyEntry.fromMap(Map<String, Object?> map) => MoneyEntry(
    id: map['id'] as int?,
    personId: map['person_id']! as int,
    date: Dates.fromStorage(map['date']! as String),
    amountPaise: map['amount_paise']! as int,
    direction: MoneyDirection.fromValue(map['direction']! as String),
    kind: MoneyKind.fromValue(map['kind']! as String),
    method: map['method'] as String?,
    note: map['note'] as String?,
  );
}
