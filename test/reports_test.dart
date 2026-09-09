import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/app_shell.dart';
import 'package:hisaab/components/app_drawer.dart';
import 'package:hisaab/helpers/money.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/providers/app_state.dart';
import 'package:hisaab/screens/collect_screen.dart';
import 'package:hisaab/screens/navigation.dart';
import 'package:hisaab/screens/person_detail_screen.dart';
import 'package:hisaab/screens/reports_screen.dart';
import 'package:hisaab/services/share_service.dart';
import 'package:hisaab/services/statement_csv_service.dart';
import 'package:hisaab/services/statement_pdf_service.dart';

import 'support/harness.dart';
import 'support/memex_ac.dart';

/// The sharing layer, and whether anything can actually reach it.
///
/// Most of this file exists because the renderers under `lib/services/` were
/// built, tested and wired to nothing. Their own tests passed the whole time,
/// which is the point: a unit test on a renderer says the document is right,
/// never that anyone can open it. The guard at the foot of this file is the
/// one that would have caught it.
void main() {
  useAcEmission('test/reports_test.dart');

  /// The date the reports screen is opened on in every test here, so which
  /// month it lands on never depends on when the suite runs.
  final DateTime openedOn = DateTime(2026, 9, 10);

  /// Every row on the reports screen, in the order it paints.
  const List<String> allRows = <String>[
    'Dues summary',
    'Stock report',
    'Monthly expenses',
    'Dues list',
    'Shopping list',
    'What is in stock now',
  ];

  /// What each row says on a book with nothing in it, in paint order.
  const Map<String, String> emptyReasons = <String, String>{
    'Dues summary': 'Every balance is settled, so the page would be empty',
    'Stock report':
        'No products in the catalogue yet, so there is nothing to count',
    'Monthly expenses': 'Nothing was recorded in September 2026',
    'Dues list':
        'Nobody is in the book yet, so the file would hold only headings',
    'Shopping list': 'No requests are pending, so the list would be empty',
    'What is in stock now':
        'No products in the catalogue yet, so there is nothing to list',
  };

  Finder cardFor(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(Card));

  Finder produceIn(String title) => find.descendant(
    of: cardFor(title),
    matching: find.byWidgetPredicate((Widget widget) => widget is FilledButton),
  );

  Future<void> reveal(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(
      find.text(title),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  bool produceEnabled(WidgetTester tester, String title) =>
      (tester.widget(produceIn(title)) as FilledButton).enabled;

  group('the drawer', () {
    acTestWidgets(
      'carries all six destinations and the three dot menu is gone',
      const <String>[],
      (WidgetTester tester) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState();
          await pumpOnSmallPhone(
            tester,
            const AppShell(),
            brightness: Brightness.light,
            state: state,
          );

          expect(
            find.byTooltip('More'),
            findsNothing,
            reason: 'the overflow menu was replaced by the drawer',
          );

          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();

          expect(find.byType(NavigationDrawer), findsOneWidget);
          for (final DrawerDestination destination
              in DrawerDestination.values) {
            expect(
              find.text(destination.label),
              findsWidgets,
              reason: '${destination.label} is not in the drawer',
            );
          }
          expect(
            DrawerDestination.values.length,
            6,
            reason:
                'People, Products, Purchases, Categories, Reports, '
                'Settings',
          );

          // The four daily destinations stay on the bottom bar and Deliver
          // stays the floating button.
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(find.text('Deliver'), findsOneWidget);
        });
      },
    );

    acTestWidgets('Reports opens the reports screen', const <String>[], (
      WidgetTester tester,
    ) async {
      await withQuietLogs(() async {
        final AppState state = await loadedState();
        await pumpOnSmallPhone(
          tester,
          const AppShell(),
          brightness: Brightness.light,
          state: state,
        );

        await tester.tap(find.byTooltip('Open navigation menu'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reports'));
        await tester.pumpAndSettle();

        expect(find.byType(ReportsScreen), findsOneWidget);
        expect(find.text('Dues summary'), findsOneWidget);
      });
    });
  });

  group('the reports screen', () {
    acTestWidgets(
      'every document is listed and can be produced on a book with data',
      const <String>[],
      (WidgetTester tester) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState();
          await pumpOnSmallPhone(
            tester,
            ReportsScreen(now: openedOn),
            brightness: Brightness.light,
            state: state,
          );

          for (final String title in allRows) {
            await reveal(tester, title);
            expect(find.text(title), findsOneWidget);
            expect(
              produceEnabled(tester, title),
              isTrue,
              reason: '$title cannot be produced on a book that has data',
            );
          }
        });
      },
    );

    acTestWidgets(
      'an empty book says why each document would be empty and disables it',
      const <String>[],
      (WidgetTester tester) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState(seeded: false);
          await pumpOnSmallPhone(
            tester,
            ReportsScreen(now: openedOn),
            brightness: Brightness.light,
            state: state,
          );

          for (final MapEntry<String, String> row in emptyReasons.entries) {
            await reveal(tester, row.key);
            expect(
              produceEnabled(tester, row.key),
              isFalse,
              reason:
                  '${row.key} would produce a blank document on an empty book',
            );
            // The reason is on screen rather than left to be guessed at.
            expect(
              find.text(row.value),
              findsOneWidget,
              reason: '${row.key} does not say why it is greyed out',
            );
          }
          expect(emptyReasons.keys, allRows);
        });
      },
    );

    acTestWidgets(
      'the month picker offers the last twelve months',
      const <String>[],
      (WidgetTester tester) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState();
          await pumpOnSmallPhone(
            tester,
            ReportsScreen(now: openedOn),
            brightness: Brightness.light,
            state: state,
          );

          await reveal(tester, 'Monthly expenses');
          expect(find.text('September 2026'), findsOneWidget);
          await tester.tap(find.text('September 2026'));
          await tester.pumpAndSettle();

          expect(find.text('October 2025'), findsOneWidget);
          await tester.tap(find.text('August 2026'));
          await tester.pumpAndSettle();

          await reveal(tester, 'Monthly expenses');
          expect(find.text('August 2026'), findsOneWidget);
        });
      },
    );
  });

  group('both new surfaces hold a small phone', () {
    for (final Brightness brightness in Brightness.values) {
      acTestWidgets('the drawer, ${brightness.name}', const <String>[], (
        WidgetTester tester,
      ) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState();
          await pumpOnSmallPhone(
            tester,
            const AppShell(),
            brightness: brightness,
            state: state,
          );
          await tester.tap(find.byTooltip('Open navigation menu'));
          await tester.pumpAndSettle();
          expect(find.text('Settings'), findsOneWidget);
        });
      });

      acTestWidgets(
        'the reports screen, ${brightness.name}',
        const <String>[],
        (WidgetTester tester) async {
          await withQuietLogs(() async {
            final AppState state = await loadedState();
            await pumpOnSmallPhone(
              tester,
              ReportsScreen(now: openedOn),
              brightness: brightness,
              state: state,
            );
            expect(find.text('Reports'), findsOneWidget);
          });
        },
      );
    }
  });

  group('the four PDF reports', () {
    /// Verifies ac-21: each document parses as a PDF and carries the figure
    /// the layout was built with.
    acTest(
      'a statement renders and carries the due figure',
      <String>['ac-21'],
      () async {
        final Statement statement = sampleStatement();
        final PdfReport report = StatementPdfService.statementReport(statement);
        expect(report.summaryFor('Due'), statement.netPaise);
        await expectParses(report);
      },
    );

    /// Verifies ac-21.
    acTest(
      'the dues report renders and carries what is owed in',
      <String>['ac-21'],
      () async {
        final PdfReport report = StatementPdfService.duesReport(
          sampleBalances(),
          generatedAt: DateTime(2026, 9, 10),
        );
        expect(
          report.summaryFor('Owed to you'),
          560000,
          reason: 'Meera owes 4,100 on products and 1,500 in cash',
        );
        expect(report.summaryFor('You owe'), 75050);
        expect(report.summaryFor('Net'), 560000 - 75050);
        await expectParses(report);
      },
    );

    /// Verifies ac-21.
    acTest(
      'the stock report renders and carries the valuation',
      <String>['ac-21'],
      () async {
        final PdfReport report = StatementPdfService.stockReport(
          sampleStockLevels(),
          generatedAt: DateTime(2026, 9, 10),
        );
        expect(
          report.summaryFor('Value at current prices'),
          205000,
          reason: 'one shake on hand at 2,050, and the tea is out',
        );
        await expectParses(report);
      },
    );

    /// Verifies ac-21.
    acTest(
      'the monthly expense report renders and keeps a saving out of '
      'what was spent',
      <String>['ac-21'],
      () async {
        final PdfReport report = StatementPdfService.monthlyExpenseReport(
          year: 2026,
          month: 9,
          expenses: sampleExpenses(),
          categoryNames: <int, String>{1: 'Travel'},
          purchases: samplePurchases(),
        );
        expect(
          report.summaryFor('Expenses'),
          250000,
          reason: '450 on travel and 2,050 used at home',
        );
        expect(report.summaryFor('Paid for stock'), 620000);
        expect(report.summaryFor('Total spent'), 870000);
        await expectParses(report);
      },
    );
  });

  group('the dues CSV', () {
    final List<PersonBalance> balances = <PersonBalance>[
      PersonBalance(
        person: const Person(id: 1, name: 'Reddy, Anita', phone: '9876500001'),
        productDuePaise: 410000,
        cashDuePaise: 150000,
        lastActivity: DateTime(2026, 9, 5),
      ),
      PersonBalance(
        person: const Person(id: 2, name: 'Sunita Rao'),
        productDuePaise: -75050,
        cashDuePaise: 0,
        lastActivity: DateTime(2026, 8, 30),
      ),
    ];

    acTest(
      'every person is listed and a comma in a name is quoted',
      const <String>[],
      () {
        final String csv = StatementCsvService.dues(balances);
        expect(
          csv,
          contains('"Reddy, Anita"'),
          reason: 'an unquoted comma would split the name across two columns',
        );

        final List<List<String>> rows = parseCsv(csv);
        expect(rows.first.first, 'Name');
        expect(rows.length, 3, reason: 'a heading and 2 people');
        expect(rows[1][0], 'Reddy, Anita');
        expect(rows[2][0], 'Sunita Rao');
        expect(rows[1][6], '5 Sep 2026');
      },
    );

    /// Verifies ac-20: the CSV and the PDF are read off the same balances, so
    /// a figure that differs between them is a renderer adding up on its own.
    acTest('the totals match the dues PDF row for row', <String>['ac-20'], () {
      final List<List<String>> rows = parseCsv(
        StatementCsvService.dues(balances),
      );
      final PdfReport report = StatementPdfService.duesReport(
        balances,
        generatedAt: DateTime(2026, 9, 10),
      );

      final PdfRow anita = report.printable.first.rows.single;
      expect(anita.label, 'Reddy, Anita');
      expect(rows[1][5], '${anita.amountPaise}');
      expect(rows[1][4], anita.amountText);
      expect(rows[1][4], Money.format(560000));

      final PdfRow sunita = report.printable[1].rows.single;
      expect(sunita.label, 'Sunita Rao');
      expect(int.parse(rows[2][5]), -75050, reason: 'Sunita is in credit');
      expect(rows[2][5], '${sunita.amountPaise}');
      expect(rows[2][4], sunita.amountText);
    });
  });

  group('the two person messages', () {
    acTestWidgets(
      'a reminder is offered to someone who owes and withheld from someone '
      'who does not',
      const <String>[],
      (WidgetTester tester) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState();
          expect(state.productDueFor(1), 210000, reason: 'Meera is behind');
          expect(state.productDueFor(2), 0, reason: 'Sunita is square');

          await pumpOnSmallPhone(
            tester,
            const PersonDetailScreen(person: kMeera),
            brightness: Brightness.light,
            state: state,
          );
          await tester.tap(find.byTooltip('Send and share'));
          await tester.pumpAndSettle();
          expect(find.text('Send a reminder'), findsOneWidget);
          expect(find.text('Send a receipt'), findsOneWidget);
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
        });

        await withQuietLogs(() async {
          final AppState state = await loadedState();
          await pumpOnSmallPhone(
            tester,
            const PersonDetailScreen(person: kSunita),
            brightness: Brightness.light,
            state: state,
          );
          await tester.tap(find.byTooltip('Send and share'));
          await tester.pumpAndSettle();
          expect(
            find.text('Send a reminder'),
            findsNothing,
            reason: 'nudging someone who owes nothing is how a favour ends',
          );
          expect(find.text('Send a receipt'), findsOneWidget);
        });
      },
    );

    acTestWidgets('the reminder names what is open', const <String>[], (
      WidgetTester tester,
    ) async {
      await withQuietLogs(() async {
        final AppState state = await loadedState();
        final _Capture capture = _Capture();
        await pumpOnSmallPhone(
          tester,
          PersonDetailScreen(person: kMeera, share: capture.service),
          brightness: Brightness.light,
          state: state,
        );

        await tester.tap(find.byTooltip('Send and share'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Send a reminder'));
        await tester.pumpAndSettle();

        expect(capture.text, isNotNull);
        expect(capture.text, contains('Meera Joshi'));
        expect(capture.text, contains(Money.formatWithSymbol(210000)));
      });
    });

    acTestWidgets(
      'the receipt offered after a collection names the payment just taken, '
      'not the lifetime figure',
      const <String>[],
      (WidgetTester tester) async {
        await withQuietLogs(() async {
          final AppState state = await loadedState();
          final _Capture capture = _Capture();

          await pumpOnSmallPhone(
            tester,
            Scaffold(
              body: Builder(
                builder: (BuildContext context) => TextButton(
                  onPressed: () => openScreen(
                    context,
                    CollectScreen(person: kMeera, share: capture.service),
                  ),
                  child: const Text('Open collect'),
                ),
              ),
            ),
            brightness: Brightness.light,
            state: state,
          );
          await tester.tap(find.text('Open collect'));
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextFormField).first, '500');
          await tester.pump();
          await tapAfterScroll(tester, find.text('Record payment'));
          await tester.pumpAndSettle();

          expect(
            find.text('Send receipt'),
            findsOneWidget,
            reason: 'the receipt is offered, never sent on its own',
          );
          expect(capture.text, isNull, reason: 'nothing has been sent yet');

          await tester.tap(find.text('Send receipt'));
          await tester.pumpAndSettle();

          expect(
            capture.text,
            contains(Money.formatWithSymbol(50000)),
            reason: 'the receipt names the 500 that was just handed over',
          );
          expect(
            capture.text,
            isNot(contains(Money.formatWithSymbol(250000))),
            reason: '2,500 is everything ever paid, which is not this receipt',
          );
          expect(
            capture.text,
            contains(Money.formatWithSymbol(160000)),
            reason: '1,600 is what is left open after this payment',
          );
        });
      },
    );
  });

  group('nothing can render into a vacuum again', () {
    /// The guard.
    ///
    /// Every public entry point that produces a whole document has to be
    /// called from a screen or a component. A renderer that stops being
    /// called still passes its own unit tests, which is exactly how four PDFs,
    /// four messages and two CSVs came to be unreachable at once.
    ///
    /// The declared list is checked against the services themselves below, so
    /// a renderer added later cannot slip past by not being listed here.
    acTest(
      'every document renderer is reached from a screen or a component',
      const <String>[],
      () {
        final String ui = uiSource();
        for (final MapEntry<String, String> entry in renderers.entries) {
          expect(
            RegExp(entry.value).hasMatch(ui),
            isTrue,
            reason:
                '${entry.key} produces a document nothing under lib/screens or '
                'lib/components opens, so no one can reach it',
          );
        }
      },
    );

    acTest(
      'the declared list still matches the services',
      const <String>[],
      () {
        final Set<String> pdf = named(
          'lib/services/statement_pdf_service.dart',
          RegExp(r'static PdfReport ([a-z]\w*)\('),
        );
        expect(pdf, <String>{
          'statementReport',
          'duesReport',
          'stockReport',
          'monthlyExpenseReport',
        });

        final Set<String> text = named(
          'lib/services/statement_text_service.dart',
          RegExp(r'\n  Future<String> ([a-z]\w*)\('),
        );
        expect(text, <String>{
          'statement',
          'reminder',
          'receipt',
          'shoppingList',
          'inStock',
        });

        // encode and escape build a field and a file out of rows a caller
        // already has, so neither is a document. Named rather than filtered by
        // shape, so a third helper forces the same decision to be made again.
        final Set<String> csv = named(
          'lib/services/statement_csv_service.dart',
          RegExp(r'\n  static String ([a-z]\w*)\('),
        )..removeAll(<String>{'encode', 'escape'});
        expect(csv, <String>{'dues', 'statement'});

        expect(
          pdf.length + text.length + csv.length,
          renderers.length,
          reason: 'a renderer exists that the guard above does not check',
        );
      },
    );
  });
}

