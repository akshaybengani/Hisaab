import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;

import '../constants.dart';
import '../helpers/dates.dart';
import '../helpers/ledger_math.dart';
import '../helpers/stock_math.dart';
import '../models/models.dart';
import '../repositories/contracts.dart';

/// The one piece of state every screen reads.
///
/// It holds the rows in memory and reloads all of them after each write. At
/// this data size, one household's ledger, that is cheaper than keeping a
/// dozen caches honest, and it means no screen can show a figure derived from
/// rows that have since changed.
///
/// Nothing here stores a balance. Balances, statements, stock levels and the
/// shopping list are worked out from the loaded rows on every read, through
/// [LedgerMath] and [StockMath].
class AppState extends ChangeNotifier {
  AppState(this._repos);

  final Repositories _repos;

  /// The storage bundle, for the services that take a repository rather than
  /// already-loaded rows. The screens still read their data from this state,
  /// never straight from here.
  Repositories get repositories => _repos;

  bool _loading = false;
  bool _loadedOnce = false;
  Object? _loadError;

  List<Person> _people = const <Person>[];
  List<Product> _products = const <Product>[];
  List<DeliveryWithItems> _deliveries = const <DeliveryWithItems>[];
  Map<int, List<MoneyEntry>> _entriesByPerson = const <int, List<MoneyEntry>>{};
  List<ProductRequest> _pendingRequests = const <ProductRequest>[];
  List<ProductRequest> _orderedRequests = const <ProductRequest>[];
  List<StockAdjustment> _adjustments = const <StockAdjustment>[];
  List<PurchaseWithItems> _purchases = const <PurchaseWithItems>[];
  List<Expense> _expenses = const <Expense>[];
  List<ExpenseCategory> _categories = const <ExpenseCategory>[];
  Map<String, String> _settings = const <String, String>{};

  bool get loading => _loading;
  bool get loadedOnce => _loadedOnce;

  /// Set where storage itself failed, which is a different problem from a
  /// derived figure failing.
  Object? get loadError => _loadError;

  List<Person> get people => _people;
  List<Product> get products => _products;
  List<Product> get activeProducts =>
      _products.where((Product p) => !p.archived).toList(growable: false);
  List<DeliveryWithItems> get deliveries => _deliveries;
  List<ProductRequest> get pendingRequests => _pendingRequests;
  List<ProductRequest> get orderedRequests => _orderedRequests;
  List<StockAdjustment> get adjustments => _adjustments;
  List<PurchaseWithItems> get purchases => _purchases;
  List<Expense> get expenses => _expenses;
  List<ExpenseCategory> get categories => _categories;
  Map<String, String> get settings => _settings;

  Map<int, Product> get productsById => <int, Product>{
    for (final Product p in _products)
      if (p.id != null) p.id!: p,
  };

  Map<int, Person> get peopleById => <int, Person>{
    for (final Person p in _people)
      if (p.id != null) p.id!: p,
  };

  Map<int, ExpenseCategory> get categoriesById => <int, ExpenseCategory>{
    for (final ExpenseCategory c in _categories)
      if (c.id != null) c.id!: c,
  };

  List<MoneyEntry> entriesFor(int personId) =>
      _entriesByPerson[personId] ?? const <MoneyEntry>[];

  List<DeliveryWithItems> deliveriesFor(int personId) =>
      _deliveriesByPerson[personId] ?? const <DeliveryWithItems>[];

  // ---------------------------------------------------------------- loading

