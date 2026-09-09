import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/components/dues_view.dart';
import 'package:hisaab/components/empty_state.dart';
import 'package:hisaab/components/expenses_view.dart';
import 'package:hisaab/components/people_view.dart';
import 'package:hisaab/components/products_view.dart';
import 'package:hisaab/components/purchases_view.dart';
import 'package:hisaab/components/requests_view.dart';
import 'package:hisaab/components/search_field.dart';
import 'package:hisaab/components/stock_view.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/models/models.dart';

import 'support/harness.dart';
import 'support/memex_ac.dart';

void _nothing() {}

// ------------------------------------------------------------- the fixtures
//
// Hand built here rather than taken from the harness, because these rows exist
// to be searched: two people share a first name, two share a surname, and
// every field a surface claims to match carries something distinctive.

const Person kJoshi = Person(
  id: 1,
  name: 'Meera Joshi',
  phone: '98765 00001',
  note: 'Society block A',
);
const Person kRao = Person(id: 2, name: 'Meera Rao');
const Person kOther = Person(id: 3, name: 'Sunita Joshi', isHousehold: true);

const List<Person> kSearchPeople = <Person>[kJoshi, kRao, kOther];

const Product kShakeProduct = Product(
  id: 1,
  name: 'Formula 1 shake',
  unitLabel: 'tub',
  currentPricePaise: 205000,
  category: 'Nutrition',
);
const Product kTeaProduct = Product(
  id: 2,
  name: 'Afresh tea',
  unitLabel: 'jar',
  currentPricePaise: 122500,
  category: 'Wellness',
);

const List<Product> kSearchProducts = <Product>[kShakeProduct, kTeaProduct];

const Map<int, Product> kSearchProductsById = <int, Product>{
  1: kShakeProduct,
  2: kTeaProduct,
};

const Map<int, Person> kSearchPeopleById = <int, Person>{
  1: kJoshi,
  2: kRao,
  3: kOther,
};

const Map<int, ExpenseCategory> kSearchCategories = <int, ExpenseCategory>{
  1: ExpenseCategory(id: 1, name: 'Travel'),
  2: ExpenseCategory(id: 2, name: 'Packaging'),
};

List<Expense> searchExpenses() => <Expense>[
  Expense(
    id: 1,
    date: DateTime(2026, 9, 4),
    amountPaise: 45000,
    categoryId: 1,
    note: 'Auto to the distributor',
  ),
  Expense(
    id: 2,
    date: DateTime(2026, 9, 3),
    amountPaise: 12000,
    categoryId: 2,
    note: 'Packing tape',
  ),
];

List<PurchaseWithItems> searchPurchases() => <PurchaseWithItems>[
  PurchaseWithItems(
    purchase: Purchase(
      id: 1,
      date: DateTime(2026, 8, 20),
      totalPaidPaise: 620000,
      vendor: 'Distributor',
      note: 'Diwali order',
    ),
    items: const <PurchaseItem>[
      PurchaseItem(
        id: 1,
        purchaseId: 1,
        productId: 1,
        qty: 3,
        unitCostPaise: 200000,
      ),
    ],
  ),
  PurchaseWithItems(
    purchase: Purchase(
      id: 2,
      date: DateTime(2026, 8, 24),
      totalPaidPaise: 122500,
      vendor: 'Corner shop',
    ),
    items: const <PurchaseItem>[
      PurchaseItem(
        id: 2,
        purchaseId: 2,
        productId: 2,
        qty: 1,
        unitCostPaise: 122500,
      ),
    ],
  ),
];

List<ProductRequest> searchRequests() => <ProductRequest>[
  ProductRequest(
    id: 1,
    personId: 3,
    productId: 2,
    qty: 3,
    status: RequestStatus.pending,
    createdAt: DateTime(2026, 8, 28),
    forMember: 'Kabir',
  ),
  ProductRequest(
    id: 2,
    personId: 1,
    productId: 1,
    qty: 1,
    status: RequestStatus.pending,
    createdAt: DateTime(2026, 9, 8),
    note: 'Wants it before Sunday',
  ),
];

List<StockLevel> searchLevels() => const <StockLevel>[
  StockLevel(
    product: kShakeProduct,
    onHand: 1,
    purchased: 3,
    delivered: 2,
    adjusted: 0,
  ),
  StockLevel(
    product: kTeaProduct,
    onHand: 0,
    purchased: 2,
    delivered: 1,
    adjusted: -1,
  ),
];

