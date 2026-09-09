import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/providers/app_state.dart';
import 'package:hisaab/theme/app_theme.dart';
import 'package:provider/provider.dart';

import 'fake_repositories.dart';

/// The surface every render test uses.
///
/// A 360 by 560 phone in logical pixels is the smallest screen this app is
/// expected on, and it is where overflow shows up first.
const Size kSmallPhone = Size(360, 560);

/// Pumps [child] on a small phone in one brightness, then fails on any
/// overflow or paint error it produced.
Future<void> pumpOnSmallPhone(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
  AppState? state,
}) async {
  tester.view.physicalSize = kSmallPhone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final Widget app = MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    home: child,
  );

  await tester.pumpWidget(
    state == null
        ? app
        : ChangeNotifierProvider<AppState>.value(value: state, child: app),
  );
  await tester.pump();
  expect(
    tester.takeException(),
    isNull,
    reason: 'rendering overflowed or threw on a 360 by 560 surface',
  );
}

/// Scrolls a control into view, then taps it.
///
/// A 360 by 560 phone cannot show a whole form at once, which is the point of
/// testing there. A list built lazily has not created its off screen rows at
/// all, so the scroll has to come before the finder can resolve.
Future<void> tapAfterScroll(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      120,
      // A text field carries its own Scrollable, so the list has to be named.
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pump();
}

/// Runs [body] with [debugPrint] quiet, restoring it before the test ends.
///
/// The derived figures come from arithmetic another lane is still writing, so
/// a connected screen logs the failure and shows a notice. Without this, that
/// log buries a real failure. It has to be restored inside the test body,
/// because the framework checks the foundation debug variables before a tear
/// down runs.
Future<void> withQuietLogs(Future<void> Function() body) async {
  final DebugPrintCallback original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {};
  try {
    await body();
  } finally {
    debugPrint = original;
  }
}

/// A loaded [AppState] over the in-memory fake.
Future<AppState> loadedState({bool seeded = true}) async {
  final AppState state = AppState(
    seeded ? FakeRepositories.seeded() : FakeRepositories(),
  );
  await state.load();
  return state;
}

// ------------------------------------------------------------ sample models
//
// Hand built, so these tests keep passing whatever the ledger and stock
// arithmetic do. Nothing here calls LedgerMath or StockMath.

const Person kMeera = Person(id: 1, name: 'Meera Joshi', phone: '9876500001');
const Person kSunita = Person(id: 2, name: 'Sunita Rao', isHousehold: true);

const Product kShake = Product(
  id: 1,
  name: 'Formula 1 shake',
  unitLabel: 'tub',
  currentPricePaise: 205000,
  category: 'Nutrition',
);
const Product kTea = Product(
  id: 2,
  name: 'Afresh tea',
  unitLabel: 'jar',
  currentPricePaise: 122500,
);

List<PersonBalance> sampleBalances() => <PersonBalance>[
  PersonBalance(
    person: kMeera,
    productDuePaise: 410000,
    cashDuePaise: 150000,
    lastActivity: DateTime(2026, 9, 5),
  ),
  PersonBalance(
    person: kSunita,
    productDuePaise: -75050,
    cashDuePaise: 0,
    lastActivity: DateTime(2026, 8, 30),
  ),
];

/// A statement whose one delivery was closed by a payment plus a discount.
///
/// Hand built like the rest of these samples, so the render test stays honest
/// about what it is checking: the wording, not the allocation. See dec-15.
Statement settledStatement() => Statement(
  person: kMeera,
  products: StatementGroup(
    title: 'Product dues',
    lines: <StatementLine>[
      StatementLine(
        date: DateTime(2026, 9, 2),
        description: 'Formula 1 shake',
        amountPaise: 95000,
        settlement: SettlementState.settled,
        concededPaise: 5000,
        detail: '1 tub at 950',
      ),
      StatementLine(
        date: DateTime(2026, 9, 5),
        description: 'Payment received',
        amountPaise: -90000,
      ),
      StatementLine(
        date: DateTime(2026, 9, 5),
        description: 'Discount given',
        amountPaise: -5000,
      ),
    ],
  ),
  cash: const StatementGroup(title: 'Cash', lines: <StatementLine>[]),
  generatedAt: DateTime(2026, 9, 9),
);