  /// Reads every table. Called once at boot and again after each write.
  Future<void> load() async {
    _loading = true;
    try {
      final List<Person> people = await _repos.people.all();
      final List<Product> products = await _repos.products.all(
        includeArchived: true,
      );
      final List<DeliveryWithItems> deliveries = await _repos.deliveries.all();

      final Map<int, List<MoneyEntry>> entries = <int, List<MoneyEntry>>{};
      for (final Person person in people) {
        final int? id = person.id;
        if (id == null) continue;
        entries[id] = await _repos.money.forPerson(id);
      }

      _people = people;
      _products = products;
      _deliveries = deliveries;
      _entriesByPerson = entries;
      _pendingRequests = await _repos.requests.byStatus(RequestStatus.pending);
      _orderedRequests = await _repos.requests.byStatus(RequestStatus.ordered);
      _adjustments = await _repos.stock.all();
      _purchases = await _repos.purchases.all();
      _expenses = await _repos.expenses.all();
      _categories = await _repos.expenses.categories(includeArchived: true);
      _settings = await _repos.settings.readAll();
      _loadError = null;
    } on Object catch (error, stack) {
      _loadError = error;
      debugPrint('Hisaab could not read its data: $error\n$stack');
    } finally {
      _loading = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- derived

  /// Runs a derived computation and reports failure as null.
  ///
  /// Every derived figure comes from a pure function over rows that were just
  /// read, so a failure here is a bug in that function, never stale data. A
  /// screen shows a notice instead of the figure rather than taking the whole
  /// app down, because a ledger the owner cannot open is worse than one
  /// missing a total.
  T? _derive<T>(T Function() compute) {
    try {
      return compute();
    } on Object catch (error, stack) {
      debugPrint('Hisaab could not work out a figure: $error\n$stack');
      return null;
    }
  }

  Map<int, List<DeliveryWithItems>> get _deliveriesByPerson {
    final Map<int, List<DeliveryWithItems>> out =
        <int, List<DeliveryWithItems>>{};
    for (final DeliveryWithItems delivery in _deliveries) {
      out
          .putIfAbsent(delivery.delivery.personId, () => <DeliveryWithItems>[])
          .add(delivery);
    }
    return out;
  }

  /// Everyone's position, for the dues list.
  List<PersonBalance>? get balances => _derive(
    () => LedgerMath.balances(
      people: _people,
      deliveriesByPerson: _deliveriesByPerson,
      entriesByPerson: _entriesByPerson,
    ),
  );

  Statement? statementFor(Person person) {
    final int? id = person.id;
    if (id == null) return null;
    return _derive(
      () => LedgerMath.buildStatement(
        person: person,
        deliveries: deliveriesFor(id),
        entries: entriesFor(id),
        productsById: productsById,
        generatedAt: DateTime.now(),
      ),
    );
  }

  int? productDueFor(int personId) => _derive(
    () => LedgerMath.productBalance(
      deliveriesFor(personId),
      entriesFor(personId),
    ),
  );

  int? cashDueFor(int personId) =>
      _derive(() => LedgerMath.cashBalance(entriesFor(personId)));

  List<PurchaseItem> _purchaseItemsFor(int productId) => <PurchaseItem>[
    for (final PurchaseWithItems purchase in _purchases)
      ...purchase.items.where((PurchaseItem i) => i.productId == productId),
  ];

  List<DeliveryItem> _deliveryItemsFor(int productId) => <DeliveryItem>[
    for (final DeliveryWithItems delivery in _deliveries)
      ...delivery.items.where((DeliveryItem i) => i.productId == productId),
  ];

  List<StockAdjustment> _adjustmentsFor(int productId) => _adjustments
      .where((StockAdjustment a) => a.productId == productId)
      .toList(growable: false);

  Map<int, DateTime> get _purchaseDates => <int, DateTime>{
    for (final PurchaseWithItems p in _purchases)
      if (p.purchase.id != null) p.purchase.id!: p.purchase.date,
  };

  Map<int, DateTime> get _deliveryDates => <int, DateTime>{
    for (final DeliveryWithItems d in _deliveries)
      if (d.delivery.id != null) d.delivery.id!: d.delivery.date,
  };

  /// One level per unarchived product, in name order.
  List<StockLevel>? get stockLevels => _derive(() {
    final List<StockLevel> levels = <StockLevel>[];
    for (final Product product in activeProducts) {
      final int id = product.id ?? -1;
      levels.add(
        StockMath.level(
          product: product,
          purchaseItems: _purchaseItemsFor(id),
          deliveryItems: _deliveryItemsFor(id),
          adjustments: _adjustmentsFor(id),
        ),
      );
    }
    levels.sort(
      (StockLevel a, StockLevel b) => a.product.name.compareTo(b.product.name),
    );
    return levels;
  });

  List<StockMovement>? historyFor(Product product) {
    final int id = product.id ?? -1;
    return _derive(
      () => StockMath.history(
        purchaseItems: _purchaseItemsFor(id),
        deliveryItems: _deliveryItemsFor(id),
        adjustments: _adjustmentsFor(id),
        purchaseDates: _purchaseDates,
        deliveryDates: _deliveryDates,
      ),
    );
  }

  /// The difference a recount has to store. Goes through [StockMath] rather
  /// than being worked out here, so the rule lives in one place.
  int? recountDelta({required int currentOnHand, required int countedOnHand}) =>
      _derive(
        () => StockMath.recountDelta(
          currentOnHand: currentOnHand,
          countedOnHand: countedOnHand,
        ),
      );

  List<ShoppingListLine>? shoppingListFor(List<ProductRequest> requests) =>
      _derive(
        () => StockMath.shoppingList(
          pending: requests,
          productsById: productsById,
        ),
      );

  // ---------------------------------------------------------------- writes

  Future<void> savePerson(Person person) async {
    if (person.id == null) {
      await _repos.people.insert(person);
    } else {
      await _repos.people.update(person);
    }
    await load();
  }

  Future<void> setPersonArchived(int id, {required bool archived}) async {
    await _repos.people.setArchived(id, archived: archived);
    await load();
  }

  Future<void> saveProduct(Product product) async {
    if (product.id == null) {
      await _repos.products.insert(product);
    } else {
      await _repos.products.update(product);
    }
    await load();
  }

  Future<void> setProductArchived(int id, {required bool archived}) async {
    await _repos.products.setArchived(id, archived: archived);
    await load();
  }

  Future<void> saveDelivery(Delivery delivery, List<DeliveryItem> items) async {
    if (delivery.id == null) {
      await _repos.deliveries.insert(delivery, items);
    } else {
      await _repos.deliveries.update(delivery, items);
    }
    await load();
  }

  Future<void> recordMoney(MoneyEntry entry) async {
    await _repos.money.insert(entry);
    await load();
  }

  /// Records the payment and, where the user chose to clear the leftover, the
  /// write-off or round-off beside it. Two rows, because the cash that moved
  /// and the decision to stop chasing the rest are different facts.
  Future<void> recordCollection(
    MoneyEntry payment, {
    MoneyEntry? clearing,
  }) async {
    await _repos.money.insert(payment);
    if (clearing != null) {
      await _repos.money.insert(clearing);
    }
    await load();
  }

  Future<void> addRequest(ProductRequest request) async {
    await _repos.requests.insert(request);
    await load();
  }

  Future<void> setRequestStatus(int id, RequestStatus status) async {
    await _repos.requests.setStatus(id, status);
    await load();
  }

  Future<void> markRequestsOrdered(Iterable<int> ids) async {
    for (final int id in ids) {
      await _repos.requests.setStatus(id, RequestStatus.ordered);
    }
    await load();
  }

  Future<void> convertRequestToDelivery(
    int requestId,
    DeliveryItem item,
  ) async {
    await _repos.requests.convertToDelivery(requestId, item);
    await load();
  }

  Future<void> adjustStock(StockAdjustment adjustment) async {
    await _repos.stock.insert(adjustment);
    await load();
  }

  /// Writes the movement and the matching expense in one transaction, which is
  /// the only place the ledger half and the expense half of the app touch.
  /// See spec-27 dec-3.
  Future<void> recordPersonalUse({
    required Product product,
    required int qty,
    int? categoryId,
    String? note,
  }) async {
    final DateTime date = Dates.today();
    await _repos.stock.insertWithExpense(
      StockAdjustment(
        id: null,
        productId: product.id ?? -1,
        qtyDelta: -qty,
        reason: StockReason.personalUse,
        date: date,
        note: note,
      ),
      Expense(
        id: null,
        date: date,
        amountPaise: qty * product.currentPricePaise,
        categoryId: categoryId,
        note: note ?? '${product.name} used at home',
      ),
    );
    await load();
  }

  Future<void> savePurchase(
    Purchase purchase,
    List<PurchaseItem> items, {
    Expense? absorbedExpense,
  }) async {
    if (purchase.id == null) {
      await _repos.purchases.insert(purchase, items);
    } else {
      await _repos.purchases.update(purchase, items);
    }
    if (absorbedExpense != null) {
      await _repos.expenses.insert(absorbedExpense);
    }
    await load();
  }

  Future<void> saveExpense(Expense expense) async {
    if (expense.id == null) {
      await _repos.expenses.insert(expense);
    } else {
      await _repos.expenses.update(expense);
    }
    await load();
  }

  Future<void> deleteExpense(int id) async {
    await _repos.expenses.delete(id);
    await load();
  }

  /// Returns the id of the category with this name, creating it only where no
  /// case-insensitive match exists. See spec-27 dec-14.
  Future<int> ensureCategory(String name) async {
    final int id = await _repos.expenses.ensureCategory(name);
    await load();
    return id;
  }

  Future<void> setCategoryArchived(int id, {required bool archived}) async {
    await _repos.expenses.setCategoryArchived(id, archived: archived);
    await load();
  }

  // -------------------------------------------------------------- settings

  String setting(String key, {String fallback = ''}) =>
      _settings[key] ?? fallback;

  Future<void> writeSetting(String key, String value) async {
    await _repos.settings.write(key, value);
    _settings = <String, String>{..._settings, key: value};
    notifyListeners();
  }

  /// Defaults to the device setting, which is what the brief asks for.
  ThemeMode get themeMode {
    switch (_settings[SettingKeys.themeMode]) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) =>
      writeSetting(SettingKeys.themeMode, switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
}
