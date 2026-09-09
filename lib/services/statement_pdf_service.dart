import 'dart:typed_data';

import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants.dart';
import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../repositories/contracts.dart';
import 'statement_text_service.dart';

/// Reads one asset's bytes. Injected so a test can hand the service the
/// committed `.ttf` off disk rather than standing up an asset bundle, and so
/// nothing in this file has to know that Flutter is running.
typedef AssetBytes = Future<ByteData> Function(String key);

/// The bundled typeface.
///
/// The `pdf` package's built-in Helvetica has no glyph for the rupee sign, so
/// every amount in the app would print as a blank box. Noto Sans covers
/// U+20B9 and is committed under `assets/fonts/` with its licence, which means
/// a PDF renders on a phone with the radio off. Nothing is fetched at render
/// time, and `test/statement_render_test.dart` asserts that.
class PdfFonts {
  const PdfFonts({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;

  static const String regularAsset = 'assets/fonts/NotoSans-Regular.ttf';
  static const String boldAsset = 'assets/fonts/NotoSans-Bold.ttf';

  /// The licence ships beside the font because the SIL Open Font License
  /// requires it to travel with the software.
  static const String licenceAsset = 'assets/fonts/OFL.txt';

  /// The rupee sign, the character that made bundling a font necessary.
  static const int rupeeRune = 0x20B9;

  /// Loads both faces once. Hold the result: parsing a `.ttf` twice per
  /// document is wasted work on a phone.
  static Future<PdfFonts> load({AssetBytes? loadAsset}) async {
    final AssetBytes read = loadAsset ?? rootBundle.load;
    return PdfFonts(
      regular: pw.Font.ttf(await read(regularAsset)),
      bold: pw.Font.ttf(await read(boldAsset)),
    );
  }

  pw.ThemeData get theme => pw.ThemeData.withFont(base: regular, bold: bold);
}

/// One printed row.
///
/// The figures are held as paise and formatted at paint time, so the layout a
/// test reads and the page a person reads carry the same number by
/// construction rather than by two call sites agreeing.
class PdfRow {
  const PdfRow({
    required this.label,
    this.date,
    this.detail,
    this.amountPaise,
    this.trailing,
  });

  final String label;
  final DateTime? date;
  final String? detail;

  /// Money, formatted through [Money.format] when painted.
  final int? amountPaise;

  /// Printed in the right column in place of an amount, for a row counted in
  /// units rather than in money.
  final String? trailing;

  String get amountText =>
      amountPaise == null ? trailing ?? '' : Money.format(amountPaise!);
}

/// A titled block of rows, optionally subtotalled.
class PdfSection {
  const PdfSection({
    required this.title,
    required this.rows,
    this.subtotalLabel,
    this.subtotalPaise,
    this.emptyMessage,
  });

  final String title;
  final List<PdfRow> rows;
  final String? subtotalLabel;
  final int? subtotalPaise;

  /// What to print where there are no rows. A section with neither rows nor
  /// this is left out entirely.
  final String? emptyMessage;

  bool get isEmpty => rows.isEmpty && emptyMessage == null;
}

/// One figure on the summary block at the foot of a report.
class PdfSummaryLine {
  const PdfSummaryLine(this.label, this.amountPaise, {this.emphasised = false});

  final String label;
  final int amountPaise;
  final bool emphasised;
}

/// A whole document, as data.
///
/// Building this is separate from painting it, which is what lets a test
/// assert the figures on a report without reading glyph indices back out of a
/// content stream. See spec-27 ac-20 and ac-21.
class PdfReport {
  const PdfReport({
    required this.title,
    required this.sections,
    this.subtitle,
    this.summary = const <PdfSummaryLine>[],
    this.note,
  });

  final String title;
  final String? subtitle;
  final List<PdfSection> sections;
  final List<PdfSummaryLine> summary;

  /// A sentence under the summary, for the one thing a column of figures
  /// cannot say on its own.
  final String? note;

  /// The sections that will actually print.
  List<PdfSection> get printable =>
      sections.where((PdfSection s) => !s.isEmpty).toList();

  /// The figure against [label] on the summary block, for a caller that wants
  /// one number rather than the whole list.
  int? summaryFor(String label) {
    for (final PdfSummaryLine line in summary) {
      if (line.label == label) return line.amountPaise;
    }
    return null;
  }
}

/// Renders the four documents Hisaab prints, on the phone, from data it
/// already has.
///
/// The header and footer blocks are the user's own text out of `app_settings`.
/// Either one unset, or set to nothing but whitespace, is normalised to null
/// here, and a null band is passed to `pw.MultiPage` as no callback at all.
/// That is what makes "no band" mean no band rather than an empty one, since
/// an empty widget still takes a line's worth of the page. See spec-27 ac-22.
class StatementPdfService {
  const StatementPdfService({required this.fonts, this.header, this.footer});

  final PdfFonts fonts;

  /// Already normalised: null, never blank.
  final String? header;
  final String? footer;

  /// Reads the two bands out of `app_settings` and loads the font.
  static Future<StatementPdfService> load({
    required SettingsRepository settings,
    PdfFonts? fonts,
    AssetBytes? loadAsset,
  }) async {
    return StatementPdfService(
      fonts: fonts ?? await PdfFonts.load(loadAsset: loadAsset),
      header: band(await settings.read(SettingKeys.pdfHeader)),
      footer: band(await settings.read(SettingKeys.pdfFooter)),
    );
  }

  /// Trims a stored band and turns anything empty into null, so the one
  /// question the renderer asks is whether it is null.
  static String? band(String? stored) {
    if (stored == null) return null;
    final String trimmed = stored.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// A person's statement, the document that gets sent when someone asks for
  /// it on paper.
  static PdfReport statementReport(Statement statement, {String? upi}) {
    final StatementFigures figures = StatementFigures.of(statement);
    final bool both = statement.hasBothGroups;
    final String? handle = band(upi);
    return PdfReport(
      title: statement.person.name,
      subtitle: 'Statement as at ${Dates.format(statement.generatedAt)}',
      sections: <PdfSection>[
        for (final StatementGroup group in <StatementGroup>[
          statement.products,
          statement.cash,
        ])
          PdfSection(
            title: group.title,
            rows: <PdfRow>[
              for (final StatementLine line in group.lines) _statementRow(line),
            ],
            subtotalLabel: both ? 'Subtotal' : null,
            subtotalPaise: both ? group.subtotalPaise : null,
          ),
      ],
      summary: <PdfSummaryLine>[
        PdfSummaryLine('Total', figures.totalPaise),
        PdfSummaryLine('Paid', figures.paidPaise),
        if (figures.adjustedPaise < 0)
          PdfSummaryLine('Discount given', -figures.adjustedPaise),
        if (figures.adjustedPaise > 0)
          PdfSummaryLine('Change kept', figures.adjustedPaise),
        if (figures.writtenOffPaise != 0)
          PdfSummaryLine('Written off', figures.writtenOffPaise),
        PdfSummaryLine('Due', figures.duePaise, emphasised: true),
      ],
      note: handle == null ? null : 'Pay by UPI to $handle',
    );
  }

  /// Everyone's position on one page, which is the document the book owner
  /// prints for herself.
  static PdfReport duesReport(
    List<PersonBalance> balances, {
    required DateTime generatedAt,
  }) {
    int owedIn = 0;
    int owedOut = 0;
    final List<PdfRow> owing = <PdfRow>[];
    final List<PdfRow> owed = <PdfRow>[];
    for (final PersonBalance balance in balances) {
      if (balance.netPaise == 0) continue;
      final PdfRow row = PdfRow(
        label: balance.person.name,
        detail: _duesDetail(balance),
        amountPaise: balance.netPaise,
      );
      if (balance.owes) {
        owedIn += balance.netPaise;
        owing.add(row);
      } else {
        owedOut -= balance.netPaise;
        owed.add(row);
      }
    }
    return PdfReport(
      title: 'All dues',
      subtitle: 'As at ${Dates.format(generatedAt)}',
      sections: <PdfSection>[
        PdfSection(
          title: 'Owed to you',
          rows: owing,
          emptyMessage: 'Nobody owes anything',
          subtotalLabel: 'Subtotal',
          subtotalPaise: owedIn,
        ),
        PdfSection(title: 'You owe', rows: owed),
      ],
      summary: <PdfSummaryLine>[
        PdfSummaryLine('Owed to you', owedIn),
        if (owedOut != 0) PdfSummaryLine('You owe', owedOut),
        PdfSummaryLine('Net', owedIn - owedOut, emphasised: true),
      ],
    );
  }

  /// What is on hand, with what it is worth at today's prices. A valuation,
  /// not a cost basis, and the wording says so.
  static PdfReport stockReport(
    List<StockLevel> levels, {
    required DateTime generatedAt,
  }) {
    int value = 0;
    final List<PdfRow> onHand = <PdfRow>[];
    final List<PdfRow> out = <PdfRow>[];
    for (final StockLevel level in levels) {
      value += level.valuePaise;
      final PdfRow row = PdfRow(
        label: level.product.name,
        detail:
            '${level.onHand} ${level.product.unitLabel} at '
            '${Money.format(level.product.currentPricePaise)}',
        amountPaise: level.valuePaise,
      );
      (level.isOut ? out : onHand).add(row);
    }
    return PdfReport(
      title: 'Stock',
      subtitle: 'As at ${Dates.format(generatedAt)}',
      sections: <PdfSection>[
        PdfSection(
          title: 'On hand',
          rows: onHand,
          emptyMessage: 'Nothing in stock',
        ),
        PdfSection(title: 'Out of stock', rows: out),
      ],
      summary: <PdfSummaryLine>[
        PdfSummaryLine('Value at current prices', value, emphasised: true),
      ],
    );
  }

  /// A month's spending, by category, with the orders placed in the same
  /// month underneath.
  ///
  /// A discount received on an order is a saving, so it is reported on its own
  /// line and is never added into what was spent. Money the owner absorbed,
  /// usually shipping, is spending and is counted.
  static PdfReport monthlyExpenseReport({
    required int year,
    required int month,
    required List<Expense> expenses,
    required Map<int, String> categoryNames,
    List<PurchaseWithItems> purchases = const <PurchaseWithItems>[],
  }) {
    final Map<String, int> byCategory = <String, int>{};
    final Map<String, int> countByCategory = <String, int>{};
    int spent = 0;
    for (final Expense expense in expenses) {
      final int? categoryId = expense.categoryId;
      final String name = categoryId == null
          ? 'Uncategorised'
          : categoryNames[categoryId] ?? 'Uncategorised';
      byCategory[name] = (byCategory[name] ?? 0) + expense.amountPaise;
      countByCategory[name] = (countByCategory[name] ?? 0) + 1;
      spent += expense.amountPaise;
    }
    final List<String> names = byCategory.keys.toList()
      ..sort(
        (String a, String b) => a.toLowerCase().compareTo(b.toLowerCase()),
      );

    int paidForStock = 0;
    int discountReceived = 0;
    final List<PdfRow> orders = <PdfRow>[];
    for (final PurchaseWithItems purchase in purchases) {
      paidForStock += purchase.purchase.totalPaidPaise;
      if (purchase.absorbedPaise < 0) {
        discountReceived -= purchase.absorbedPaise;
      }
      orders.add(
        PdfRow(
          label: purchase.purchase.vendor ?? 'Order',
          date: purchase.purchase.date,
          detail: StatementLabels.purchaseGap(purchase.absorbedPaise),
          amountPaise: purchase.purchase.totalPaidPaise,
        ),
      );
    }

    final DateTime first = DateTime(year, month);
    final DateTime last = DateTime(
      year,
      month + 1,
    ).subtract(const Duration(days: 1));
    return PdfReport(
      title: 'Expenses',
      subtitle: 'From ${Dates.format(first)} to ${Dates.format(last)}',
      sections: <PdfSection>[
        PdfSection(
          title: 'By category',
          rows: <PdfRow>[
            for (final String name in names)
              PdfRow(
                label: name,
                detail: _entryCount(countByCategory[name]!),
                amountPaise: byCategory[name],
              ),
          ],
          emptyMessage: 'Nothing recorded this month',
          subtotalLabel: 'Subtotal',
          subtotalPaise: spent,
        ),
        PdfSection(title: 'Orders placed', rows: orders),
      ],
      summary: <PdfSummaryLine>[
        PdfSummaryLine('Expenses', spent),
        if (orders.isNotEmpty) PdfSummaryLine('Paid for stock', paidForStock),
        PdfSummaryLine('Total spent', spent + paidForStock, emphasised: true),
        if (discountReceived != 0)
          PdfSummaryLine('Discount received', discountReceived),
      ],
      note: discountReceived == 0
          ? null
          : 'A discount received is a saving, so it is not counted in what '
                'was spent',
    );
  }

  /// Paints [report] and returns the bytes.
  ///
  /// [compress] exists so a test can read the page's own content stream and
  /// check what the layout actually put on the page. Leave it alone in the
  /// app: an uncompressed statement is several times the size.
  Future<Uint8List> render(PdfReport report, {bool compress = true}) async {
    final pw.Document document = pw.Document(
      compress: compress,
      theme: fonts.theme,
      title: report.title,
    );
    final String? headerText = header;
    final String? footerText = footer;
    document.addPage(
      pw.MultiPage(
        maxPages: 200,
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 32,
          marginRight: 32,
          marginTop: 32,
          marginBottom: 32,
        ),
        header: headerText == null
            ? null
            : (pw.Context context) => _headerBand(headerText),
        footer: footerText == null
            ? null
            : (pw.Context context) => _footerBand(footerText),
        build: (pw.Context context) => _body(report),
      ),
    );
    return document.save();
  }

  List<pw.Widget> _body(PdfReport report) {
    final String? subtitle = report.subtitle;
    final String? note = report.note;
    return <pw.Widget>[
      pw.Text(
        report.title,
        style: pw.TextStyle(font: fonts.bold, fontSize: 18),
      ),
      if (subtitle != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            subtitle,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        ),
      pw.SizedBox(height: 12),
      for (final PdfSection section in report.printable) _section(section),
      if (report.summary.isNotEmpty) _summary(report.summary),
      if (note != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            note,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
    ];
  }

  pw.Widget _section(PdfSection section) {
    final String? emptyMessage = section.emptyMessage;
    final String? subtotalLabel = section.subtotalLabel;
    final int? subtotalPaise = section.subtotalPaise;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          section.title,
          style: pw.TextStyle(font: fonts.bold, fontSize: 11),
        ),
        pw.Divider(height: 6, thickness: 0.5, color: PdfColors.grey400),
        if (section.rows.isEmpty && emptyMessage != null)
          pw.Text(
            emptyMessage,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
        for (final PdfRow row in section.rows) _row(row),
        if (subtotalLabel != null && subtotalPaise != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Text(
                    subtotalLabel,
                    style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                  ),
                ),
                pw.Text(
                  Money.format(subtotalPaise),
                  style: pw.TextStyle(font: fonts.bold, fontSize: 10),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  pw.Widget _row(PdfRow row) {
    final DateTime? date = row.date;
    final String? detail = row.detail;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: 72,
            child: pw.Text(
              date == null ? '' : Dates.format(date),
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text(row.label, style: const pw.TextStyle(fontSize: 10)),
                if (detail != null)
                  pw.Text(
                    detail,
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ),
          ),
          pw.Text(row.amountText, style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
  }

  pw.Widget _summary(List<PdfSummaryLine> lines) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Divider(height: 6, thickness: 0.5, color: PdfColors.grey400),
      for (final PdfSummaryLine line in lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Text(
                  line.label,
                  style: line.emphasised
                      ? pw.TextStyle(font: fonts.bold, fontSize: 11)
                      : const pw.TextStyle(fontSize: 10),
                ),
              ),
              pw.Text(
                Money.formatWithSymbol(line.amountPaise),
                style: line.emphasised
                    ? pw.TextStyle(font: fonts.bold, fontSize: 11)
                    : const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),
        ),
    ],
  );

  pw.Widget _headerBand(String text) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      for (final String line in text.split('\n'))
        pw.Text(line, style: const pw.TextStyle(fontSize: 9)),
      pw.Divider(height: 8, thickness: 0.5, color: PdfColors.grey400),
    ],
  );

  pw.Widget _footerBand(String text) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Divider(height: 8, thickness: 0.5, color: PdfColors.grey400),
      for (final String line in text.split('\n'))
        pw.Text(
          line,
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
    ],
  );

