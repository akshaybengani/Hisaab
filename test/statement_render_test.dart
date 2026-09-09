import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/helpers/ledger_math.dart';
import 'package:hisaab/helpers/money.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/repositories/contracts.dart';
import 'package:hisaab/services/share_service.dart';
import 'package:hisaab/services/statement_csv_service.dart';
import 'package:hisaab/services/statement_pdf_service.dart';
import 'package:hisaab/services/statement_text_service.dart';
import 'package:hisaab/templates.dart';
import 'package:pdf/pdf.dart';

import 'support/memex_ac.dart';

/// The three renderers, asserted against one another rather than each against
/// a figure typed into the test.
///
/// That is the whole point of spec-27 dec-6: the text message, the PDF and the
/// CSV all read one [Statement], so the only way they can disagree about a
/// total is if one of them adds something up itself. These tests would catch
/// that, and nothing else would until a person noticed a wrong number in a
/// message already sent.
void main() {
  useAcEmission('test/statement_render_test.dart');

  // A book with something in both pools, a payment that came up short, and the
  // round-off that closed the gap. One fixture, because every renderer is
  // supposed to be reading the same one.
  const Person meena = Person(id: 1, name: 'Meena', phone: '98765 43210');
  const Product formula = Product(
    id: 7,
    name: 'Formula 1',
    unitLabel: 'tub',
    currentPricePaise: 205000,
  );
  final DateTime generatedAt = DateTime(2026, 9, 9);

  Statement build({
    List<MoneyEntry> extra = const <MoneyEntry>[],
    Person person = meena,
  }) {
    final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
      DeliveryWithItems(
        delivery: Delivery(id: 1, personId: 1, date: DateTime(2026, 9, 1)),
        items: <DeliveryItem>[
          const DeliveryItem(
            id: 1,
            deliveryId: 1,
            productId: 7,
            qty: 2,
            unitPricePaise: 205000,
          ),
        ],
      ),
    ];
    return LedgerMath.buildStatement(
      person: person,
      deliveries: deliveries,
      entries: <MoneyEntry>[
        MoneyEntry(
          id: 1,
          personId: 1,
          date: DateTime(2026, 9, 5),
          amountPaise: 400000,
          direction: MoneyDirection.incoming,
          kind: MoneyKind.paymentReceived,
          method: 'UPI',
        ),
        MoneyEntry(
          id: 2,
          personId: 1,
          date: DateTime(2026, 9, 5),
          amountPaise: 10000,
          direction: MoneyDirection.incoming,
          kind: MoneyKind.adjustment,
        ),
        MoneyEntry(
          id: 3,
          personId: 1,
          date: DateTime(2026, 9, 2),
          amountPaise: 50000,
          direction: MoneyDirection.outgoing,
          kind: MoneyKind.cashLent,
        ),
        ...extra,
      ],
      productsById: const <int, Product>{7: formula},
      generatedAt: generatedAt,
    );
  }

  group('one statement, three renderers', () {
    /// Verifies ac-20.
    acTest(
      'total, paid and due read the same in the text, the PDF and the CSV',
      <String>['ac-20'],
      () async {
        final Statement statement = build();
        final StatementFigures figures = StatementFigures.of(statement);

        final String text = await StatementTextService(
          _Settings(),
        ).statement(statement);
        final PdfReport report = StatementPdfService.statementReport(statement);
        final String csv = StatementCsvService.statement(statement);

        // Each renderer is read the way its own reader would read it: the
        // message by the line it prints, the PDF by the summary block it
        // paints, the CSV by the column a spreadsheet would sum.
        expect(
          _labelled(text, 'Total'),
          Money.formatWithSymbol(410000 + 50000),
        );
        expect(_labelled(text, 'Paid'), Money.formatWithSymbol(400000));
        expect(_labelled(text, 'Due'), Money.formatWithSymbol(50000));

        for (final String label in <String>['Total', 'Paid', 'Due']) {
          final int? fromPdf = report.summaryFor(label);
          final int fromCsv = _csvSummary(csv, label);
          expect(
            fromPdf,
            fromCsv,
            reason: '$label differs between the PDF and the CSV',
          );
          expect(
            _labelled(text, label),
            Money.formatWithSymbol(fromCsv),
            reason: '$label differs between the message and the CSV',
          );
        }

        expect(figures.totalPaise, 460000);
        expect(figures.paidPaise, 400000);
        expect(figures.duePaise, statement.netPaise);
      },
    );

    /// Verifies ac-20: the figures still agree once a write-off has moved a
    /// balance without anyone paying, which is where a renderer that does its
    /// own arithmetic would drift.
    acTest(
      'the three agree after a write-off as well',
      <String>['ac-20'],
      () async {
        final Statement statement = build(
          extra: <MoneyEntry>[
            MoneyEntry(
              id: 4,
              personId: 1,
              date: DateTime(2026, 9, 8),
              amountPaise: 50000,
              direction: MoneyDirection.incoming,
              kind: MoneyKind.writeOff,
            ),
          ],
        );

        final String text = await StatementTextService(
          _Settings(),
        ).statement(statement);
        final PdfReport report = StatementPdfService.statementReport(statement);
        final String csv = StatementCsvService.statement(statement);

        for (final String label in <String>['Total', 'Paid', 'Due']) {
          expect(
            _labelled(text, label),
            Money.formatWithSymbol(_csvSummary(csv, label)),
          );
          expect(report.summaryFor(label), _csvSummary(csv, label));
        }
        // A write-off is not a payment, so it never lands in the paid figure.
        expect(report.summaryFor('Paid'), 400000);
        expect(report.summaryFor('Written off'), 50000);
      },
    );
  });

  group('the PDF renders from the bundled font', () {
    /// Verifies ac-21.
    acTest(
      'the committed font covers the rupee sign',
      <String>['ac-21'],
      () async {
        for (final String asset in <String>[
          PdfFonts.regularAsset,
          PdfFonts.boldAsset,
        ]) {
          final File file = File(asset);
          expect(
            file.existsSync(),
            isTrue,
            reason: '$asset is not committed, so the PDF has no rupee glyph',
          );
          final TtfParser parsed = TtfParser(await _bytes(asset));
          expect(
            parsed.charToGlyphIndexMap.containsKey(PdfFonts.rupeeRune),
            isTrue,
            reason: '$asset has no glyph for the rupee sign',
          );
        }

        // The licence has to travel with the font, and the pubspec has to name
        // the folder or none of it reaches the phone.
        expect(File(PdfFonts.licenceAsset).existsSync(), isTrue);
        expect(
          File('pubspec.yaml').readAsStringSync(),
          contains('assets/fonts/'),
        );
      },
    );

    /// Verifies ac-21.
    acTest(
      'the document parses, names the bundled font, and carries the figures',
      <String>['ac-21'],
      () async {
        final Statement statement = build();
        final StatementPdfService service = await _service();
        final Uint8List bytes = await service.render(
          StatementPdfService.statementReport(statement),
        );

        final String raw = latin1.decode(bytes, allowInvalid: true);
        expect(raw.startsWith('%PDF-'), isTrue);
        expect(raw.trimRight().endsWith('%%EOF'), isTrue);
        expect(raw, matches(RegExp(r'/Type\s*/Catalog')));
        expect(raw, matches(RegExp(r'/Type\s*/Page[^s]')));

        // The cross reference the trailer points at has to be inside the file
        // and has to be a cross reference, which is as far as a reader gets
        // before it can find anything at all.
        final RegExpMatch? tail = RegExp(
          r'startxref\s+(\d+)\s+%%EOF',
        ).firstMatch(raw);
        expect(tail, isNotNull, reason: 'the file has no usable trailer');
        final int xref = int.parse(tail!.group(1)!);
        expect(xref, greaterThan(0));
        expect(xref, lessThan(bytes.length));
        expect(
          raw.substring(xref, xref + 60),
          anyOf(startsWith('xref'), matches(RegExp(r'^\d+ \d+ obj'))),
        );

        // The embedded font descriptor carries the face's own PostScript name,
        // so this is the bundled file and not a substitute.
        expect(raw, matches(RegExp(r'/BaseFont\s*/NotoSans-Regular')));
        expect(raw, matches(RegExp(r'/FontFile2\s*\d+ 0 R')));

        // The figures are on the page because the layout the page was painted
        // from carries them. Reading them back out of the content stream is
        // not possible once a TrueType subset has turned them into glyph
        // indices, which is exactly why the layout is a separate object.
        final PdfReport report = StatementPdfService.statementReport(statement);
        expect(report.summaryFor('Due'), statement.netPaise);
        expect(
          report.printable.first.rows.map((PdfRow r) => r.amountText),
          contains(Money.format(410000)),
        );
      },
    );

    /// Verifies ac-21.
    acTest(
      'rendering asks for the two committed assets and nothing else, and '
      'makes no network call',
      <String>['ac-21'],
      () async {
        final List<String> asked = <String>[];
        final HttpOverrides? previous = HttpOverrides.current;
        HttpOverrides.global = _NoNetwork();
        addTearDown(() => HttpOverrides.global = previous);

        final PdfFonts fonts = await PdfFonts.load(
          loadAsset: (String key) async {
            asked.add(key);
            return _bytes(key);
          },
        );
        final Uint8List bytes = await StatementPdfService(
          fonts: fonts,
        ).render(StatementPdfService.statementReport(build()));

        expect(asked, <String>[PdfFonts.regularAsset, PdfFonts.boldAsset]);
        expect(bytes, isNotEmpty);
      },
    );
  });

  group('the PDF header and footer come from app_settings', () {
    /// Verifies ac-22.
    acTest(
      'both bands are read off the settings and blank ones become nothing',
      <String>['ac-22'],
      () async {
        final StatementPdfService set = await StatementPdfService.load(
          settings: _Settings(<String, String>{
            SettingKeys.pdfHeader: '  Meena Herbalife\n9876543210  ',
            SettingKeys.pdfFooter: 'Thank you',
          }),
          fonts: await _fonts(),
        );
        expect(set.header, 'Meena Herbalife\n9876543210');
        expect(set.footer, 'Thank you');

        final StatementPdfService blank = await StatementPdfService.load(
          settings: _Settings(<String, String>{
            SettingKeys.pdfHeader: '   \n  ',
            SettingKeys.pdfFooter: '',
          }),
          fonts: await _fonts(),
        );
        expect(blank.header, isNull);
        expect(blank.footer, isNull);

        final StatementPdfService unset = await StatementPdfService.load(
          settings: _Settings(),
          fonts: await _fonts(),
        );
        expect(unset.header, isNull);
        expect(unset.footer, isNull);
      },
    );

    /// Verifies ac-22.
    acTest(
      'a set band adds to the page and an empty one takes no space at all',
      <String>['ac-22'],
      () async {
        final PdfFonts fonts = await _fonts();
        final PdfReport report = StatementPdfService.statementReport(build());

        final String withBands = await _pageContent(
          StatementPdfService(
            fonts: fonts,
            header: 'Meena Herbalife\n9876543210',
            footer: 'Thank you',
          ),
          report,
        );
        final String withNone = await _pageContent(
          StatementPdfService(fonts: fonts),
          report,
        );
        final String withBlank = await _pageContent(
          await StatementPdfService.load(
            settings: _Settings(<String, String>{
              SettingKeys.pdfHeader: '   ',
              SettingKeys.pdfFooter: '\n \n',
            }),
            fonts: fonts,
          ),
          report,
        );

        // Bands set: more drawn, and drawn differently.
        expect(withBands, isNot(withNone));
        expect(
          _count(withBands, 'Td'),
          greaterThan(_count(withNone, 'Td')),
          reason: 'a header and a footer should put more text on the page',
        );

        // Bands blank: byte for byte the same page as no bands at all, which
        // is the only way to show an empty one consumes no vertical space. An
        // empty widget would still shift every y coordinate below it.
        expect(
          withBlank,
          withNone,
          reason: 'an empty band must render nothing and take no height',
        );
      },
    );
  });

  group('templates', () {
    /// Verifies ac-23.
    acTest(
      'all six placeholders resolve and an unknown one stays literal',
      <String>['ac-23'],
      () async {
        const String template =
            '{name} {items} {total} {paid} {due} {upi} {tota} {}';
        final String filled =
            StatementTextService.fill(template, <String, String>{
              'name': 'Meena',
              'items': 'one thing',
              'total': '₹4,600',
              'paid': '₹4,000',
              'due': '₹500',
              'upi': 'meena@upi',
            });

        expect(
          filled,
          'Meena one thing ₹4,600 ₹4,000 ₹500 meena@upi '
          '{tota} {}',
        );
        for (final String placeholder in Templates.placeholders) {
          expect(
            filled,
            isNot(contains(placeholder)),
            reason: '$placeholder was left unresolved',
          );
        }
      },
    );

    /// Verifies ac-23.
    acTest(
      'every default template uses only placeholders that resolve',
      <String>['ac-23'],
      () async {
        final Statement statement = build();
        final Map<String, String> values = StatementTextService.valuesOf(
          statement,
          upi: 'meena@upi',
        );
        expect(values.keys.length, Templates.placeholders.length);

        for (final MapEntry<String, String> entry
            in Templates.defaults.entries) {
          final String filled = StatementTextService.fill(entry.value, values);
          expect(
            RegExp(r'\{[a-z_]+\}').hasMatch(filled),
            isFalse,
            reason: '${entry.key} left a placeholder in the output',
          );
          expect(filled.trim(), isNotEmpty);
          expect(Templates.titles.containsKey(entry.key), isTrue);
        }
      },
    );

    acTest(
      'a value that resolves to nothing takes its whole line with it',
      <String>[],
      () async {
        final String withHandle = await StatementTextService(
          _Settings(<String, String>{SettingKeys.upiHandle: 'meena@upi'}),
        ).reminder(build());
        final String without = await StatementTextService(
          _Settings(),
        ).reminder(build());

        expect(withHandle, contains('UPI meena@upi'));
        expect(without, isNot(contains('UPI')));
        expect(without.trimRight(), without);
        expect(without, isNot(contains('\n\n\n')));
      },
    );

    acTest(
      "the user's own wording wins over the default",
      <String>[],
      () async {
        final String message = await StatementTextService(
          _Settings(<String, String>{
            SettingKeys.templateReminder: 'Hi {name}, {due} outstanding',
          }),
        ).reminder(build());

        expect(
          message,
          'Hi Meena, ${Money.formatWithSymbol(50000)} outstanding',
        );
      },
    );
  });

  group('a round-off is its own line, and the direction picks the word', () {
    /// Verifies ac-39.
    acTest(
      'money paid short reads as a discount given, in the text and the PDF',
      <String>['ac-39'],
      () async {
        final Statement statement = build();
        final String text = await StatementTextService(
          _Settings(),
        ).statement(statement);
        final PdfReport report = StatementPdfService.statementReport(statement);
        final String csv = StatementCsvService.statement(statement);

        // Its own row, beside the payment rather than folded into it.
        final List<String> textRows = text
            .split('\n')
            .where((String line) => line.contains('Discount given'))
            .toList();
        expect(textRows, hasLength(1));
        expect(textRows.single, contains(Money.formatWithSymbol(-10000)));
        expect(text, contains('Payment received'));

        final List<PdfRow> pdfRows = report.printable
            .expand((PdfSection s) => s.rows)
            .where((PdfRow r) => r.label == 'Discount given')
            .toList();
        expect(pdfRows, hasLength(1));
        expect(pdfRows.single.amountPaise, -10000);
        expect(
          report.printable
              .expand((PdfSection s) => s.rows)
              .map((PdfRow r) => r.label),
          contains('Payment received'),
        );

        expect(csv, contains('Discount given'));

        // Never the other vocabulary, and never a write-off.
        for (final String output in <String>[text, csv]) {
          expect(output.toLowerCase(), isNot(contains('write off')));
          expect(output.toLowerCase(), isNot(contains('written off')));
          expect(output, isNot(contains('Round-off adjustment')));
        }
      },
    );

    /// Verifies ac-39.
    acTest(
      'an overpayment kept reads as change kept',
      <String>['ac-39'],
      () async {
        final Statement kept = LedgerMath.buildStatement(
          person: meena,
          deliveries: const <DeliveryWithItems>[],
          entries: <MoneyEntry>[
            MoneyEntry(
              id: 1,
              personId: 1,
              date: DateTime(2026, 9, 5),
              amountPaise: 5000,
              direction: MoneyDirection.outgoing,
              kind: MoneyKind.adjustment,
            ),
          ],
          productsById: const <int, Product>{},
          generatedAt: generatedAt,
        );

        final PdfReport report = StatementPdfService.statementReport(kept);
        expect(
          report.printable.expand((PdfSection s) => s.rows).single.label,
          'Change kept',
        );
        expect(report.summaryFor('Change kept'), 5000);
        expect(report.summaryFor('Discount given'), isNull);
      },
    );

    acTest(
      'a genuine write-off keeps the words it deserves',
      <String>[],
      () async {
        final Statement statement = build(
          extra: <MoneyEntry>[
            MoneyEntry(
              id: 4,
              personId: 1,
              date: DateTime(2026, 9, 8),
              amountPaise: 50000,
              direction: MoneyDirection.incoming,
              kind: MoneyKind.writeOff,
            ),
          ],
        );
        final String text = await StatementTextService(
          _Settings(),
        ).statement(statement);
        expect(text, contains('Written off'));
        expect(text, contains('Discount given'));
      },
    );

    acTest(
      'a purchase gap is absorbed one way and a discount the other',
      <String>[],
      () async {
        expect(StatementLabels.purchaseGap(0), isNull);
        expect(StatementLabels.purchaseGap(20000), 'You absorbed ₹200');
        expect(StatementLabels.purchaseGap(-5000), 'Discount received ₹50');

        // The discount is reported as a saving, and never added into what was
        // spent.
        final PdfReport report = StatementPdfService.monthlyExpenseReport(
          year: 2026,
          month: 9,
          expenses: <Expense>[
            Expense(
              id: 1,
              date: DateTime(2026, 9, 3),
              amountPaise: 30000,
              categoryId: 1,
            ),
          ],
          categoryNames: const <int, String>{1: 'Travel'},
          purchases: <PurchaseWithItems>[
            PurchaseWithItems(
              purchase: Purchase(
                id: 1,
                date: DateTime(2026, 9, 2),
                totalPaidPaise: 395000,
                vendor: 'Herbalife',
              ),
              items: const <PurchaseItem>[
                PurchaseItem(
                  id: 1,
                  purchaseId: 1,
                  productId: 7,
                  qty: 2,
                  unitCostPaise: 200000,
                ),
              ],
            ),
          ],
        );

        expect(report.summaryFor('Expenses'), 30000);
        expect(report.summaryFor('Total spent'), 30000 + 395000);
        expect(report.summaryFor('Discount received'), 5000);
        expect(report.note, contains('saving'));
      },
    );

    /// The classifier in `StatementLabels` reads the descriptions
    /// `LedgerMath` writes. If a label there is reworded, this fails rather
    /// than every payment quietly becoming an unknown row.
    acTest(
      'the labels the renderers classify on still match LedgerMath',
      <String>[],
      () async {
        final Statement all = LedgerMath.buildStatement(
          person: meena,
          deliveries: const <DeliveryWithItems>[],
          entries: <MoneyEntry>[
            for (final MoneyKind kind in MoneyKind.values)
              MoneyEntry(
                id: kind.index + 1,
                personId: 1,
                date: DateTime(2026, 9, 1),
                amountPaise: 1000,
                direction: kind == MoneyKind.cashLent
                    ? MoneyDirection.outgoing
                    : MoneyDirection.incoming,
                kind: kind,
              ),
            // An adjustment reads by direction, so it is the one kind that
            // yields two descriptions and both have to stay recognised.
            MoneyEntry(
              id: 99,
              personId: 1,
              date: DateTime(2026, 9, 1),
              amountPaise: 1000,
              direction: MoneyDirection.outgoing,
              kind: MoneyKind.adjustment,
            ),
          ],
          productsById: const <int, Product>{},
          generatedAt: generatedAt,
        );

        final Set<String> seen = <String>{
          for (final StatementGroup group in <StatementGroup>[
            all.products,
            all.cash,
          ])
            for (final StatementLine line in group.lines) line.description,
        };
        expect(seen, StatementLabels.knownDescriptions.keys.toSet());
        expect(
          seen,
          hasLength(MoneyKind.values.length + 1),
          reason: 'every kind, plus the adjustment\'s second direction',
        );

        for (final StatementLine line in <StatementLine>[
          ...all.products.lines,
          ...all.cash.lines,
        ]) {
          expect(
            StatementLabels.kindOf(line),
            isNot(StatementLineKind.unknown),
            reason: '"${line.description}" is no longer recognised',
          );
        }
      },
    );
  });

  group('CSV quoting', () {
    /// A name in this book is whatever the user typed.
    acTest(
      'a name with a comma and a quote survives the round trip',
      <String>[],
      () async {
        const String awkward = 'Reddy, "Anita" O\'Brien';
        final String csv = StatementCsvService.dues(<PersonBalance>[
          PersonBalance(
            person: const Person(
              id: 1,
              name: awkward,
              phone: '+91 98765 43210',
            ),
            productDuePaise: 410000,
            cashDuePaise: -50000,
            lastActivity: DateTime(2026, 9, 5),
          ),
          const PersonBalance(
            person: Person(id: 2, name: ' padded '),
            productDuePaise: 0,
            cashDuePaise: 0,
            lastActivity: null,
          ),
        ]);

        // Read back with a parser that knows nothing about the writer.
        final List<List<String>> rows = _parseCsv(csv);
        expect(rows.first.first, 'Name');
        expect(rows[1][0], awkward);
        expect(rows[1][4], Money.format(360000));
        expect(rows[1][5], '360000');
        expect(rows[1][6], '5 Sep 2026');
        expect(rows[2][0], ' padded ');
        expect(rows[2][6], '');

        // And the raw text really is quoted, not merely parseable by luck.
        expect(csv, contains('"Reddy, ""Anita"" O\'Brien"'));
        expect(csv, contains('" padded "'));
        expect(csv.endsWith('\r\n'), isTrue);
      },
    );

    acTest('a field holding a newline round trips too', <String>[], () async {
      const String messy = 'line one\nline two, with a comma';
      expect(
        StatementCsvService.escape(messy),
        '"line one\nline two, with a comma"',
      );
      expect(
        _parseCsv(
          StatementCsvService.encode(<List<String>>[
            <String>[messy, 'after'],
          ]),
        ),
        <List<String>>[
          <String>[messy, 'after'],
        ],
      );
    });
  });

  group('sharing', () {
    acTest('a wa.me link is built and percent-encoded', <String>[], () async {
      final Uri? link = WhatsAppLink.forPerson(
        meena,
        'Hi Meena\nDue ₹500 & change',
      );

      expect(link, isNotNull);
      expect(link!.scheme, 'https');
      expect(link.host, 'wa.me');
      expect(link.path, '/919876543210');
      expect(link.toString(), contains('%0A'));
      expect(link.toString(), contains('%20'));
      expect(link.toString(), contains('%E2%82%B9'));
      expect(link.toString(), contains('%26'));
      expect(link.toString(), isNot(contains('+')));
      // The round trip is what a chat app actually does with the link.
      expect(link.queryParameters['text'], 'Hi Meena\nDue ₹500 & change');
    });

    acTest(
      'however the number was typed, the link is the same',
      <String>[],
      () async {
        for (final String typed in <String>[
          '9876543210',
          '98765 43210',
          '098765-43210',
          '+91 98765 43210',
          '(+91) 98765 43210',
          '00919876543210',
          '919876543210',
        ]) {
          expect(
            WhatsAppLink.digits(typed),
            '919876543210',
            reason: '"$typed" did not normalise',
          );
        }

        for (final String? unusable in <String?>[
          null,
          '',
          '   ',
          'call the landline',
          '12345',
          '9999999999999999999',
        ]) {
          expect(
            WhatsAppLink.digits(unusable),
            isNull,
            reason: '"$unusable" should not become a link',
          );
        }
      },
    );

    acTest(
      'with no number saved it falls back to the share sheet',
      <String>[],
      () async {
        const Person noPhone = Person(id: 2, name: 'Kavita');
        expect(WhatsAppLink.forPerson(noPhone, 'Hi'), isNull);
        expect(WhatsAppLink.routeFor(noPhone), ShareRoute.shareSheet);
        expect(WhatsAppLink.routeFor(meena), ShareRoute.whatsApp);

        final List<Uri> opened = <Uri>[];
        final List<String?> shared = <String?>[];
        final ShareService service = ShareService(
          openUrl: (Uri url) async {
            opened.add(url);
            return true;
          },
          shareSheet: (ShareParams params) async => shared.add(params.text),
        );

        expect(
          await service.sendText(noPhone, 'Hi Kavita'),
          ShareRoute.shareSheet,
        );
        expect(opened, isEmpty);
        expect(shared, <String>['Hi Kavita']);

        expect(await service.sendText(meena, 'Hi Meena'), ShareRoute.whatsApp);
        expect(opened.single.host, 'wa.me');
        expect(shared, hasLength(1));
      },
    );

    /// WhatsApp missing is the same answer as no number saved.
    acTest('a refused intent also falls back', <String>[], () async {
      final List<String?> shared = <String?>[];
      final ShareService service = ShareService(
        openUrl: (Uri url) async => throw const _NoApp(),
        shareSheet: (ShareParams params) async => shared.add(params.text),
      );

      expect(await service.sendText(meena, 'Hi Meena'), ShareRoute.shareSheet);
      expect(shared, <String>['Hi Meena']);
    });
  });

  group('the other three documents', () {
    acTest(
      'the dues report splits who owes from who is owed',
      <String>[],
      () async {
        final PdfReport report = StatementPdfService.duesReport(<PersonBalance>[
          PersonBalance(
            person: meena,
            productDuePaise: 410000,
            cashDuePaise: 50000,
            lastActivity: DateTime(2026, 9, 5),
          ),
          const PersonBalance(
            person: Person(id: 2, name: 'Kavita'),
            productDuePaise: 0,
            cashDuePaise: -20000,
            lastActivity: null,
          ),
          const PersonBalance(
            person: Person(id: 3, name: 'Settled'),
            productDuePaise: 0,
            cashDuePaise: 0,
            lastActivity: null,
          ),
        ], generatedAt: generatedAt);

        expect(report.summaryFor('Owed to you'), 460000);
        expect(report.summaryFor('You owe'), 20000);
        expect(report.summaryFor('Net'), 440000);
        // Somebody square with the book is on neither list.
        expect(
          report.printable
              .expand((PdfSection s) => s.rows)
              .map((PdfRow r) => r.label),
          isNot(contains('Settled')),
        );
        expect(await (await _service()).render(report), isNotEmpty);
      },
    );

    acTest('the stock report values what is on hand', <String>[], () async {
      final PdfReport report = StatementPdfService.stockReport(<StockLevel>[
        const StockLevel(
          product: formula,
          onHand: 3,
          purchased: 5,
          delivered: 2,
          adjusted: 0,
        ),
        const StockLevel(
          product: Product(
            id: 8,
            name: 'Afresh',
            unitLabel: 'pack',
            currentPricePaise: 90000,
          ),
          onHand: 0,
          purchased: 2,
          delivered: 2,
          adjusted: 0,
        ),
      ], generatedAt: generatedAt);

      expect(report.summaryFor('Value at current prices'), 615000);
      expect(report.printable.map((PdfSection s) => s.title), <String>[
        'On hand',
        'Out of stock',
      ]);
      expect(await (await _service()).render(report), isNotEmpty);
    });

    acTest('the monthly expense report renders', <String>[], () async {
      final PdfReport report = StatementPdfService.monthlyExpenseReport(
        year: 2026,
        month: 9,
        expenses: <Expense>[
          Expense(id: 1, date: DateTime(2026, 9, 3), amountPaise: 30000),
        ],
        categoryNames: const <int, String>{},
      );

      expect(report.subtitle, 'From 1 Sep 2026 to 30 Sep 2026');
      expect(report.printable.single.rows.single.label, 'Uncategorised');
      expect(report.printable.single.rows.single.detail, '1 entry');
      expect(report.summaryFor('Total spent'), 30000);
      expect(await (await _service()).render(report), isNotEmpty);
    });

    acTest(
      'a shopping list and a stock list read as sentences',
      <String>[],
      () async {
        final StatementTextService text = StatementTextService(_Settings());

        final String list = await text.shoppingList(const <ShoppingListLine>[
          ShoppingListLine(
            productId: 7,
            productName: 'Formula 1',
            unitLabel: 'tub',
            qty: 3,
            requestCount: 2,
          ),
          ShoppingListLine(
            productId: 8,
            productName: 'Afresh',
            unitLabel: 'pack',
            qty: 1,
            requestCount: 1,
          ),
        ], estimatedTotalPaise: 705000);
        expect(list, contains('3 tub Formula 1 (2 people)'));
        expect(list, contains('1 pack Afresh (1 person)'));
        expect(list, contains(Money.formatWithSymbol(705000)));

        final String stock = await text.inStock(<StockLevel>[
          const StockLevel(
            product: formula,
            onHand: 3,
            purchased: 3,
            delivered: 0,
            adjusted: 0,
          ),
          const StockLevel(
            product: Product(
              id: 8,
              name: 'Afresh',
              unitLabel: 'pack',
              currentPricePaise: 90000,
            ),
            onHand: 0,
            purchased: 0,
            delivered: 0,
            adjusted: 0,
          ),
        ]);
        expect(stock, contains('Formula 1, 3 tub'));
        expect(stock, contains('Afresh, out of stock'));
        expect(stock, contains(Money.formatWithSymbol(615000)));
      },
    );
  });
}

