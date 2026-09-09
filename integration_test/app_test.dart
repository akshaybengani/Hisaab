/// The journeys, driven against the real app and the real sqflite file on a
/// device.
///
/// These are not widget tests with a fake repository behind them. Each one
/// boots `main()`, which opens the database the shipped app opens, and then
/// taps through the screens the way the owner of the book would. That is the
/// only way to catch a journey that works against a fake and not against
/// storage, or a screen that a person cannot actually reach.
///
/// Every test starts from an empty book. `setUp` deletes the file before the
/// app boots, so the second run of the suite sees exactly what the first one
/// saw.
///
/// Money is an `int` count of paise throughout: 2,050 rupees is 205000.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/app_shell.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/main.dart' as app;
import 'package:hisaab/models/models.dart';
import 'package:hisaab/providers/app_state.dart';
import 'package:hisaab/repositories/sqflite_repositories.dart';
import 'package:hisaab/services/backup_service.dart';
import 'package:hisaab/services/database_service.dart';
import 'package:hisaab/services/statement_pdf_service.dart';
import 'package:hisaab/services/statement_text_service.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../test/support/memex_ac.dart';

/// The reporter reads `MEMEX_EMIT` out of the process environment, and a run
/// on a device carries the device's environment rather than the one the
/// command was typed into. So emission is opt in here, through
/// `--dart-define=MEMEX_EMIT_INTEGRATION=on`, and stays off otherwise. Without
/// it nothing is ever flushed, which is what keeps a device run from posting
/// events nobody asked for.
const String _emitFlag = String.fromEnvironment('MEMEX_EMIT_INTEGRATION');

