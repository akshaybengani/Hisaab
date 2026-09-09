import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';

/// Turning a statement into something the owner can send.
///
/// Both renderers read the same [Statement], so their totals agree by
/// construction rather than by luck. See spec-27 dec-6.
///
/// This sits in the UI lane because the UI lane owns the share actions. If a
/// service layer grows later, the two builders move there unchanged.
abstract final class StatementShare {
  /// The WhatsApp text. [template] is the owner's own wording from settings,
  /// used as the opening line where she set one.
  static String message(Statement statement, {String template = ''}) {
    final StringBuffer out = StringBuffer();
    if (template.trim().isNotEmpty) {
      out.writeln(template.trim());
      out.writeln();
    }
    out.writeln('${statement.person.name}, as of ${Dates.format(statement.generatedAt)}');
    for (final StatementGroup group in <StatementGroup>[
      statement.products,
      statement.cash,
    ]) {
      if (group.isEmpty) continue;
      out.writeln();
      out.writeln(group.title);
      for (final StatementLine line in group.lines) {
        out.writeln(
          '${Dates.format(line.date)}  ${line.description}  '
          '${Money.formatWithSymbol(line.amountPaise)}',
        );
      }
      out.writeln('Subtotal ${Money.formatWithSymbol(group.subtotalPaise)}');
    }
    out.writeln();
    final int net = statement.netPaise;
    out.writeln(
      net > 0
          ? 'Balance due ${Money.formatWithSymbol(net)}'
          : net < 0
          ? 'In your credit ${Money.formatWithSymbol(net.abs())}'
          : 'Nothing outstanding',
    );
    return out.toString();
  }

  /// A one page statement.
  ///
  /// Amounts are written as grouped numerals with the currency named in the
  /// column head, because the built in PDF fonts carry no rupee glyph and a
  /// missing glyph on a bill is worse than a spelled out unit.
  static Future<Uint8List> pdf(
    Statement statement, {
    String header = '',
    String footer = '',
  }) async {
    final pw.Document document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => <pw.Widget>[
          if (header.trim().isNotEmpty)
            pw.Paragraph(
              text: header.trim(),
              style: const pw.TextStyle(fontSize: 10),
            ),
          pw.Header(level: 0, text: statement.person.name),
          pw.Text(
            'Statement as of ${Dates.format(statement.generatedAt)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 12),
          for (final StatementGroup group in <StatementGroup>[
            statement.products,
            statement.cash,
          ])
            if (!group.isEmpty) _group(group),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              pw.Text(
                statement.netPaise >= 0 ? 'Balance due' : 'In credit',
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.Text(
                Money.format(statement.netPaise.abs()),
                style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (footer.trim().isNotEmpty) ...<pw.Widget>[
            pw.SizedBox(height: 24),
            pw.Paragraph(
              text: footer.trim(),
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ],
      ),
    );
    return document.save();
  }

  static pw.Widget _group(StatementGroup group) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.SizedBox(height: 8),
      pw.Text(
        group.title,
        style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Table(
        columnWidths: const <int, pw.TableColumnWidth>{
          0: pw.FlexColumnWidth(2),
          1: pw.FlexColumnWidth(5),
          2: pw.FlexColumnWidth(2),
        },
        children: <pw.TableRow>[
          pw.TableRow(
            children: <pw.Widget>[
              _cell('Date', bold: true),
              _cell('Detail', bold: true),
              _cell('Amount (INR)', bold: true, right: true),
            ],
          ),
          for (final StatementLine line in group.lines)
            pw.TableRow(
              children: <pw.Widget>[
                _cell(Dates.format(line.date)),
                _cell(
                  <String>[
                    line.description,
                    if (line.forMember != null) 'for ${line.forMember}',
                  ].join(', '),
                ),
                _cell(Money.format(line.amountPaise), right: true),
              ],
            ),
          pw.TableRow(
            children: <pw.Widget>[
              _cell(''),
              _cell('Subtotal', bold: true),
              _cell(
                Money.format(group.subtotalPaise),
                bold: true,
                right: true,
              ),
            ],
          ),
        ],
      ),
    ],
  );

  static pw.Widget _cell(
    String text, {
    bool bold = false,
    bool right = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
    child: pw.Text(
      text,
      textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}