/// An in-memory `app_settings`, so a template and a band can be set without a
/// database.
class _Settings implements SettingsRepository {
  _Settings([Map<String, String>? values])
    : _values = <String, String>{...?values};

  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.of(_values);

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

/// Fails any attempt to open an HTTP client while it is installed, so a
/// renderer that reached for a font over the wire would fail the test rather
/// than quietly work on the machine that has a network.
class _NoNetwork extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw StateError('rendering a PDF must not touch the network');
}

/// Stands in for WhatsApp not being installed.
class _NoApp implements Exception {
  const _NoApp();
}

Future<ByteData> _bytes(String path) async =>
    ByteData.sublistView(await File(path).readAsBytes());

PdfFonts? _cached;

/// The fonts are parsed once and reused, because reading a 550 KB `.ttf` per
/// test is most of this file's runtime.
Future<PdfFonts> _fonts() async =>
    _cached ??= await PdfFonts.load(loadAsset: _bytes);

Future<StatementPdfService> _service() async =>
    StatementPdfService(fonts: await _fonts());

/// The value printed after [label] on a rendered message.
String _labelled(String text, String label) {
  for (final String line in text.split('\n')) {
    if (line.startsWith('$label ')) return line.substring(label.length + 1);
  }
  throw StateError('the message has no "$label" line:\n$text');
}

