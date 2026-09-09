import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/components/categories_view.dart';
import 'package:hisaab/components/dues_view.dart';
import 'package:hisaab/components/empty_state.dart';
import 'package:hisaab/components/expenses_view.dart';
import 'package:hisaab/components/people_view.dart';
import 'package:hisaab/components/products_view.dart';
import 'package:hisaab/components/purchases_view.dart';
import 'package:hisaab/components/requests_view.dart';
import 'package:hisaab/components/stock_view.dart';
import 'package:hisaab/models/models.dart';

import 'support/harness.dart';

void _nothing() {}

/// Nothing is seeded, so every list surface opens empty on the first run.
/// That is the moment the app gets abandoned, which is why each one has to
/// name what it is for and offer the next action inline.
void main() {
  final Map<String, Widget> emptySurfaces = <String, Widget>{
    'dues': DuesView(
      balances: const <PersonBalance>[],
      onTapPerson: (_) {},
      onAddPerson: _nothing,
    ),
    'people': PeopleView(
      people: const <Person>[],
      onTapPerson: (_) {},
      onAddPerson: _nothing,
    ),
    'products': ProductsView(
      products: const <Product>[],
      onAddProduct: _nothing,
      onTapProduct: (_) {},
    ),
    'requests': RequestsView(
      pending: const <ProductRequest>[],
      ordered: const <ProductRequest>[],
      productsById: kProductsById,
      peopleById: kPeopleById,
      buildShoppingList: (_) => const <ShoppingListLine>[],
      onMarkOrdered: (_) {},
      onConvert: (_) {},
      onCancel: (_) {},
      onAddRequest: _nothing,
    ),
    'expenses': ExpensesView(
      expenses: const <Expense>[],
      categoriesById: kCategoriesById,
      onAddExpense: _nothing,
      onTapExpense: (_) {},
      onManageCategories: _nothing,
    ),
    'categories': CategoriesView(
      categories: const <ExpenseCategory>[],
      onAddCategory: _nothing,
      onSetArchived: (ExpenseCategory c, {required bool archived}) {},
    ),
    'purchases': PurchasesView(
      purchases: const <PurchaseWithItems>[],
      productsById: kProductsById,
      onAddPurchase: _nothing,
      onTapPurchase: (_) {},
    ),
    'stock': StockView(
      levels: const <StockLevel>[],
      onStep: (StockLevel level, int delta) {},
      onOpenHistory: (_) {},
      onPersonalUse: (_) {},
      onRecount: (_) {},
      onAddProduct: _nothing,
    ),
  };

  for (final MapEntry<String, Widget> surface in emptySurfaces.entries) {
    testWidgets('${surface.key} has a real empty state', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(body: surface.value),
        brightness: Brightness.light,
      );

      final EmptyState empty = tester.widget<EmptyState>(
        find.byType(EmptyState),
      );

      expect(
        empty.message.length,
        greaterThan(40),
        reason: 'the message has to say what the surface is for',
      );
      expect(
        empty.message.trim(),
        endsWith('.'),
        reason: 'a full sentence takes a full stop [per std-24]',
      );
      for (final String slop in <String>[
        'no items',
        'nothing here',
        'empty',
        'not found',
      ]) {
        expect(
          empty.message.toLowerCase(),
          isNot(contains(slop)),
          reason: '"$slop" tells the owner nothing',
        );
      }

      expect(empty.actionLabel, isNotEmpty);
      expect(
        empty.actionLabel,
        isNot(endsWith('.')),
        reason: 'a short label takes no full stop [per std-24]',
      );
      expect(
        empty.actionLabel[0],
        equals(empty.actionLabel[0].toUpperCase()),
        reason: 'sentence case starts with a capital',
      );
      expect(
        find.widgetWithText(FilledButton, empty.actionLabel),
        findsOneWidget,
        reason: 'the next action has to be reachable from here',
      );
    });
  }

  testWidgets('the empty state action fires', (WidgetTester tester) async {
    int taps = 0;
    await pumpOnSmallPhone(
      tester,
      Scaffold(
        body: EmptyState(
          icon: Icons.group_outlined,
          message: 'People holds everyone you hand products to.',
          actionLabel: 'Add person',
          onAction: () => taps++,
        ),
      ),
      brightness: Brightness.light,
    );
    await tester.tap(find.text('Add person'));
    await tester.pump();
    expect(taps, 1);
  });
}
