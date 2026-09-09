import '../constants.dart';
import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../repositories/contracts.dart';
import '../templates.dart';

/// What one statement row actually is.
///
/// [Statement] carries a description string rather than a kind, because the
/// renderers are the only thing that needs to tell a payment from a round-off
/// and [StatementLine] is deliberately free of enums. So the kind is recovered
/// here, from the two facts the line does carry: a delivery is the only row
/// with a settlement state, and every money row's description comes from one
/// closed set written by `LedgerMath`.
///
/// `test/statement_render_test.dart` asserts that set still matches what
/// `LedgerMath` produces, so a reworded label fails a test rather than
/// silently turning every payment into [StatementLineKind.unknown].
enum StatementLineKind {
  delivery,
  paymentReceived,
  cashLent,
  cashBorrowed,
  repayment,
  adjustment,
  writeOff,

  /// A description no build of `LedgerMath` has produced. Rendered with its
  /// own words and counted in no total, which is the safe way to be wrong.
  unknown,
}

/// The words Hisaab uses for money that moved without anyone paying.
///
/// The direction picks the word, and neither word is "write off". The book
/// owner's own framing: paying ₹50 less means the discount was received and
/// the change kept, and getting ₹50 less means the discount was given. A
/// [MoneyKind.writeOff] is the different thing of giving up on a debt, and
/// that one is written off.
abstract final class StatementLabels {
  /// The descriptions `LedgerMath` writes onto a money row.
  static const Map<String, StatementLineKind> _fromDescription =
      <String, StatementLineKind>{
        'Payment received': StatementLineKind.paymentReceived,
        'Cash lent': StatementLineKind.cashLent,
        'Cash borrowed': StatementLineKind.cashBorrowed,
        'Repayment': StatementLineKind.repayment,
        'Round-off adjustment': StatementLineKind.adjustment,
        'Written off': StatementLineKind.writeOff,
      };

  /// The set the drift guard reads, so the test does not restate the map.
  static Map<String, StatementLineKind> get knownDescriptions =>
      Map<String, StatementLineKind>.unmodifiable(_fromDescription);

  static StatementLineKind kindOf(StatementLine line) {
    if (line.settlement != null) return StatementLineKind.delivery;
    return _fromDescription[line.description] ?? StatementLineKind.unknown;
  }

  /// What the row reads as on a statement, in text and in the PDF alike.
  ///
  /// A round-off gets the direction-picked word. Everything else keeps the
  /// description it arrived with, including a delivery, whose description is
  /// the product that was handed over.
  static String labelFor(StatementLine line) {
    if (kindOf(line) != StatementLineKind.adjustment) return line.description;
    return line.amountPaise < 0 ? 'Discount given' : 'Change kept';
  }

  /// The gap between what a purchase cost on its lines and what was actually
  /// paid for it, in words. Null where the two agree.
  ///
  /// Paying more than the lines is money the owner absorbed, usually shipping.
  /// Paying less is a discount she received, which is a saving and belongs in
  /// no expense total.
  static String? purchaseGap(int absorbedPaise) {
    if (absorbedPaise == 0) return null;
    if (absorbedPaise > 0) {
      return 'You absorbed ${Money.formatWithSymbol(absorbedPaise)}';
    }
    return 'Discount received ${Money.formatWithSymbol(-absorbedPaise)}';
  }
}

/// The three figures every renderer prints, read once off one [Statement].
///
/// This type is the whole reason the text, the PDF and the CSV cannot disagree
/// about a total: none of them adds anything up itself. See spec-27 dec-6 and
/// ac-20.
///
/// [totalPaise] and [paidPaise] do not have to reconcile to [duePaise]. A
/// discount or a write-off moves the balance without anyone paying, and that
/// is exactly why each one is its own labelled row rather than a smaller
/// delivery or a larger payment.
class StatementFigures {
  const StatementFigures({
    required this.totalPaise,
    required this.paidPaise,
    required this.duePaise,
    required this.adjustedPaise,
    required this.writtenOffPaise,
  });

  /// Everything that was handed over or lent out, at the price it went out at.
  final int totalPaise;

