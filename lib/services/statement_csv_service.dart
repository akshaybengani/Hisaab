import 'dart:io';

import '../constants.dart';
import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import 'statement_text_service.dart';

/// Writes the book out as CSV, for anyone who would rather see it in a
/// spreadsheet than in a message.
///
/// Quoting follows RFC 4180 because it has to: a name in this book is whatever
/// the user typed, and "Reddy, Anita" and 5'2" Aunty are both real shapes. A
/// field is quoted wherever quoting changes its meaning, a quote inside a
/// field is doubled, and rows end with CRLF.
///
/// Every amount comes off a [Statement] or a [PersonBalance] through
/// [StatementFigures], the same object the text and the PDF read, which is
/// what stops a CSV total from disagreeing with the message that was sent.
/// See spec-27 ac-20.
abstract final class StatementCsvService {
  /// RFC 4180's record separator. A field holding a bare newline still round
  /// trips, because such a field is always quoted.
  static const String rowEnd = '\r\n';

  /// The dues list: one row per person, sorted the way `LedgerMath.balances`
  /// sorted them, so the file matches the screen it came from.
  ///
  /// The paise column is the stored integer, untouched, for a spreadsheet that
  /// wants to add the column up. The formatted columns are the same figures
  /// read by a person, and both come from the one balance.
  static String dues(List<PersonBalance> balances) {
    final List<List<String>> rows = <List<String>>[
      const <String>[
        'Name',
        'Phone',
        'Product due',
        'Cash due',
        'Total due',
        'Total due in paise',
        'Last activity',
      ],
      for (final PersonBalance balance in balances)
        <String>[
          balance.person.name,
          balance.person.phone ?? '',
          Money.format(balance.productDuePaise),
          Money.format(balance.cashDuePaise),
          Money.format(balance.netPaise),
          '${balance.netPaise}',
          balance.lastActivity == null
              ? ''
              : Dates.format(balance.lastActivity!),
        ],
    ];
    return encode(rows);
  }

  /// One person's statement, row for row, with the three figures on the end.
  ///
  /// A round-off keeps its own row here exactly as it does in the message and
  /// in the PDF, so a reader can see why the total, the paid figure and the
  /// due figure do not add up in the obvious way.
  static String statement(Statement statement) {
    final StatementFigures figures = StatementFigures.of(statement);
    final List<List<String>> rows = <List<String>>[
      const <String>[
        'Date',
        'Group',
        'Description',
        'For',
        'Settlement',
        'Amount',
        'Amount in paise',
      ],
      for (final StatementGroup group in <StatementGroup>[
        statement.products,
        statement.cash,
      ])
        for (final StatementLine line in group.lines)
          <String>[
            Dates.format(line.date),
            group.title,
            _describe(line),
            line.forMember ?? '',
            _settlement(line.settlement),
            Money.format(line.amountPaise),
            '${line.amountPaise}',
          ],
      _summary('Total', figures.totalPaise),
      _summary('Paid', figures.paidPaise),
      _summary('Due', figures.duePaise),
    ];
    return encode(rows);
  }

  /// Writes [content] to [path] and returns the file, for the share sheet.
  static Future<File> toFile(String path, String content) async {
    final File file = File(path);
    await file.writeAsString(content);
    return file;
  }

  /// Joins [rows] into a CSV document. Every row is padded to nothing and
  /// trimmed of nothing: a short row is a caller bug, not something to guess
  /// about.
  static String encode(List<List<String>> rows) {
    final StringBuffer out = StringBuffer();
    for (final List<String> row in rows) {
      out.write(row.map(escape).join(','));
      out.write(rowEnd);
    }
    return out.toString();
  }

  /// Quotes [field] wherever leaving it bare would change what it means, and
  /// doubles any quote inside it.
  ///
  /// Leading and trailing spaces are enough on their own to need quoting,
  /// because plenty of readers strip them.
  static String escape(String field) {
    final bool needsQuotes =
        field.contains('"') ||
        field.contains(',') ||
        field.contains('\n') ||
        field.contains('\r') ||
        field != field.trim();
    if (!needsQuotes) return field;
    return '"${field.replaceAll('"', '""')}"';
  }

  static List<String> _summary(String label, int paise) => <String>[
    '',
    '',
    label,
    '',
    '',
    Money.format(paise),
    '$paise',
  ];

  static String _describe(StatementLine line) {
    final String label = StatementLabels.labelFor(line);
    final String? detail = line.detail?.trim();
    if (detail == null || detail.isEmpty) return label;
    return '$label ($detail)';
  }

  static String _settlement(SettlementState? state) => switch (state) {
    null => '',
    SettlementState.paid => 'Paid',
    SettlementState.settled => 'Settled',
    SettlementState.partlyPaid => 'Partly paid',
    SettlementState.unpaid => 'Unpaid',
  };
}