List<PersonBalance> searchBalances() => <PersonBalance>[
  PersonBalance(
    person: kJoshi,
    productDuePaise: 410000,
    cashDuePaise: 0,
    lastActivity: DateTime(2026, 9, 5),
  ),
  PersonBalance(
    person: kOther,
    productDuePaise: -75050,
    cashDuePaise: 0,
    lastActivity: DateTime(2026, 8, 30),
  ),
];

// ------------------------------------------------------------- the surfaces

Widget peopleSurface({List<Person> people = kSearchPeople}) =>
    PeopleView(people: people, onTapPerson: (_) {}, onAddPerson: _nothing);

Widget productsSurface({List<Product> products = kSearchProducts}) =>
    ProductsView(
      products: products,
      onAddProduct: _nothing,
      onTapProduct: (_) {},
    );

Widget expensesSurface({List<Expense>? expenses}) => ExpensesView(
  expenses: expenses ?? searchExpenses(),
  categoriesById: kSearchCategories,
  onAddExpense: _nothing,
  onTapExpense: (_) {},
  onManageCategories: _nothing,
  month: DateTime(2026, 9, 9),
);

Widget purchasesSurface({List<PurchaseWithItems>? purchases}) => PurchasesView(
  purchases: purchases ?? searchPurchases(),
  productsById: kSearchProductsById,
  onAddPurchase: _nothing,
  onTapPurchase: (_) {},
);

Widget requestsSurface({List<ProductRequest>? pending}) => RequestsView(
  pending: pending ?? searchRequests(),
  ordered: const <ProductRequest>[],
  productsById: kSearchProductsById,
  peopleById: kSearchPeopleById,
  buildShoppingList: (_) => sampleShoppingList(),
  onMarkOrdered: (_) {},
  onConvert: (_) {},
  onCancel: (_) {},
  onAddRequest: _nothing,
  now: DateTime(2026, 9, 9),
);

Widget stockSurface({List<StockLevel>? levels}) => StockView(
  levels: levels ?? searchLevels(),
  onStep: (StockLevel level, int delta) {},
  onOpenHistory: (_) {},
  onPersonalUse: (_) {},
  onRecount: (_) {},
  onAddProduct: _nothing,
);

Widget duesSurface({List<PersonBalance>? balances}) => DuesView(
  balances: balances ?? searchBalances(),
  onTapPerson: (_) {},
  onAddPerson: _nothing,
);

/// Every list surface, populated, and the same one with nothing in it.
final Map<String, Widget Function()> kPopulated = <String, Widget Function()>{
  'people': peopleSurface,
  'products': productsSurface,
  'expenses': expensesSurface,
  'purchases': purchasesSurface,
  'requests': requestsSurface,
  'stock': stockSurface,
  'dues': duesSurface,
};

final Map<String, Widget Function()> kEmpty = <String, Widget Function()>{
  'people': () => peopleSurface(people: const <Person>[]),
  'products': () => productsSurface(products: const <Product>[]),
  'expenses': () => expensesSurface(expenses: const <Expense>[]),
  'purchases': () => purchasesSurface(purchases: const <PurchaseWithItems>[]),
  'requests': () => requestsSurface(pending: const <ProductRequest>[]),
  'stock': () => stockSurface(levels: const <StockLevel>[]),
  'dues': () => duesSurface(balances: const <PersonBalance>[]),
};

// --------------------------------------------------------------- the driving

Future<void> pumpSurface(WidgetTester tester, Widget surface) =>
    pumpOnSmallPhone(
      tester,
      Scaffold(body: surface),
      brightness: Brightness.light,
    );

Future<void> typeSearch(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(SearchField), query);
  await tester.pump();
}

/// One claim the code makes about what a surface matches.
class FieldCase {
  const FieldCase({
    required this.surface,
    required this.field,
    required this.build,
    required this.query,
    required this.kept,
    required this.dropped,
  });

  final String surface;
  final String field;
  final Widget Function() build;
  final String query;

  /// A row that has to survive the search, named by text on it.
  final String kept;

  /// A row that has to go, which is what proves the search filtered at all.
  final String dropped;
}