  /// Money that actually came in: payments against products and repayments
  /// against loans. A discount is not a payment and is not counted here.
  final int paidPaise;

  /// What is still open. Negative means the book owner owes this person.
  final int duePaise;

  /// The round-offs, signed the way the statement rows are. Negative is a
  /// discount given, positive is change kept.
  final int adjustedPaise;

  /// What has been given up on, as a positive figure.
  final int writtenOffPaise;

  factory StatementFigures.of(Statement statement) {
    int total = 0;
    int paid = 0;
    int adjusted = 0;
    int writtenOff = 0;
    for (final StatementGroup group in <StatementGroup>[
      statement.products,
      statement.cash,
    ]) {
      for (final StatementLine line in group.lines) {
        if (line.amountPaise > 0) total += line.amountPaise;
        switch (StatementLabels.kindOf(line)) {
          case StatementLineKind.paymentReceived:
          case StatementLineKind.repayment:
            paid -= line.amountPaise;
          case StatementLineKind.adjustment:
            adjusted += line.amountPaise;
          case StatementLineKind.writeOff:
            writtenOff -= line.amountPaise;
          case StatementLineKind.delivery:
          case StatementLineKind.cashLent:
          case StatementLineKind.cashBorrowed:
          case StatementLineKind.unknown:
            break;
        }
      }
    }
    return StatementFigures(
      totalPaise: total,
      paidPaise: paid,
      duePaise: statement.netPaise,
      adjustedPaise: adjusted,
      writtenOffPaise: writtenOff,
    );
  }
}

/// Turns a [Statement] into the message that gets sent.
///
/// The substitution is a pure static, so every template can be asserted
/// without a database. The instance methods only exist to fetch the user's
/// own wording and UPI handle out of `app_settings` first.
class StatementTextService {
  const StatementTextService(this._settings);

  final SettingsRepository _settings;

  /// `{name}` and friends. Deliberately narrow: a stray `{` in a note can
  /// never look like a placeholder.
  static final RegExp _placeholder = RegExp(r'\{([a-z_]+)\}');

  /// Substitutes [values] into [template].
  ///
  /// A key not in [values] is left in the output exactly as written, so a
  /// mistyped `{tota}` reads back to the user instead of disappearing. A key
  /// that is in [values] but resolves to nothing takes its whole line with it,
  /// which is how a UPI line stays out of a message on a book with no handle
  /// saved. Runs of blank lines then collapse to one.
  static String fill(String template, Map<String, String> values) {
    final List<String> kept = <String>[];
    for (final String line in template.split('\n')) {
      bool drop = false;
      final String filled = line.replaceAllMapped(_placeholder, (Match match) {
        final String key = match.group(1)!;
        final String? value = values[key];
        if (value == null) return match.group(0)!;
        if (value.isEmpty) drop = true;
        return value;
      });
      if (!drop) kept.add(filled);
    }
    return _squeeze(kept);
  }

  /// Every value a statement template can substitute.
  ///
  /// [paidPaise] overrides the lifetime figure, for a receipt that should name
  /// the payment just taken rather than everything ever received.
  static Map<String, String> valuesOf(
    Statement statement, {
    String? upi,
    int? paidPaise,
  }) {
    final StatementFigures figures = StatementFigures.of(statement);
    return <String, String>{
      'name': statement.person.name.trim(),
      'items': itemsOf(statement),
      'total': Money.formatWithSymbol(figures.totalPaise),
      'paid': Money.formatWithSymbol(paidPaise ?? figures.paidPaise),
      'due': Money.formatWithSymbol(figures.duePaise),
      'upi': (upi ?? '').trim(),
    };
  }

  /// The rows, one per line. Product dues and cash loans are only titled and
  /// subtotalled where the person has both, since one heading over one list
  /// is noise. See spec-27 dec-4.
  static String itemsOf(Statement statement) {
    final bool both = statement.hasBothGroups;
    final List<String> out = <String>[];
    for (final StatementGroup group in <StatementGroup>[
      statement.products,
      statement.cash,
    ]) {
      if (group.isEmpty) continue;
      if (both) out.add(group.title);
      for (final StatementLine line in group.lines) {
        out.add(rowOf(line));
      }
      if (both) {
        out.add('Subtotal ${Money.formatWithSymbol(group.subtotalPaise)}');
      }
    }
    return out.join('\n');
  }