/// Each document renderer against the shape a call to it takes, matched
/// against the UI source with its whitespace squeezed out so reformatting a
/// call site cannot break the guard.
const Map<String, String> renderers = <String, String>{
  'StatementPdfService.statementReport':
      r'StatementPdfService\.statementReport\(',
  'StatementPdfService.duesReport': r'StatementPdfService\.duesReport\(',
  'StatementPdfService.stockReport': r'StatementPdfService\.stockReport\(',
  'StatementPdfService.monthlyExpenseReport':
      r'StatementPdfService\.monthlyExpenseReport\(',
  'StatementCsvService.dues': r'StatementCsvService\.dues\(',
  'StatementCsvService.statement': r'StatementCsvService\.statement\(',
  // The text service is called on an instance, so the receiver is a variable
  // or a constructor call rather than the class name. The lookbehind is what
  // keeps StatementCsvService.statement from answering for the message.
  'StatementTextService.statement': r'(?<!CsvService)\.statement\(',
  'StatementTextService.reminder': r'\.reminder\(',
  'StatementTextService.receipt': r'\.receipt\(',
  'StatementTextService.shoppingList': r'\.shoppingList\(',
  'StatementTextService.inStock': r'\.inStock\(',
};

/// Every Dart file under the two directories a person can actually reach,
/// joined and squeezed.
String uiSource() {
  final StringBuffer out = StringBuffer();
  for (final String directory in <String>['lib/screens', 'lib/components']) {
    final Directory folder = Directory(directory);
    expect(folder.existsSync(), isTrue, reason: 'run this from the repo root');
    for (final FileSystemEntity entity in folder.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      out.write(entity.readAsStringSync().replaceAll(RegExp(r'\s+'), ''));
      out.write('\n');
    }
  }
  return out.toString();
}