/// Every field every surface claims, one case each, so a field added to the
/// code without a case here shows up as an untested claim.
const List<FieldCase> kFieldCases = <FieldCase>[
  FieldCase(
    surface: 'people',
    field: 'a name',
    build: peopleSurface,
    query: 'sunita',
    kept: 'Sunita Joshi',
    dropped: 'Meera Rao',
  ),
  FieldCase(
    surface: 'people',
    field: 'a phone number typed without its spaces',
    build: peopleSurface,
    query: '9876500001',
    kept: 'Meera Joshi',
    dropped: 'Meera Rao',
  ),
  FieldCase(
    surface: 'people',
    field: 'a note',
    build: peopleSurface,
    query: 'block a',
    kept: 'Meera Joshi',
    dropped: 'Sunita Joshi',
  ),
  FieldCase(
    surface: 'products',
    field: 'a product name',
    build: productsSurface,
    query: 'afresh',
    kept: 'Afresh tea',
    dropped: 'Formula 1 shake',
  ),
  FieldCase(
    surface: 'products',
    field: 'a unit label',
    build: productsSurface,
    query: 'tub',
    kept: 'Formula 1 shake',
    dropped: 'Afresh tea',
  ),
  FieldCase(
    surface: 'products',
    field: 'a category',
    build: productsSurface,
    query: 'wellness',
    kept: 'Afresh tea',
    dropped: 'Formula 1 shake',
  ),
  FieldCase(
    surface: 'expenses',
    field: 'a note',
    build: expensesSurface,
    query: 'auto',
    kept: 'Auto to the distributor',
    dropped: 'Packing tape',
  ),
  FieldCase(
    surface: 'expenses',
    field: 'a category name',
    build: expensesSurface,
    query: 'packaging',
    kept: 'Packing tape',
    dropped: 'Auto to the distributor',
  ),
  FieldCase(
    surface: 'purchases',
    field: 'a vendor',
    build: purchasesSurface,
    query: 'corner',
    kept: 'Corner shop',
    dropped: 'Distributor',
  ),
  FieldCase(
    surface: 'purchases',
    field: 'a note',
    build: purchasesSurface,
    query: 'diwali',
    kept: 'Distributor',
    dropped: 'Corner shop',
  ),
  FieldCase(
    surface: 'purchases',
    field: 'a product on the order',
    build: purchasesSurface,
    query: 'afresh',
    kept: 'Corner shop',
    dropped: 'Distributor',
  ),
  FieldCase(
    surface: 'purchases',
    field: 'a unit label on the order',
    build: purchasesSurface,
    query: 'tub',
    kept: 'Distributor',
    dropped: 'Corner shop',
  ),
  FieldCase(
    surface: 'requests',
    field: 'the person who asked',
    build: requestsSurface,
    query: 'sunita',
    kept: 'Afresh tea, 3 jars',
    dropped: 'Formula 1 shake, 1 tub',
  ),
  FieldCase(
    surface: 'requests',
    field: 'the member it is for',
    build: requestsSurface,
    query: 'kabir',
    kept: 'Afresh tea, 3 jars',
    dropped: 'Formula 1 shake, 1 tub',
  ),
  FieldCase(
    surface: 'requests',
    field: 'a product name',
    build: requestsSurface,
    query: 'formula',
    kept: 'Formula 1 shake, 1 tub',
    dropped: 'Afresh tea, 3 jars',
  ),
  FieldCase(
    surface: 'requests',
    field: 'a unit label',
    build: requestsSurface,
    query: 'jar',
    kept: 'Afresh tea, 3 jars',
    dropped: 'Formula 1 shake, 1 tub',
  ),
  FieldCase(
    surface: 'requests',
    field: 'a note',
    build: requestsSurface,
    query: 'sunday',
    kept: 'Formula 1 shake, 1 tub',
    dropped: 'Afresh tea, 3 jars',
  ),
  FieldCase(
    surface: 'stock',
    field: 'a product name',
    build: stockSurface,
    query: 'afresh',
    kept: 'Afresh tea',
    dropped: 'Formula 1 shake',
  ),
  FieldCase(
    surface: 'stock',
    field: 'a unit label',
    build: stockSurface,
    query: 'tub',
    kept: 'Formula 1 shake',
    dropped: 'Afresh tea',
  ),
  FieldCase(
    surface: 'stock',
    field: 'a category',
    build: stockSurface,
    query: 'nutrition',
    kept: 'Formula 1 shake',
    dropped: 'Afresh tea',
  ),
  FieldCase(
    surface: 'dues',
    field: 'a name',
    build: duesSurface,
    query: 'sunita',
    kept: 'Sunita Joshi',
    dropped: 'Meera Joshi',
  ),
  FieldCase(
    surface: 'dues',
    field: 'a phone number',
    build: duesSurface,
    query: '9876500001',
    kept: 'Meera Joshi',
    dropped: 'Sunita Joshi',
  ),
  FieldCase(
    surface: 'dues',
    field: 'a note',
    build: duesSurface,
    query: 'block',
    kept: 'Meera Joshi',
    dropped: 'Sunita Joshi',
  ),
];