  /// One row: the date, what it was, and the amount.
  static String rowOf(StatementLine line) {
    final StringBuffer middle = StringBuffer(StatementLabels.labelFor(line));
    final String? detail = _trimmed(line.detail);
    if (detail != null) middle.write(' ($detail)');
    final String? member = _trimmed(line.forMember);
    if (member != null) middle.write(' for $member');
    return '${Dates.format(line.date)}, $middle, '
        '${Money.formatWithSymbol(line.amountPaise)}';
  }

  /// The full position, for someone who asked what they owe.
  Future<String> statement(Statement statement) async => fill(
    await _template(SettingKeys.templateStatement),
    valuesOf(statement, upi: await _upi()),
  );

  /// The nudge. Warm and short by design, because the person is buying through
  /// the book owner as a favour.
  Future<String> reminder(Statement statement) async => fill(
    await _template(SettingKeys.templateReminder),
    valuesOf(statement, upi: await _upi()),
  );

  /// Sent straight after money changes hands. [paidPaise] names the payment
  /// just taken; without it the message reads the lifetime figure.
  Future<String> receipt(Statement statement, {int? paidPaise}) async => fill(
    await _template(SettingKeys.templateReceipt),
    valuesOf(statement, upi: await _upi(), paidPaise: paidPaise),
  );

  /// Everything pending, one line per product, which is what gets typed into
  /// an order. [estimatedTotalPaise] is a valuation at today's prices, so it
  /// is named as an estimate in the default wording.
  Future<String> shoppingList(
    List<ShoppingListLine> lines, {
    required int estimatedTotalPaise,
  }) async =>
      fill(await _template(SettingKeys.templateShoppingList), <String, String>{
        'name': '',
        'items': lines.map(_shoppingRow).join('\n'),
        'total': Money.formatWithSymbol(estimatedTotalPaise),
        'paid': '',
        'due': '',
        'upi': await _upi() ?? '',
      });

  /// Answers the question that gets asked most often over WhatsApp. A product
  /// with nothing left is still listed, because "out of stock" is the answer
  /// someone is looking for.
  Future<String> inStock(List<StockLevel> levels) async {
    int value = 0;
    for (final StockLevel level in levels) {
      value += level.valuePaise;
    }
    return fill(await _template(SettingKeys.templateInStock), <String, String>{
      'name': '',
      'items': levels.map(_stockRow).join('\n'),
      'total': Money.formatWithSymbol(value),
      'paid': '',
      'due': '',
      'upi': await _upi() ?? '',
    });
  }

  static String _shoppingRow(ShoppingListLine line) {
    final String people = line.requestCount == 1
        ? '1 person'
        : '${line.requestCount} people';
    return '${line.qty} ${line.unitLabel} ${line.productName} ($people)';
  }

  static String _stockRow(StockLevel level) => level.isOut
      ? '${level.product.name}, out of stock'
      : '${level.product.name}, ${level.onHand} ${level.product.unitLabel}';

  /// The user's own wording where they have written any, the default where
  /// they have not.
  Future<String> _template(String key) async {
    final String? stored = await _settings.read(key);
    if (stored == null || stored.trim().isEmpty) {
      return Templates.defaults[key]!;
    }
    return stored;
  }

  Future<String?> _upi() async {
    final String? handle = await _settings.read(SettingKeys.upiHandle);
    return _trimmed(handle);
  }

  static String _squeeze(List<String> lines) {
    final List<String> out = <String>[];
    for (final String line in lines) {
      final bool blank = line.trim().isEmpty;
      if (blank && (out.isEmpty || out.last.isEmpty)) continue;
      out.add(blank ? '' : line);
    }
    while (out.isNotEmpty && out.last.isEmpty) {
      out.removeLast();
    }
    return out.join('\n');
  }

  static String? _trimmed(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