Statement sampleStatement({bool bothPools = true}) => Statement(
  person: kMeera,
  products: StatementGroup(
    title: 'Product dues',
    lines: <StatementLine>[
      StatementLine(
        date: DateTime(2026, 9, 2),
        description: 'Formula 1 shake',
        amountPaise: 410000,
        forMember: 'Ananya',
        settlement: SettlementState.partlyPaid,
        detail: '2 tubs at 2,050',
      ),
      StatementLine(
        date: DateTime(2026, 9, 5),
        description: 'Payment received',
        amountPaise: -200000,
      ),
    ],
  ),
  cash: StatementGroup(
    title: 'Cash',
    lines: bothPools
        ? <StatementLine>[
            StatementLine(
              date: DateTime(2026, 8, 18),
              description: 'Cash lent',
              amountPaise: 150000,
            ),
          ]
        : const <StatementLine>[],
  ),
  generatedAt: DateTime(2026, 9, 9),
);

List<StockLevel> sampleStockLevels() => const <StockLevel>[
  StockLevel(
    product: kShake,
    onHand: 1,
    purchased: 3,
    delivered: 2,
    adjusted: 0,
  ),
  StockLevel(
    product: kTea,
    onHand: 0,
    purchased: 2,
    delivered: 1,
    adjusted: -1,
  ),
];

List<StockMovement> sampleMovements() => <StockMovement>[
  StockMovement(
    date: DateTime(2026, 8, 20),
    label: 'Bought from Distributor',
    qtyDelta: 3,
    runningOnHand: 3,
    detail: '3 tubs at 2,000',
  ),
  StockMovement(
    date: DateTime(2026, 9, 2),
    label: 'Delivered to Meera Joshi',
    qtyDelta: -2,
    runningOnHand: 1,
  ),
];

List<ShoppingListLine> sampleShoppingList() => const <ShoppingListLine>[
  ShoppingListLine(
    productId: 2,
    productName: 'Afresh tea',
    unitLabel: 'jar',
    qty: 4,
    requestCount: 2,
  ),
];

List<ProductRequest> samplePendingRequests() => <ProductRequest>[
  ProductRequest(
    id: 1,
    personId: 2,
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
  ),
];

List<ProductRequest> sampleOrderedRequests() => <ProductRequest>[
  ProductRequest(
    id: 3,
    personId: 1,
    productId: 1,
    qty: 2,
    status: RequestStatus.ordered,
    createdAt: DateTime(2026, 9, 1),
  ),
];

List<PurchaseWithItems> samplePurchases() => <PurchaseWithItems>[
  PurchaseWithItems(
    purchase: Purchase(
      id: 1,
      date: DateTime(2026, 8, 20),
      totalPaidPaise: 620000,
      vendor: 'Distributor',
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
];

List<Expense> sampleExpenses() => <Expense>[
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
    amountPaise: 205000,
    categoryId: 1,
    note: 'Formula 1 shake used at home',
    stockAdjustmentId: 1,
  ),
];

const List<ExpenseCategory> kCategories = <ExpenseCategory>[
  ExpenseCategory(id: 1, name: 'Travel'),
  ExpenseCategory(id: 2, name: 'Packaging', archived: true),
];

Map<int, Product> get kProductsById => const <int, Product>{1: kShake, 2: kTea};

Map<int, Person> get kPeopleById => const <int, Person>{1: kMeera, 2: kSunita};

Map<int, ExpenseCategory> get kCategoriesById => <int, ExpenseCategory>{
  for (final ExpenseCategory c in kCategories)
    if (c.id != null) c.id!: c,
};

/// The settings screen's own values, so its fields are not all empty.
Map<String, String> sampleSettings() => <String, String>{
  SettingKeys.pdfHeader: 'Hisaab statement',
  SettingKeys.pdfFooter: 'Pay by UPI to meera@bank',
  SettingKeys.templateStatement: 'Here is your statement.',
  SettingKeys.themeMode: 'system',
};