/// Counts what the user had to do. Reset at the start of a flow that makes a
/// claim about how few steps it takes.
int _interactions = 0;

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (_emitFlag == 'on') useAcEmission('integration_test/app_test.dart');

  AppState? live;

  Future<String> databaseFile() async =>
      p.join(await getDatabasesPath(), DatabaseService.fileName);

  setUp(() async {
    await deleteDatabase(await databaseFile());
    _interactions = 0;
  });

  tearDown(() async {
    final AppState? state = live;
    live = null;
    if (state != null) {
      await (state.repositories as SqfliteRepositories).database.close();
    }
  });

  /// Boots the shipped `main()` against the file just deleted and hands back
  /// the state it built, so a test can read what storage actually holds.
  Future<AppState> boot(WidgetTester tester) async {
    await app.main();
    await tester.pumpAndSettle();
    final AppState state = tester
        .widget<app.HisaabApp>(find.byType(app.HisaabApp))
        .state;
    live = state;
    return state;
  }

  // ------------------------------------------------------------------ ac-1

  acTestWidgets(
    'a cold start with an empty book reaches a person, a product, a delivery '
    'and a total on the home screen',
    <String>['ac-1'],
    (WidgetTester tester) async {
      await boot(tester);

      expect(
        find.textContaining('Add the first person to start a book'),
        findsOneWidget,
        reason: 'the book has to start empty, whatever the last run left',
      );

      await addPerson(tester, 'Priya');
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await deliver(
        tester,
        lines: <DeliveryLine>[const DeliveryLine('tub', '2')],
      );

      // Nothing below this line navigates or filters. Whatever the home
      // screen shows now is what the owner sees when the delivery is saved.
      expect(find.byType(AppShell), findsOneWidget);
      expect(
        find.widgetWithText(AppBar, 'Dues'),
        findsOneWidget,
        reason: 'saving a delivery lands back on the home destination',
      );

      expect(
        find.text('Priya').hitTestable(),
        findsOneWidget,
        reason: 'the person is on screen without scrolling or filtering',
      );
      expect(
        find
            .descendant(
              of: find.widgetWithText(ListTile, 'Priya'),
              matching: find.text('₹4,100'),
            )
            .hitTestable(),
        findsOneWidget,
        reason: '2 tubs at 2,050 is 4,100 against Priya',
      );
      expect(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('Cash out'),
                matching: find.byType(Card),
              ),
              matching: find.text('₹4,100'),
            )
            .hitTestable(),
        findsOneWidget,
        reason: 'the one figure for everything that is out reads 4,100',
      );
      expect(find.text('Waiting with 1 person.'), findsOneWidget);
    },
  );

  // ------------------------------------------------------------------ ac-2

  acTestWidgets(
    'one handover of two products moves the balance and both on-hand figures '
    'at once',
    <String>['ac-2'],
    (WidgetTester tester) async {
      await boot(tester);
      await addPerson(tester, 'Priya');
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await addProduct(tester, name: 'Herbal tea', unit: 'pack', price: '950');

      // Stock to hand out, built through the stepper on the stock card.
      await openStock(tester);
      for (int i = 0; i < 2; i++) {
        await tap(tester, find.byTooltip('One more').at(0));
      }
      for (int i = 0; i < 3; i++) {
        await tap(tester, find.byTooltip('One more').at(1));
      }
      expect(find.text('2 tubs on hand, worth ₹4,100'), findsOneWidget);
      expect(find.text('3 packs on hand, worth ₹2,850'), findsOneWidget);

      // The claim is about how few steps the handover itself takes, so the
      // count starts here rather than at boot.
      _interactions = 0;
      await deliver(
        tester,
        lines: <DeliveryLine>[
          const DeliveryLine('tub', '1'),
          const DeliveryLine('pack', '2', product: 'Herbal tea'),
        ],
      );
      expect(
        _interactions,
        lessThanOrEqualTo(8),
        reason:
            'two products to one person should be a handful of taps, not a '
            'form filled twice',
      );

      // Saving pops back to wherever Deliver was opened from, which here is
      // the stock tab, so the dues list needs asking for.
      await openDues(tester);
      await see(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Priya'),
          matching: find.text('₹3,950'),
        ),
        reason: '1 tub at 2,050 plus 2 packs at 950 is 3,950',
      );

      await openStock(tester);
      expect(
        find.text('1 tub on hand, worth ₹2,050'),
        findsOneWidget,
        reason: 'the tub that went out left stock the moment it was recorded',
      );
      expect(
        find.text('1 pack on hand, worth ₹950'),
        findsOneWidget,
        reason: 'both packs that went out left stock too',
      );
    },
  );

  // ------------------------------------------------------------------ ac-3

  acTestWidgets(
    'two deliveries and a part payment read paid and partly paid, then square',
    <String>['ac-3'],
    (WidgetTester tester) async {
      await boot(tester);
      await addPerson(tester, 'Priya');
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await addProduct(tester, name: 'Herbal tea', unit: 'pack', price: '950');

      // 2 at 205000, then 1 at 95000. 505000 out in total.
      await deliver(
        tester,
        lines: <DeliveryLine>[const DeliveryLine('tub', '2')],
      );
      await deliver(
        tester,
        lines: <DeliveryLine>[
          const DeliveryLine('pack', '1', product: 'Herbal tea'),
        ],
      );
      await see(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Priya'),
          matching: find.text('₹5,050'),
        ),
      );

      // A payment of 450000, which leaves 55000.
      await tap(tester, find.widgetWithText(ListTile, 'Priya'));
      await type(
        tester,
        find.widgetWithText(TextFormField, 'Amount being paid'),
        '4500',
      );
      expect(
        find.text('₹550 still owed after this.'),
        findsOneWidget,
        reason: 'the screen does the arithmetic before the money is taken',
      );
      await tap(tester, find.text('Record payment'));

      await see(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Priya'),
          matching: find.text('₹550'),
        ),
        reason: '505000 out less 450000 in leaves 55000',
      );

      await openPerson(tester, 'Priya');
      // The whole group is one card, so scrolling to its title puts every
      // delivery line and every chip in the tree at once.
      await see(tester, find.text('Product dues'));
      expect(
        find.text('Paid'),
        findsOneWidget,
        reason: 'the 4,100 delivery is covered in full by money',
      );
      expect(
        find.text('Partly paid'),
        findsOneWidget,
        reason: 'the 950 delivery is covered by the 400 that was left over',
      );
      expect(find.text('Unpaid'), findsNothing);
      await see(tester, find.text('Priya owes you'));

      // The rest.
      await tap(tester, find.text('Collect payment'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Amount being paid'),
        findsOneWidget,
      );
      expect(
        find.text('550'),
        findsOneWidget,
        reason: 'the amount is prefilled with the exact balance',
      );
      expect(find.text('Nothing left after this.'), findsOneWidget);
      await tap(tester, find.text('Record payment'));

      await see(tester, find.text('Product dues'));
      expect(
        find.text('Paid'),
        findsNWidgets(2),
        reason: 'both deliveries are now covered by money, not conceded',
      );
      expect(find.text('Partly paid'), findsNothing);
      await see(
        tester,
        find.text('Settled'),
        reason: 'the net card reads settled once nothing is left',
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Everyone is square'),
        findsOneWidget,
        reason: 'the home screen says so without the owner adding anything up',
      );
    },
  );

  // ------------------------------------------------------------------ ac-4

  acTestWidgets(
    'a statement renders as text and as a PDF carrying the right figures, '
    'with nothing reaching the network',
    <String>['ac-4'],
    (WidgetTester tester) async {
      final AppState state = await boot(tester);
      await addPerson(tester, 'Priya');
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await addProduct(tester, name: 'Herbal tea', unit: 'pack', price: '950');
      await deliver(
        tester,
        lines: <DeliveryLine>[const DeliveryLine('tub', '2')],
      );
      await deliver(
        tester,
        lines: <DeliveryLine>[
          const DeliveryLine('pack', '1', product: 'Herbal tea'),
        ],
      );
      await tap(tester, find.widgetWithText(ListTile, 'Priya'));
      await type(
        tester,
        find.widgetWithText(TextFormField, 'Amount being paid'),
        '4500',
      );
      await tap(tester, find.text('Record payment'));

      final Person person = state.people.single;
      final Statement statement = state.statementFor(person)!;

      late final String message;
      late final Uint8List pdf;
      await HttpOverrides.runZoned<Future<void>>(
        () async {
          message = await StatementTextService(
            state.repositories.settings,
          ).statement(statement);
          final StatementPdfService service = await StatementPdfService.load(
            settings: state.repositories.settings,
          );
          pdf = await service.render(
            StatementPdfService.statementReport(
              statement,
              upi: state.setting(SettingKeys.upiHandle),
            ),
            // Uncompressed so the test can read what was actually painted
            // rather than trusting the object that was handed to the painter.
            compress: false,
          );
        },
        createHttpClient: (SecurityContext? context) => throw StateError(
          'a statement must render with the radio off, and this one tried to '
          'open an HTTP connection',
        ),
      );

      expect(message, contains('Hi Priya'));
      expect(message, contains('Formula 1 (2 tub at 2,050), ₹4,100'));
      expect(message, contains('Herbal tea (1 pack at 950), ₹950'));
      expect(message, contains('Payment received, -₹4,500'));
      expect(message, contains('Total ₹5,050'));
      expect(message, contains('Paid ₹4,500'));
      expect(message, contains('Due ₹550'));

      final String raw = latin1.decode(pdf, allowInvalid: true);
      expect(raw.startsWith('%PDF-'), isTrue);
      expect(raw.trimRight().endsWith('%%EOF'), isTrue);

      final Set<String> painted = _paintedWords(raw);
      expect(painted, contains('Priya'));
      expect(painted, containsAll(<String>['Product', 'dues']));
      expect(painted, containsAll(<String>['Formula', 'Herbal', 'tea']));
      expect(
        painted,
        contains('4,100'),
        reason: '2 tubs at 2,050 printed as one line total',
      );
      expect(
        painted,
        contains('950'),
        reason: 'the pack printed at its own price',
      );
      expect(painted, containsAll(<String>['Payment', 'received', '-4,500']));
      expect(painted, containsAll(<String>['Total', '₹5,050']));
      expect(
        painted,
        containsAll(<String>['Due', '₹550']),
        reason:
            'the rupee sign comes from the bundled face, so this also proves '
            'the font travelled with the app',
      );
    },
  );

  // ------------------------------------------------------------------ ac-5

  acTestWidgets(
    'a price change leaves the delivery already recorded alone and prices the '
    'next one',
    <String>['ac-5'],
    (WidgetTester tester) async {
      await boot(tester);
      await addPerson(tester, 'Priya');
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await deliver(
        tester,
        lines: <DeliveryLine>[const DeliveryLine('tub', '1')],
      );

      await openPerson(tester, 'Priya');
      await see(tester, find.textContaining('1 tub at 2,050'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The price moves to 250000.
      await tap(tester, find.byTooltip('More'));
      await tap(tester, find.text('Products'));
      await tap(tester, find.widgetWithText(ListTile, 'Formula 1'));
      await type(
        tester,
        find.widgetWithText(TextFormField, 'Current price'),
        '2500',
      );
      await tap(tester, find.text('Save product'));
      await tester.pageBack();
      await tester.pumpAndSettle();

      await see(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Priya'),
          matching: find.text('₹2,050'),
        ),
        reason: 'the balance is built from the price the tub went out at',
      );
      await openPerson(tester, 'Priya');
      await see(
        tester,
        find.textContaining('1 tub at 2,050'),
        reason: 'the recorded delivery keeps its own price',
      );
      expect(find.textContaining('1 tub at 2,500'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();

      // The next handover picks the new price up.
      await tap(tester, find.widgetWithText(FloatingActionButton, 'Deliver'));
      expect(
        find.text('2,500'),
        findsOneWidget,
        reason: 'the line prefills from the price as it is today',
      );
      expect(find.text('Line total ₹2,500'), findsOneWidget);
      await tap(tester, find.text('Save delivery'));

      await see(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Priya'),
          matching: find.text('₹4,550'),
        ),
        reason: '2,050 at the old price plus 2,500 at the new one',
      );
      await openPerson(tester, 'Priya');
      await see(tester, find.text('Product dues'));
      expect(find.textContaining('1 tub at 2,050'), findsOneWidget);
      expect(find.textContaining('1 tub at 2,500'), findsOneWidget);
    },
  );

  // ------------------------------------------------------------------ ac-6

  acTestWidgets(
    'the stepper and a recount move the figure on hand, and the history '
    'explains it',
    <String>['ac-6'],
    (WidgetTester tester) async {
      await boot(tester);
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await openStock(tester);

      expect(find.text('0 tubs on hand, worth ₹0'), findsOneWidget);
      for (int i = 0; i < 3; i++) {
        await tap(tester, find.byTooltip('One more'));
      }
      expect(
        find.text('3 tubs on hand, worth ₹6,150'),
        findsOneWidget,
        reason: 'three taps of the stepper are three movements, not a counter',
      );

      await tap(tester, find.byTooltip('Stock actions'));
      await tap(tester, find.text('Recount'));
      await type(
        tester,
        find.widgetWithText(TextField, 'Counted on the shelf'),
        '5',
      );
      await tap(tester, find.text('Save count'));

      expect(
        find.text('5 tubs on hand, worth ₹10,250'),
        findsOneWidget,
        reason: 'the figure follows the count that was actually made',
      );
      expect(find.text('Bought 0, out 0, corrected 5'), findsOneWidget);

      await tap(tester, find.byTooltip('Stock actions'));
      await tap(tester, find.text('Movement history'));

      await see(tester, find.text('Recount'));
      expect(
        find.text('Manual'),
        findsNWidgets(3),
        reason: 'each stepper tap left a row behind',
      );
      expect(find.text('+1'), findsNWidgets(3));
      expect(find.text('+2'), findsOneWidget);
      expect(find.textContaining('Counted 5 tubs'), findsOneWidget);
      expect(
        find.text('5 left'),
        findsOneWidget,
        reason: 'the running figure lands on the number the card shows',
      );
    },
  );

  // ------------------------------------------------------------------ ac-7

  acTestWidgets(
    'the book exports to a file that describes what is in it, and restores '
    'from it',
    <String>['ac-7'],
    (WidgetTester tester) async {
      final AppState state = await boot(tester);
      await addPerson(tester, 'Priya');
      await addProduct(tester, name: 'Formula 1', unit: 'tub', price: '2050');
      await addProduct(tester, name: 'Herbal tea', unit: 'pack', price: '950');
      await deliver(
        tester,
        lines: <DeliveryLine>[
          const DeliveryLine('tub', '2'),
          const DeliveryLine('pack', '1', product: 'Herbal tea'),
        ],
      );
      await tap(tester, find.widgetWithText(ListTile, 'Priya'));
      await type(
        tester,
        find.widgetWithText(TextFormField, 'Amount being paid'),
        '4500',
      );
      await tap(tester, find.text('Record payment'));

      final Database db = (state.repositories as SqfliteRepositories).database;
      final String path = p.join(await getDatabasesPath(), 'export.json');
      final File written = await BackupService(db).exportToFile(path);

      expect(written.existsSync(), isTrue);
      final String source = await written.readAsString();
      expect(source.length, greaterThan(0));

      final BackupSummary summary = BackupService.summarise(source);
      expect(summary.schemaVersion, DatabaseService.latestVersion);
      expect(summary.rowCounts['people'], 1);
      expect(summary.rowCounts['products'], 2);
      expect(summary.rowCounts['deliveries'], 1);
      expect(
        summary.rowCounts['delivery_items'],
        2,
        reason: 'the handover carried two products',
      );
      expect(summary.rowCounts['money_entries'], 1);
      expect(summary.rowCounts['purchases'], 0);
      expect(summary.rowCounts['expenses'], 0);
      expect(summary.isEmpty, isFalse);

      // The file has to carry the figures, not just the row counts.
      final Map<String, Object?> decoded =
          jsonDecode(source) as Map<String, Object?>;
      final Map<String, Object?> tables =
          decoded['tables']! as Map<String, Object?>;
      final List<Object?> items = tables['delivery_items']! as List<Object?>;
      expect(
        items
            .map((Object? row) => (row! as Map<String, Object?>)['qty'])
            .toList(),
        <int>[2, 1],
      );
      expect(
        items
            .map(
              (Object? row) =>
                  (row! as Map<String, Object?>)['unit_price_paise'],
            )
            .toList(),
        <int>[205000, 95000],
        reason: 'the snapshotted prices travel with the delivery lines',
      );
      expect(source, contains('Priya'));

      // Restoring replaces the book, so the round trip is provable inside one
      // run: add someone who is not in the file, then put the file back.
      await addPerson(tester, 'Someone else');
      expect(state.people.length, 2);

      final BackupSummary restored = await BackupService(db).importJson(source);
      expect(restored.rowCounts['people'], 1);
      await state.load();
      await tester.pumpAndSettle();

      expect(state.people.single.name, 'Priya');
      expect(find.text('Someone else'), findsNothing);
      await see(
        tester,
        find.descendant(
          of: find.widgetWithText(ListTile, 'Priya'),
          matching: find.text('₹550'),
        ),
        reason: 'the restored book carries the same balance it exported with',
      );
    },
  );

  acTestWidgets(
    'the owner can reach the export from settings',
    <String>['ac-7'],
    (WidgetTester tester) async {
      await boot(tester);
      await tap(tester, find.byTooltip('More'));
      await tap(tester, find.text('Settings'));
      await bring(tester, find.text('Back up to a file'));

      final ListTile backup = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Back up to a file'),
      );
      expect(
        backup.enabled,
        isTrue,
        reason:
            'BackupService is implemented and covered, but AppShell builds a '
            'SettingsScreen with no backup callback, so the tile is dead and '
            'nobody can export their book from the app',
      );
      expect(
        backup.onTap,
        isNotNull,
        reason: 'a tile that does nothing when tapped is not an export',
      );
    },
  );
}