/// Search on every list surface.
///
/// The app ships empty and grows, so the behaviour that matters is what
/// happens at fifty people: two words have to narrow the list, and a search
/// that finds nothing has to say so rather than leaving a blank screen.
void main() {
  useAcEmission('test/search_test.dart');

  group('terms are ANDed', () {
    acTestWidgets(
      'two terms narrow the list rather than widen it',
      <String>[],
      (WidgetTester tester) async {
        await pumpSurface(tester, peopleSurface());
        expect(find.byType(ListTile), findsNWidgets(3));

        await typeSearch(tester, 'meera joshi');

        expect(
          find.text('Meera Joshi'),
          findsOneWidget,
          reason: 'the one row carrying both words',
        );
        expect(
          find.text('Meera Rao'),
          findsNothing,
          reason: 'ORing the terms would have kept this row on "meera"',
        );
        expect(
          find.text('Sunita Joshi'),
          findsNothing,
          reason: 'ORing the terms would have kept this row on "joshi"',
        );
        expect(find.byType(ListTile), findsOneWidget);
      },
    );

    acTestWidgets('a second term can land in a different field', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, requestsSurface());

      await typeSearch(tester, 'sunita jar');

      expect(
        find.text('Afresh tea, 3 jars'),
        findsOneWidget,
        reason: 'the person matched one term and the unit label the other',
      );
      expect(find.text('Formula 1 shake, 1 tub'), findsNothing);
    });

    acTestWidgets('a term nothing carries narrows to nothing', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, peopleSurface());

      await typeSearch(tester, 'meera dytor');

      expect(
        find.byType(ListTile),
        findsNothing,
        reason: 'both words have to match, and no row carries the second',
      );
    });
  });

  group('what a search ignores', () {
    acTestWidgets('case', <String>[], (WidgetTester tester) async {
      await pumpSurface(tester, peopleSurface());

      await typeSearch(tester, 'MEERA JOSHI');

      expect(find.text('Meera Joshi'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    acTestWidgets('whitespace around and between the terms', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, peopleSurface());

      await typeSearch(tester, '   meera    joshi  ');

      expect(find.text('Meera Joshi'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    acTestWidgets('whitespace on its own, which is not a search', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, peopleSurface());

      await typeSearch(tester, '   ');

      expect(
        find.byType(ListTile),
        findsNWidgets(3),
        reason: 'spaces alone leave the list as it was',
      );
    });
  });

  group('every field a surface claims', () {
    for (final FieldCase field in kFieldCases) {
      acTestWidgets(
        '${field.surface} search matches ${field.field}',
        <String>[],
        (WidgetTester tester) async {
          await pumpSurface(tester, field.build());

          await typeSearch(tester, field.query);

          expect(
            find.text(field.kept),
            findsOneWidget,
            reason: '"${field.query}" is in that row',
          );
          expect(
            find.text(field.dropped),
            findsNothing,
            reason: 'the search has to remove what does not match',
          );
        },
      );
    }
  });

  group('a search that finds nothing', () {
    acTestWidgets(
      'names what was searched and offers to clear it',
      <String>['ac-33'],
      (WidgetTester tester) async {
        await pumpSurface(tester, peopleSurface());

        await typeSearch(tester, 'dytor');

        expect(
          find.text('0 results for "dytor"'),
          findsOneWidget,
          reason: 'the panel names the search and matches the noun to zero',
        );
        expect(
          find.widgetWithText(FilledButton, 'Clear search'),
          findsOneWidget,
          reason: 'the no match state names the way out',
        );
        expect(find.byType(ListTile), findsNothing);
      },
    );

    acTestWidgets('never shows the surface empty state instead', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, peopleSurface());

      await typeSearch(tester, 'dytor');

      expect(
        find.byType(EmptyState),
        findsNothing,
        reason: '"add your first person" is wrong when a search found nothing',
      );
      expect(
        find.textContaining('Add person'),
        findsNothing,
        reason: 'the people are there, the search just missed them',
      );
    });

    acTestWidgets(
      'reports the search as typed, not as normalised',
      <String>['ac-33'],
      (WidgetTester tester) async {
        await pumpSurface(tester, productsSurface());

        await typeSearch(tester, '  Tub Wellness  ');

        expect(
          find.text('0 results for "Tub Wellness"'),
          findsOneWidget,
          reason: 'a term from each product, so neither product carries both',
        );
      },
    );
  });

  group('clearing', () {
    acTestWidgets('the panel button restores the whole list', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, peopleSurface());
      final List<String> before = rowTitles(tester);

      await typeSearch(tester, 'dytor');
      expect(find.byType(ListTile), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Clear search'));
      await tester.pump();

      expect(
        rowTitles(tester),
        before,
        reason: 'the same rows in the same order they were given in',
      );
    });

    acTestWidgets('emptying the field restores the whole list', <String>[], (
      WidgetTester tester,
    ) async {
      await pumpSurface(tester, peopleSurface());
      final List<String> before = rowTitles(tester);

      await typeSearch(tester, 'sunita');
      expect(rowTitles(tester), <String>['Sunita Joshi']);

      await typeSearch(tester, '');

      expect(rowTitles(tester), before);
    });

    acTestWidgets(
      'the field offers its own clear once anything is typed',
      <String>[],
      (WidgetTester tester) async {
        await pumpSurface(tester, peopleSurface());
        expect(
          find.byTooltip('Clear search'),
          findsNothing,
          reason: 'an empty field has nothing to clear',
        );

        await typeSearch(tester, 'sunita');
        expect(find.byTooltip('Clear search'), findsOneWidget);

        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump();

        expect(find.byType(ListTile), findsNWidgets(3));
      },
    );
  });

  group('every list surface', () {
    for (final MapEntry<String, Widget Function()> surface
        in kPopulated.entries) {
      acTestWidgets('${surface.key} has a search field', <String>[], (
        WidgetTester tester,
      ) async {
        await pumpSurface(tester, surface.value());

        expect(find.byType(SearchField), findsOneWidget);
      });
    }

    for (final MapEntry<String, Widget Function()> surface in kEmpty.entries) {
      acTestWidgets(
        '${surface.key} with nothing in it keeps its own empty state',
        <String>[],
        (WidgetTester tester) async {
          await pumpSurface(tester, surface.value());

          expect(
            find.byType(EmptyState),
            findsOneWidget,
            reason: 'a list with nothing in it yet is not a failed search',
          );
          expect(
            find.byType(NoSearchMatch),
            findsNothing,
            reason: 'nothing was searched',
          );
          expect(
            find.byType(SearchField),
            findsNothing,
            reason:
                'a field over an empty list is noise on the one screen '
                'that has to explain itself',
          );
        },
      );
    }
  });

  group('the matcher itself', () {
    acTest('an empty query keeps everything', <String>[], () {
      expect(matchesSearch('', <String?>['Meera Joshi']), isTrue);
      expect(matchesSearch('   ', <String?>['Meera Joshi']), isTrue);
    });

    acTest('a null field is skipped rather than matched', <String>[], () {
      expect(matchesSearch('meera', <String?>[null, 'Meera Joshi']), isTrue);
      expect(matchesSearch('meera', <String?>[null, null]), isFalse);
    });

    acTest('terms are split on any run of whitespace', <String>[], () {
      expect(searchTerms('  meera   joshi '), <String>['meera', 'joshi']);
      expect(searchTerms('   '), isEmpty);
    });
  });
}

/// The title of every row currently on screen, in the order they are laid out.
List<String> rowTitles(WidgetTester tester) => <String>[
  for (final ListTile tile in tester.widgetList<ListTile>(
    find.byType(ListTile),
  ))
    if (tile.title case final Text title) title.data ?? '',
];
