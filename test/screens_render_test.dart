import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/app_shell.dart';
import 'package:hisaab/components/categories_view.dart';
import 'package:hisaab/components/collect_view.dart';
import 'package:hisaab/components/deliver_form.dart';
import 'package:hisaab/components/dues_view.dart';
import 'package:hisaab/components/expenses_view.dart';
import 'package:hisaab/components/people_view.dart';
import 'package:hisaab/components/person_detail_view.dart';
import 'package:hisaab/components/person_edit_form.dart';
import 'package:hisaab/components/products_view.dart';
import 'package:hisaab/components/purchase_form.dart';
import 'package:hisaab/components/purchases_view.dart';
import 'package:hisaab/components/request_form.dart';
import 'package:hisaab/components/requests_view.dart';
import 'package:hisaab/components/settings_view.dart';
import 'package:hisaab/components/stock_view.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/providers/app_state.dart';
import 'package:hisaab/providers/view_models.dart';
import 'package:hisaab/screens/categories_screen.dart';
import 'package:hisaab/screens/collect_screen.dart';
import 'package:hisaab/screens/deliver_screen.dart';
import 'package:hisaab/screens/dues_screen.dart';
import 'package:hisaab/screens/expense_edit_screen.dart';
import 'package:hisaab/screens/expenses_screen.dart';
import 'package:hisaab/screens/people_screen.dart';
import 'package:hisaab/screens/person_detail_screen.dart';
import 'package:hisaab/screens/person_edit_screen.dart';
import 'package:hisaab/screens/product_edit_screen.dart';
import 'package:hisaab/screens/products_screen.dart';
import 'package:hisaab/screens/purchase_edit_screen.dart';
import 'package:hisaab/screens/purchases_screen.dart';
import 'package:hisaab/screens/request_edit_screen.dart';
import 'package:hisaab/screens/requests_screen.dart';
import 'package:hisaab/screens/settings_screen.dart';
import 'package:hisaab/screens/stock_history_screen.dart';
import 'package:hisaab/screens/stock_screen.dart';

import 'support/harness.dart';

void _nothing() {}