/// The first capture group of every match of [pattern] in [path].
Set<String> named(String path, RegExp pattern) {
  final String source = File(path).readAsStringSync();
  return <String>{
    for (final RegExpMatch match in pattern.allMatches(source)) match.group(1)!,
  };
}

/// Renders [report] with the committed font and checks the bytes are a PDF a
/// reader could open.
Future<void> expectParses(PdfReport report) async {
  final StatementPdfService service = StatementPdfService(fonts: await fonts());
  final Uint8List bytes = await service.render(report);
  final String raw = latin1.decode(bytes, allowInvalid: true);
  expect(raw.startsWith('%PDF-'), isTrue);
  expect(raw.trimRight().endsWith('%%EOF'), isTrue);
  expect(raw, matches(RegExp(r'/Type\s*/Catalog')));
  expect(raw, matches(RegExp(r'/Type\s*/Page[^s]')));
  expect(raw, matches(RegExp(r'/BaseFont\s*/NotoSans-Regular')));
}

PdfFonts? _cachedFonts;

/// Parsed once: reading two 550 KB faces per test is most of the runtime.
Future<PdfFonts> fonts() async => _cachedFonts ??= await PdfFonts.load(
  loadAsset: (String path) async =>
      ByteData.sublistView(await File(path).readAsBytes()),
);

/// An RFC 4180 reader, written from the standard rather than from the writer.
List<List<String>> parseCsv(String source) {
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

/// Stands in for the share sheet, so a test reads the message that would have
/// gone out instead of standing up a method channel.
class _Capture {
  ShareParams? params;

  String? get text => params?.text;

  ShareService get service => ShareService(
    // WhatsApp not being installed is the path that lands on the sheet, which
    // is the one a test can read.
    openUrl: (Uri url) async => false,
    shareSheet: (ShareParams sent) async => params = sent,
  );
}