  static PdfRow _statementRow(StatementLine line) => PdfRow(
    label: StatementLabels.labelFor(line),
    date: line.date,
    detail: _statementDetail(line),
    amountPaise: line.amountPaise,
  );

  static String? _statementDetail(StatementLine line) {
    final String? member = _trimmed(line.forMember);
    final List<String> parts = <String>[
      ?_trimmed(line.detail),
      if (member != null) 'for $member',
      ?_settlementLabel(line),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// A settled line names the amount conceded, because a person reading their
  /// own statement should see the discount they were given rather than a word
  /// that quietly stands in for it. See spec-27 ac-43.
  static String? _settlementLabel(
    StatementLine line,
  ) => switch (line.settlement) {
    null => null,
    SettlementState.paid => 'paid',
    SettlementState.partlyPaid => 'partly paid',
    SettlementState.unpaid => 'unpaid',
    SettlementState.settled =>
      line.concededPaise > 0
          ? 'settled, ${Money.formatWithSymbol(line.concededPaise)} discount'
          : 'settled',
  };

  static String? _duesDetail(PersonBalance balance) {
    final DateTime? last = balance.lastActivity;
    final List<String> parts = <String>[
      if (balance.productDuePaise != 0 && balance.cashDuePaise != 0)
        'products ${Money.format(balance.productDuePaise)}, cash '
            '${Money.format(balance.cashDuePaise)}',
      if (last != null) 'last activity ${Dates.format(last)}',
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String _entryCount(int count) =>
      count == 1 ? '1 entry' : '$count entries';

  static String? _trimmed(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