/// Every screen, rendered on a 360 by 560 phone in both brightnesses.
///
/// The sizes are the point: this is the smallest surface the app has to hold,
/// and an overflow there is a real bug rather than a styling opinion. The
/// presentational widgets are driven with hand built models, so none of this
/// waits on the ledger or stock arithmetic.
void main() {
  final Map<String, Widget Function()> surfaces = <String, Widget Function()>{
    'dues, populated': () => DuesView(
      balances: sampleBalances(),
      onTapPerson: (_) {},
      onAddPerson: _nothing,
      onSeePeople: _nothing,
    ),
    'dues, empty': () => DuesView(
      balances: const <PersonBalance>[],
      onTapPerson: (_) {},
      onAddPerson: _nothing,
    ),
    'people, populated': () => PeopleView(
      people: const <Person>[kMeera, kSunita],
      onTapPerson: (_) {},
      onAddPerson: _nothing,
    ),
    'people, empty': () => PeopleView(
      people: const <Person>[],
      onTapPerson: (_) {},
      onAddPerson: _nothing,
    ),
    'person detail, both pools': () => PersonDetailView(
      statement: sampleStatement(),
      onCollect: _nothing,
      onLendCash: _nothing,
      onShareText: _nothing,
      onSharePdf: _nothing,
    ),
    'person detail, products only': () => PersonDetailView(
      statement: sampleStatement(bothPools: false),
      onCollect: _nothing,
      onLendCash: _nothing,
      onShareText: _nothing,
      onSharePdf: _nothing,
    ),
    'person edit': () => PersonEditForm(
      initial: kMeera,
      onSave: (_) {},
      onSetArchived: ({required bool archived}) {},
    ),
    'deliver': () => DeliverForm(
      people: const <Person>[kMeera, kSunita],
      products: const <Product>[kShake, kTea],
      onSave: (Delivery delivery, List<DeliveryItem> items) {},
      onAddPerson: _nothing,
      onAddProduct: _nothing,
    ),
    'deliver, no products': () => DeliverForm(
      people: const <Person>[kMeera],
      products: const <Product>[],
      onSave: (Delivery delivery, List<DeliveryItem> items) {},
      onAddPerson: _nothing,
      onAddProduct: _nothing,
    ),
    'collect, both pools': () => CollectView(
      person: kMeera,
      productDuePaise: 210000,
      cashDuePaise: 150000,
      onRecord: (CollectPlan plan, {required bool clearRemainder}) {},
    ),
    'collect, one pool': () => CollectView(
      person: kMeera,
      productDuePaise: 210000,
      cashDuePaise: 0,
      onRecord: (CollectPlan plan, {required bool clearRemainder}) {},
    ),
    'requests, populated': () => RequestsView(
      pending: samplePendingRequests(),
      ordered: sampleOrderedRequests(),
      productsById: kProductsById,
      peopleById: kPeopleById,
      buildShoppingList: (_) => sampleShoppingList(),
      onMarkOrdered: (_) {},
      onConvert: (_) {},
      onCancel: (_) {},
      onAddRequest: _nothing,
      now: DateTime(2026, 9, 9),
    ),
    'requests, empty': () => RequestsView(
      pending: const <ProductRequest>[],
      ordered: const <ProductRequest>[],
      productsById: kProductsById,
      peopleById: kPeopleById,
      buildShoppingList: (_) => sampleShoppingList(),
      onMarkOrdered: (_) {},
      onConvert: (_) {},
      onCancel: (_) {},
      onAddRequest: _nothing,
    ),
    'request form': () => RequestForm(
      people: const <Person>[kMeera, kSunita],
      products: const <Product>[kShake, kTea],
      onSave: (_) {},
      onAddPerson: _nothing,
      onAddProduct: _nothing,
    ),
    'stock, populated': () => StockView(
      levels: sampleStockLevels(),
      onStep: (StockLevel level, int delta) {},
      onOpenHistory: (_) {},
      onPersonalUse: (_) {},
      onRecount: (_) {},
      onAddProduct: _nothing,
    ),
    'stock, empty': () => StockView(
      levels: const <StockLevel>[],
      onStep: (StockLevel level, int delta) {},
      onOpenHistory: (_) {},
      onPersonalUse: (_) {},
      onRecount: (_) {},
      onAddProduct: _nothing,
    ),
    'stock history, populated': () =>
        StockHistoryView(product: kShake, movements: sampleMovements()),
    'stock history, empty': () => const StockHistoryView(
      product: kShake,
      movements: <StockMovement>[],
    ),
    'purchases, populated': () => PurchasesView(
      purchases: samplePurchases(),
      productsById: kProductsById,
      onAddPurchase: _nothing,
      onTapPurchase: (_) {},
    ),
    'purchases, empty': () => PurchasesView(
      purchases: const <PurchaseWithItems>[],
      productsById: kProductsById,
      onAddPurchase: _nothing,
      onTapPurchase: (_) {},
    ),
    'purchase form': () => PurchaseForm(
      products: const <Product>[kShake, kTea],
      categories: kCategories,
      onSave:
          (
            Purchase purchase,
            List<PurchaseItem> items, {
            Expense? absorbedExpense,
          }) {},
      onAddProduct: _nothing,
    ),
    'expenses, populated': () => ExpensesView(
      expenses: sampleExpenses(),
      categoriesById: kCategoriesById,
      onAddExpense: _nothing,
      onTapExpense: (_) {},
      onManageCategories: _nothing,
      month: DateTime(2026, 9, 9),
    ),
    'expenses, empty': () => ExpensesView(
      expenses: const <Expense>[],
      categoriesById: kCategoriesById,
      onAddExpense: _nothing,
      onTapExpense: (_) {},
      onManageCategories: _nothing,
    ),
    'expense form': () => ExpenseForm(
      categories: kCategories,
      onSave: (_) {},
      onCreateCategory: (String name) async => 1,
    ),
    'categories, populated': () => CategoriesView(
      categories: kCategories,
      onAddCategory: _nothing,
      onSetArchived: (ExpenseCategory c, {required bool archived}) {},
    ),
    'categories, empty': () => CategoriesView(
      categories: const <ExpenseCategory>[],
      onAddCategory: _nothing,
      onSetArchived: (ExpenseCategory c, {required bool archived}) {},
    ),
    'products, populated': () => ProductsView(
      products: const <Product>[kShake, kTea],
      onAddProduct: _nothing,
      onTapProduct: (_) {},
    ),
    'products, empty': () => ProductsView(
      products: const <Product>[],
      onAddProduct: _nothing,
      onTapProduct: (_) {},
    ),
    'product edit': () => ProductEditForm(
      initial: kShake,
      knownCategories: const <String>['Nutrition', 'Skin'],
      onSave: (_) {},
      onSetArchived: ({required bool archived}) {},
    ),
    'settings': () => SettingsView(
      values: sampleSettings(),
      themeMode: ThemeMode.system,
      onWrite: (String key, String value) async {},
      onThemeModeChanged: (ThemeMode mode) async {},
      onBackup: null,
      onRestore: null,
    ),
  };

  group('every screen renders on a small phone', () {
    for (final Brightness brightness in Brightness.values) {
      for (final MapEntry<String, Widget Function()> surface
          in surfaces.entries) {
        testWidgets('${surface.key}, ${brightness.name}', (
          WidgetTester tester,
        ) async {
          await pumpOnSmallPhone(
            tester,
            Scaffold(body: surface.value()),
            brightness: brightness,
          );
        });
      }
    }
  });

  group('surfaces that only appear after a tap', () {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('requests selection bar, ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await pumpOnSmallPhone(
          tester,
          Scaffold(
            body: RequestsView(
              pending: samplePendingRequests(),
              ordered: sampleOrderedRequests(),
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
          brightness: brightness,
        );

        // The bar carries two buttons and a count, which is what overflowed
        // on a 360 wide phone before it was laid out as a column.
        await tester.tap(find.byType(Checkbox).first);
        await tester.pump();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Shopping list'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('stock actions menu, ${brightness.name}', (
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
          brightness: brightness,
        );
        await tester.tap(find.byTooltip('Stock actions').first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('every connected screen renders against the fake', () {
    final Map<String, Widget> connected = <String, Widget>{
      'app shell': const AppShell(),
      'dues': const Scaffold(body: DuesScreen()),
      'requests': const Scaffold(body: RequestsScreen()),
      'stock': const Scaffold(body: StockScreen()),
      'expenses': const Scaffold(body: ExpensesScreen()),
      'people': const PeopleScreen(),
      'person detail': const PersonDetailScreen(person: kMeera),
      'person edit': const PersonEditScreen(person: kMeera),
      'collect': const CollectScreen(person: kMeera),
      'deliver': const DeliverScreen(),
      'request edit': const RequestEditScreen(),
      'stock history': const StockHistoryScreen(product: kShake),
      'purchases': const PurchasesScreen(),
      'purchase edit': const PurchaseEditScreen(),
      'expense edit': const ExpenseEditScreen(),
      'categories': const CategoriesScreen(),
      'products': const ProductsScreen(),
      'product edit': const ProductEditScreen(product: kShake),
      'settings': const SettingsScreen(),
    };

    for (final Brightness brightness in Brightness.values) {
      for (final MapEntry<String, Widget> entry in connected.entries) {
        testWidgets('${entry.key}, ${brightness.name}', (
          WidgetTester tester,
        ) async {
          await withQuietLogs(() async {
            final AppState state = await loadedState();
            await pumpOnSmallPhone(
              tester,
              entry.value,
              brightness: brightness,
              state: state,
            );
          });
        });
      }
    }
  });
}
