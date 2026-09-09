import '../constants.dart';
import 'person.dart';

/// One row on a person's statement.
class StatementLine {
  const StatementLine({
    required this.date,
    required this.description,
    required this.amountPaise,
    this.forMember,
    this.settlement,
    this.detail,
  });

  final DateTime date;
  final String description;

  /// Positive increases what the person owes, negative reduces it. This is the
  /// only sign convention in the app and it lives here.
  final int amountPaise;
  final String? forMember;

  /// Set on delivery lines only, computed by allocating payments oldest first
  /// and never stored. See spec-27 dec-1.
  final SettlementState? settlement;

  /// A second line of context, such as "2 Formula 1 at 2,050".
  final String? detail;
}

/// Product dues and cash loans are subtotalled separately, so a personal loan
/// never reads as though it were a product bill. See spec-27 dec-4.
class StatementGroup {
  const StatementGroup({required this.title, required this.lines});

  final String title;
  final List<StatementLine> lines;

  bool get isEmpty => lines.isEmpty;

  int get subtotalPaise =>
      lines.fold(0, (int sum, StatementLine l) => sum + l.amountPaise);
}

/// Everything the three renderers need, built once per person.
///
/// The text template, the PDF, and the CSV all read this same object, which is
/// what makes their totals identical by construction rather than by luck. See
/// spec-27 dec-6.
class Statement {
  const Statement({
    required this.person,
    required this.products,
    required this.cash,
    required this.generatedAt,
  });

  final Person person;
  final StatementGroup products;
  final StatementGroup cash;
  final DateTime generatedAt;

  /// What the person owes overall. Negative means the book owner owes them.
  int get netPaise => products.subtotalPaise + cash.subtotalPaise;

  bool get isSettled => netPaise == 0;

  bool get hasBothPools => !products.isEmpty && !cash.isEmpty;
}

/// A person's position, for the dues list. Cheap enough to compute for
/// everyone on every read at this data size.
class PersonBalance {
  const PersonBalance({
    required this.person,
    required this.productDuePaise,
    required this.cashDuePaise,
    required this.lastActivity,
  });

  final Person person;
  final int productDuePaise;
  final int cashDuePaise;

  /// The most recent delivery or money entry, used to sort and to show age.
  final DateTime? lastActivity;

  int get netPaise => productDuePaise + cashDuePaise;

  /// True where this person owes the book owner money.
  bool get owes => netPaise > 0;

  /// True where the book owner owes this person money.
  bool get isOwed => netPaise < 0;
}