/// The paise column of the summary row [label] carries in a statement CSV.
int _csvSummary(String csv, String label) {
  for (final List<String> row in _parseCsv(csv)) {
    if (row.length > 6 && row[2] == label) return int.parse(row[6]);
  }
  throw StateError('the CSV has no "$label" row:\n$csv');
}

/// The page content streams of an uncompressed document, joined.
///
/// Only the streams holding text operators are kept, which leaves out the
/// embedded font. Two pages painted identically give the same string here even
/// though the whole files differ, since a PDF also carries a creation
/// timestamp.
Future<String> _pageContent(
  StatementPdfService service,
  PdfReport report,
) async {
  final Uint8List bytes = await service.render(report, compress: false);
  final String raw = latin1.decode(bytes, allowInvalid: true);
  final List<String> streams = <String>[];
  int at = 0;
  while (true) {
    final int start = raw.indexOf('stream', at);
    if (start < 0) break;
    final int end = raw.indexOf('endstream', start);
    if (end < 0) break;
    final String body = raw.substring(start + 'stream'.length, end);
    if (body.contains('BT')) streams.add(body);
    at = end + 'endstream'.length;
  }
  if (streams.isEmpty) {
    throw StateError('the document painted no text');
  }
  return streams.join('\n');
}

int _count(String haystack, String needle) =>
    needle.allMatches(haystack).length;

/// An RFC 4180 reader, written from the standard rather than from the writer,
/// so a round trip proves something.
List<List<String>> _parseCsv(String source) {
  final List<List<String>> rows = <List<String>>[];
  List<String> row = <String>[];
  final StringBuffer field = StringBuffer();
  bool quoted = false;
  int i = 0;
  while (i < source.length) {
    final String char = source[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        quoted = false;
        i++;
        continue;
      }
      field.write(char);
      i++;
      continue;
    }
    if (char == '"' && field.isEmpty) {
      quoted = true;
      i++;
      continue;
    }
    if (char == ',') {
      row.add(field.toString());
      field.clear();
      i++;
      continue;
    }
    if (char == '\r' && i + 1 < source.length && source[i + 1] == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
      i += 2;
      continue;
    }
    field.write(char);
    i++;
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows;
}