// -------------------------------------------------------------------- steps

/// One line of a handover: the unit the product is counted in, the quantity,
/// and the product to pick where it is not the one the form defaults to.
class DeliveryLine {
  const DeliveryLine(this.unit, this.qty, {this.product});

  final String unit;
  final String qty;
  final String? product;
}

/// Everything the screen is currently reading, for a failure message.
String onScreen() => find
    .byType(Text)
    .evaluate()
    .map((Element element) => (element.widget as Text).data)
    .whereType<String>()
    .join(' | ');

/// The list the current screen scrolls, ignoring the sideways scroller every
/// text field carries around with it.
Finder scroller() => find
    .byWidgetPredicate(
      (Widget widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

/// Drags the current list until [target] turns up, or gives up.
Future<void> sweep(WidgetTester tester, Finder target, double step) async {
  final Finder list = scroller();
  if (list.evaluate().isEmpty) return;
  for (int i = 0; i < 25 && target.evaluate().isEmpty; i++) {
    await tester.drag(list, Offset(0, step));
    await tester.pumpAndSettle();
  }
}

/// Scrolls [target] into view.
///
/// The keyboard is let go of before scrolling. A focused field asks its list
/// to keep the caret on screen, so it drags the list back every time the test
/// scrolls past it and whatever sits below never arrives. On a device that
/// keyboard also takes a third of the form with it.
Future<void> bring(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }
  if (target.evaluate().isEmpty) await sweep(tester, target, -160);
  if (target.evaluate().isEmpty) await sweep(tester, target, 160);
  if (target.evaluate().isEmpty) {
    throw StateError(
      'nothing matched ${target.describeMatch(Plurality.many)}, so the journey stopped here. '
      'The screen reads: ${onScreen()}',
    );
  }
  if (find
      .ancestor(of: target, matching: find.byType(Scrollable))
      .evaluate()
      .isNotEmpty) {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
  }
}

/// Looks for [target], scrolling the way a person would before deciding it
/// is not there. A list only builds what is near the viewport, so an
/// assertion that skips this is asserting the scroll position.
Future<void> see(WidgetTester tester, Finder target, {String? reason}) async {
  if (target.evaluate().isEmpty) {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await sweep(tester, target, -160);
    if (target.evaluate().isEmpty) await sweep(tester, target, 160);
  }
  expect(target, findsOneWidget, reason: reason);
}

/// One thing the user did.
Future<void> tap(WidgetTester tester, Finder target) async {
  _interactions++;
  await bring(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// One thing the user typed. The field is let go of afterwards, so the
/// keyboard stops holding the bottom of the form off screen.
Future<void> type(WidgetTester tester, Finder target, String text) async {
  _interactions++;
  await bring(tester, target);
  await tester.enterText(target, text);
  await tester.pumpAndSettle();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

/// Adds a person through the people screen and comes back to the shell.
Future<void> addPerson(WidgetTester tester, String name) async {
  await tap(tester, find.byTooltip('People'));
  await tap(tester, find.byTooltip('Add person'));
  await type(tester, find.widgetWithText(TextFormField, 'Name'), name);
  await tap(tester, find.text('Save person'));
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// Adds a product through the products screen and comes back to the shell.
Future<void> addProduct(
  WidgetTester tester, {
  required String name,
  required String unit,
  required String price,
}) async {
  await tap(tester, find.byTooltip('More'));
  await tap(tester, find.text('Products'));
  await tap(tester, find.byTooltip('Add product'));
  await type(tester, find.widgetWithText(TextFormField, 'Name'), name);
  await type(tester, find.widgetWithText(TextFormField, 'Unit label'), unit);
  await type(
    tester,
    find.widgetWithText(TextFormField, 'Current price'),
    price,
  );
  await tap(tester, find.text('Save product'));
  await tester.pageBack();
  await tester.pumpAndSettle();
}

/// Records a handover from the FAB, one card per line.
Future<void> deliver(
  WidgetTester tester, {
  required List<DeliveryLine> lines,
}) async {
  await tap(tester, find.widgetWithText(FloatingActionButton, 'Deliver'));
  for (int index = 0; index < lines.length; index++) {
    final DeliveryLine line = lines[index];
    if (index > 0) await tap(tester, find.text('Add line'));
    final String? product = line.product;
    if (product != null) {
      await tap(
        tester,
        find.byKey(ValueKey<String>('delivery-line-product-$index')),
      );
      expect(
        find.text(product),
        findsWidgets,
        reason:
            'the product picker did not open. The screen reads: '
            '${onScreen()}',
      );
      await tap(tester, find.text(product).last);
      expect(
        find.widgetWithText(TextFormField, 'Qty (${line.unit})'),
        findsWidgets,
        reason:
            'picking $product left the line on another product. The '
            'screen reads: ${onScreen()}',
      );
    }
    await type(
      tester,
      find.widgetWithText(TextFormField, 'Qty (${line.unit})'),
      line.qty,
    );
  }
  await tap(tester, find.text('Save delivery'));
}

/// Opens the dues destination from the bottom bar.
Future<void> openDues(WidgetTester tester) async {
  await tap(tester, find.widgetWithText(NavigationDestination, 'Dues'));
}

/// Opens the stock destination from the bottom bar.
Future<void> openStock(WidgetTester tester) async {
  await tap(tester, find.widgetWithText(NavigationDestination, 'Stock'));
}

/// Opens one person's statement, which lives behind the people list rather
/// than behind a dues row.
Future<void> openPerson(WidgetTester tester, String name) async {
  await tap(tester, find.byTooltip('People'));
  await tap(tester, find.widgetWithText(ListTile, name));
}

// ---------------------------------------------------------------------- pdf

/// Every word an uncompressed document actually painted.
///
/// A statement is drawn with an embedded TrueType face, so the page carries
/// glyph ids rather than characters, and the layout paints one run per word
/// rather than one per line. Each font in the file ships its own `ToUnicode`
/// map, so every run is decoded through every map and all the readings are
/// kept. A run decoded through the wrong map is nonsense and matches nothing,
/// which is why keeping them all is safe: a figure found in here was painted,
/// not merely handed to the painter.
Set<String> _paintedWords(String raw) {
  final List<Map<int, int>> maps = <Map<int, int>>[];
  for (final RegExpMatch block in RegExp(
    r'beginbfchar(.*?)endbfchar',
    dotAll: true,
  ).allMatches(raw)) {
    final Map<int, int> characters = <int, int>{};
    for (final RegExpMatch pair in RegExp(
      r'<([0-9A-Fa-f]{4})>\s*<([0-9A-Fa-f]{4})>',
    ).allMatches(block.group(1)!)) {
      characters[int.parse(pair.group(1)!, radix: 16)] = int.parse(
        pair.group(2)!,
        radix: 16,
      );
    }
    maps.add(characters);
  }
  if (maps.isEmpty) throw StateError('the document embedded no font');

  final Set<String> words = <String>{};
  int at = 0;
  while (true) {
    final int start = raw.indexOf('stream', at);
    if (start < 0) break;
    final int end = raw.indexOf('endstream', start);
    if (end < 0) break;
    final String body = raw.substring(start + 'stream'.length, end);
    if (body.contains('BT')) {
      for (final RegExpMatch run in RegExp(
        r'<([0-9A-Fa-f]+)>',
      ).allMatches(body)) {
        final String hex = run.group(1)!;
        for (final Map<int, int> characters in maps) {
          final StringBuffer word = StringBuffer();
          for (int i = 0; i + 4 <= hex.length; i += 4) {
            word.writeCharCode(
              characters[int.parse(hex.substring(i, i + 4), radix: 16)] ??
                  0xfffd,
            );
          }
          words.add(word.toString());
        }
      }
    }
    at = end + 'endstream'.length;
  }
  if (words.isEmpty) throw StateError('the document painted no text');
  return words;
}
