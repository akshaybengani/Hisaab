import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/components/deliver_form.dart';
import 'package:hisaab/components/dues_view.dart';
import 'package:hisaab/components/person_detail_view.dart';
import 'package:hisaab/components/purchase_form.dart';
import 'package:hisaab/components/requests_view.dart';
import 'package:hisaab/components/settings_view.dart';
import 'package:hisaab/components/stock_view.dart';
import 'package:hisaab/models/models.dart';

import 'support/harness.dart';
import 'support/memex_ac.dart';

void _nothing() {}

/// The behaviour the brief is specific about, rather than the layout.
void main() {
  useAcEmission('test/behaviour_test.dart');

  group('dues', () {
    testWidgets('leads with one figure for everything that is out', (
      WidgetTester tester,
    ) async {
      PersonBalance? tapped;
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: DuesView(
            balances: sampleBalances(),
            onTapPerson: (PersonBalance balance) => tapped = balance,
            onAddPerson: _nothing,
          ),
        ),
        brightness: Brightness.light,
      );

      expect(find.text('Cash out'), findsOneWidget);
      expect(
        find.text('₹5,600'),
        findsWidgets,
        reason: 'Meera owes 4,100 on products and 1,500 in cash',
      );
      expect(find.text('To collect'), findsOneWidget);
      expect(find.text('To pay'), findsOneWidget);
      expect(find.text('₹750.50'), findsWidgets, reason: 'Sunita is in credit');

      await tester.tap(find.text('Meera Joshi'));
      await tester.pump();
      expect(
        tapped?.person.name,
        'Meera Joshi',
        reason: 'a row goes straight to collect',
      );
    });
  });

  group('deliver', () {
    testWidgets('prefills the price from the product and keeps it editable', (
      WidgetTester tester,
    ) async {
      Delivery? saved;
      List<DeliveryItem>? savedItems;
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: DeliverForm(
            people: const <Person>[kMeera],
            products: const <Product>[kShake, kTea],
            onAddPerson: _nothing,
            onAddProduct: _nothing,
            onSave: (Delivery delivery, List<DeliveryItem> items) {
              saved = delivery;
              savedItems = items;
            },
          ),
        ),
        brightness: Brightness.light,
      );

      expect(
        find.text('2,050'),
        findsOneWidget,
        reason: "the shake's current price prefills the line",
      );
      expect(find.text('Line total ₹2,050'), findsOneWidget);

      // The price is a field, not a label.
      final Finder priceField = find.widgetWithText(TextFormField, '2,050');
      await tester.enterText(priceField, '1900');
      await tester.pump();
      expect(find.text('Line total ₹1,900'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'For member (optional)'),
        'Ananya',
      );
      await tester.pump();

      await tapAfterScroll(tester, find.text('Save delivery'));

      expect(saved?.forMember, 'Ananya');
      expect(savedItems?.single.unitPricePaise, 190000);
      expect(savedItems?.single.qty, 1);
    });
  });

  group('requests', () {
    testWidgets('shows an age on each row and matches the noun to it', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: RequestsView(
            pending: samplePendingRequests(),
            ordered: const <ProductRequest>[],
            productsById: kProductsById,
            peopleById: kPeopleById,
            buildShoppingList: (_) => sampleShoppingList(),
            onMarkOrdered: (_) {},
            onConvert: (_) {},
            onCancel: (_) {},
            onAddRequest: _nothing,
            now: DateTime(2026, 9, 9),
          ),
        ),
        brightness: Brightness.light,
      );

      expect(find.textContaining('asked 12 days ago'), findsOneWidget);
      expect(
        find.textContaining('asked 1 day ago'),
        findsOneWidget,
        reason: 'one day, not one days',
      );
      expect(find.text('Afresh tea, 3 jars'), findsOneWidget);
      expect(find.text('Formula 1 shake, 1 tub'), findsOneWidget);
    });

    testWidgets('puts the oldest request first whatever order it is given', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: RequestsView(
            pending: samplePendingRequests().reversed.toList(),
            ordered: const <ProductRequest>[],
            productsById: kProductsById,
            peopleById: kPeopleById,
            buildShoppingList: (_) => sampleShoppingList(),
            onMarkOrdered: (_) {},
            onConvert: (_) {},
            onCancel: (_) {},
            onAddRequest: _nothing,
            now: DateTime(2026, 9, 9),
          ),
        ),
        brightness: Brightness.light,
      );

      final CheckboxListTile first = tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .first;
      expect(
        (first.title! as Text).data,
        'Afresh tea, 3 jars',
        reason: 'the 28 Aug request is older than the 8 Sep one',
      );
    });

    testWidgets('ticking rows offers the consolidated shopping list', (
      WidgetTester tester,
    ) async {
      List<ProductRequest>? ordered;
      List<ProductRequest>? askedFor;
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: RequestsView(
            pending: samplePendingRequests(),
            ordered: const <ProductRequest>[],
            productsById: kProductsById,
            peopleById: kPeopleById,
            buildShoppingList: (List<ProductRequest> selected) {
              askedFor = selected;
              return sampleShoppingList();
            },
            onMarkOrdered: (List<ProductRequest> selected) =>
                ordered = selected,
            onConvert: (_) {},
            onCancel: (_) {},
            onAddRequest: _nothing,
            now: DateTime(2026, 9, 9),
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(
        find.text('1 request ticked'),
        findsOneWidget,
        reason: 'one request, not one requests',
      );

      await tester.tap(find.text('Shopping list'));
      await tester.pumpAndSettle();
      expect(askedFor?.length, 1);
      expect(find.text('Afresh tea'), findsWidgets);
      expect(find.text('4 jars'), findsOneWidget);
      expect(find.text('2 people asked'), findsOneWidget);

      Navigator.of(tester.element(find.text('4 jars'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mark ordered'));
      await tester.pump();
      expect(ordered?.length, 1);
    });
  });

  group('stock', () {
    testWidgets('shows the derived figure and steps by one', (
      WidgetTester tester,
    ) async {
      final List<int> steps = <int>[];
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: StockView(
            levels: sampleStockLevels(),
            onStep: (StockLevel level, int delta) => steps.add(delta),
            onOpenHistory: (_) {},
            onPersonalUse: (_) {},
            onRecount: (_) {},
            onAddProduct: _nothing,
          ),
        ),
        brightness: Brightness.light,
      );

      expect(find.textContaining('1 tub on hand'), findsOneWidget);
      expect(
        find.textContaining('0 jars on hand'),
        findsOneWidget,
        reason: 'zero takes the plural',
      );

      await tester.tap(find.byTooltip('One more').first);
      await tester.pump();
      await tester.tap(find.byTooltip('One less').first);
      await tester.pump();
      expect(steps, <int>[1, -1]);
    });

    testWidgets('offers used it myself and recount', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: StockView(
            levels: sampleStockLevels(),
            onStep: (StockLevel level, int delta) {},
            onOpenHistory: (_) {},
            onPersonalUse: (_) {},
            onRecount: (_) {},
            onAddProduct: _nothing,
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.tap(find.byTooltip('Stock actions').first);
      await tester.pumpAndSettle();
      expect(find.text('Used it myself'), findsOneWidget);
      expect(find.text('Recount'), findsOneWidget);
      expect(find.text('Movement history'), findsOneWidget);
    });
  });

  group('purchases', () {
    testWidgets('names the absorbed gap and never writes it on its own', (
      WidgetTester tester,
    ) async {
      Expense? absorbed;
      bool saved = false;
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: PurchaseForm(
            products: const <Product>[kShake],
            categories: kCategories,
            onAddProduct: _nothing,
            onSave:
                (
                  Purchase purchase,
                  List<PurchaseItem> items, {
                  Expense? absorbedExpense,
                }) {
                  saved = true;
                  absorbed = absorbedExpense;
                },
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '3');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Unit cost'),
        '2000',
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Total paid'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Total paid'),
        '6200',
      );
      await tester.pump();

      expect(find.text('₹6,000'), findsOneWidget, reason: 'the line total');
      expect(
        find.textContaining('You absorbed ₹200'),
        findsOneWidget,
        reason: 'the gap is shown rather than spread across units',
      );
      expect(
        find.textContaining('Also record ₹200 as an expense'),
        findsOneWidget,
      );
      expect(
        tester.widget<Checkbox>(find.byType(Checkbox)).value,
        isFalse,
        reason: 'writing the gap to expenses is offered, never silent',
      );

      await tapAfterScroll(tester, find.text('Save purchase'));

      expect(saved, isTrue);
      expect(absorbed, isNull);
    });

    testWidgets('a discount received is named and never offered to expenses', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: PurchaseForm(
            products: const <Product>[kShake],
            categories: kCategories,
            onAddProduct: _nothing,
            onSave:
                (
                  Purchase purchase,
                  List<PurchaseItem> items, {
                  Expense? absorbedExpense,
                }) {},
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.enterText(find.widgetWithText(TextFormField, 'Qty'), '3');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Unit cost'),
        '2000',
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.widgetWithText(TextFormField, 'Total paid'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Total paid'),
        '5950',
      );
      await tester.pump();

      expect(
        find.textContaining('Discount received ₹50'),
        findsOneWidget,
        reason: 'paying under the lines is a saving, not something absorbed',
      );
      expect(
        find.byType(Checkbox),
        findsNothing,
        reason: 'a discount she received is not an expense she paid',
      );
    });
  });

  group('the statement', () {
    /// Verifies ac-43.
    acTestWidgets(
      'a settled delivery names what was conceded',
      <String>['ac-43'],
      (WidgetTester tester) async {
        await pumpOnSmallPhone(
          tester,
          Scaffold(
            body: PersonDetailView(
              statement: settledStatement(),
              onCollect: _nothing,
              onLendCash: _nothing,
              onShareText: _nothing,
              onSharePdf: _nothing,
            ),
          ),
          brightness: Brightness.light,
        );

        expect(
          find.text('Settled, ₹50 discount'),
          findsOneWidget,
          reason: 'the concession stays visible at the point of settlement',
        );
        expect(
          find.text('Paid'),
          findsNothing,
          reason: 'part of it was conceded, so nothing may claim it was paid',
        );
      },
    );
  });

  group('settings', () {
    testWidgets('the restore confirmation names what will be lost', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => confirmRestore(
                context,
                people: 2,
                deliveries: 1,
                expenses: 3,
              ),
              child: const Text('Restore'),
            ),
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      expect(find.text('Restore from a file'), findsOneWidget);
      expect(find.textContaining('2 people'), findsOneWidget);
      expect(find.textContaining('1 delivery and'), findsOneWidget);
      expect(find.textContaining('3 expenses'), findsOneWidget);
      expect(find.textContaining('cannot be brought back'), findsOneWidget);
      expect(find.text('Replace everything'), findsOneWidget);
      expect(find.text('Keep it'), findsOneWidget);
      expect(find.text('Yes'), findsNothing);
      expect(find.text('No'), findsNothing);
    });

    testWidgets('theme offers match device, light and dark', (
      WidgetTester tester,
    ) async {
      ThemeMode? picked;
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: SettingsView(
            values: sampleSettings(),
            themeMode: ThemeMode.system,
            onWrite: (String key, String value) async {},
            onThemeModeChanged: (ThemeMode mode) async => picked = mode,
            onBackup: null,
            onRestore: null,
          ),
        ),
        brightness: Brightness.light,
      );

      await tapAfterScroll(tester, find.text('Dark'));
      expect(find.text('Match device'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(picked, ThemeMode.dark);
    });

    testWidgets('the build number is on screen', (WidgetTester tester) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: SettingsView(
            values: sampleSettings(),
            themeMode: ThemeMode.system,
            onWrite: (String key, String value) async {},
            onThemeModeChanged: (ThemeMode mode) async {},
            onBackup: null,
            onRestore: null,
          ),
        ),
        brightness: Brightness.light,
      );
      await tester.scrollUntilVisible(
        find.text('Build'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('1.0.0 (1)'), findsOneWidget);
    });
  });
}
