import 'package:hisaab/constants.dart';
import 'package:hisaab/helpers/dates.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/repositories/contracts.dart';

/// An in-memory [Repositories], so a connected screen can be pumped without a
/// database.
///
/// It follows the contracts rather than the eventual sqflite behaviour: ids
/// are handed out in order, requests come back oldest first, and a disallowed
/// status move is rejected rather than applied.
class FakeRepositories implements Repositories {
  FakeRepositories();

  /// A book with two people, two products, a delivery, a payment, a pending
  /// request, a purchase and an expense. Enough to render every surface.
  factory FakeRepositories.seeded() {
    final FakeRepositories repos = FakeRepositories();
    final FakeProductRepository products = repos.products;
    final FakePersonRepository people = repos.people;

    products.rows
      ..add(
        const Product(
          id: 1,
          name: 'Formula 1 shake',
          unitLabel: 'tub',
          currentPricePaise: 205000,
          category: 'Nutrition',
        ),
      )
      ..add(
        const Product(
          id: 2,
          name: 'Afresh tea',
          unitLabel: 'jar',
          currentPricePaise: 122500,
          category: 'Nutrition',
        ),
      );
    products.nextId = 3;

    people.rows
      ..add(const Person(id: 1, name: 'Meera Joshi', phone: '9876500001'))
      ..add(const Person(id: 2, name: 'Sunita Rao', isHousehold: true));
    people.nextId = 3;

    repos.deliveries.rows.add(
      DeliveryWithItems(
        delivery: Delivery(
          id: 1,
          personId: 1,
          date: DateTime(2026, 9, 2),
          forMember: 'Ananya',
        ),
        items: const <DeliveryItem>[
          DeliveryItem(
            id: 1,
            deliveryId: 1,
            productId: 1,
            qty: 2,
            unitPricePaise: 205000,
          ),
        ],
      ),
    );
    repos.deliveries.nextId = 2;

    repos.money.rows.add(
      MoneyEntry(
        id: 1,
        personId: 1,
        date: DateTime(2026, 9, 5),
        amountPaise: 200000,
        direction: MoneyDirection.incoming,
        kind: MoneyKind.paymentReceived,
        method: 'UPI',
      ),
    );
    repos.money.nextId = 2;

    repos.requests.rows.add(
      ProductRequest(
        id: 1,
        personId: 2,
        productId: 2,
        qty: 3,
        status: RequestStatus.pending,
        createdAt: DateTime(2026, 8, 28),
      ),
    );
    repos.requests.nextId = 2;

    repos.purchases.rows.add(
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
    );
    repos.purchases.nextId = 2;

    repos.expenses.categoryRows.add(
      const ExpenseCategory(id: 1, name: 'Travel'),
    );
    repos.expenses.nextCategoryId = 2;
    repos.expenses.rows.add(
      Expense(
        id: 1,
        date: DateTime(2026, 9, 4),
        amountPaise: 45000,
        categoryId: 1,
        note: 'Auto to the distributor',
      ),
    );
    repos.expenses.nextId = 2;

    repos.stock.rows.add(
      StockAdjustment(
        id: 1,
        productId: 1,
        qtyDelta: -1,
        reason: StockReason.personalUse,
        date: DateTime(2026, 9, 3),
      ),
    );
    repos.stock.nextId = 2;

    return repos;
  }

  @override
  final FakeProductRepository products = FakeProductRepository();
  @override
  final FakePersonRepository people = FakePersonRepository();
  @override
  final FakeDeliveryRepository deliveries = FakeDeliveryRepository();
  @override
  final FakeMoneyRepository money = FakeMoneyRepository();
  @override
  late final FakeStockRepository stock = FakeStockRepository(expenses);
  @override
  final FakePurchaseRepository purchases = FakePurchaseRepository();
  @override
  late final FakeRequestRepository requests = FakeRequestRepository(deliveries);
  @override
  final FakeExpenseRepository expenses = FakeExpenseRepository();
  @override
  final FakeSettingsRepository settings = FakeSettingsRepository();
}

class FakeProductRepository implements ProductRepository {
  final List<Product> rows = <Product>[];
  final List<PriceChange> priceRows = <PriceChange>[];
  int nextId = 1;

  @override
  Future<List<Product>> all({bool includeArchived = false}) async => rows
      .where((Product p) => includeArchived || !p.archived)
      .toList(growable: false);

  @override
  Future<Product?> byId(int id) async =>
      rows.where((Product p) => p.id == id).firstOrNull;

  @override
  Future<int> insert(Product product) async {
    final int id = nextId++;
    rows.add(product.copyWith(id: id));
    return id;
  }

  @override
  Future<void> update(Product product) async {
    final int index = rows.indexWhere((Product p) => p.id == product.id);
    if (index < 0) return;
    if (rows[index].currentPricePaise != product.currentPricePaise) {
      priceRows.add(
        PriceChange(
          id: priceRows.length + 1,
          productId: product.id ?? -1,
          pricePaise: product.currentPricePaise,
          effectiveFrom: Dates.today(),
        ),
      );
    }
    rows[index] = product;
  }

  @override
  Future<void> setArchived(int id, {required bool archived}) async {
    final int index = rows.indexWhere((Product p) => p.id == id);
    if (index < 0) return;
    rows[index] = rows[index].copyWith(archived: archived);
  }

  @override
  Future<List<PriceChange>> priceHistory(int productId) async => priceRows
      .where((PriceChange c) => c.productId == productId)
      .toList(growable: false);
}

class FakePersonRepository implements PersonRepository {
  final List<Person> rows = <Person>[];
  int nextId = 1;

  @override
  Future<List<Person>> all({bool includeArchived = false}) async => rows
      .where((Person p) => includeArchived || !p.archived)
      .toList(growable: false);

  @override
  Future<Person?> byId(int id) async =>
      rows.where((Person p) => p.id == id).firstOrNull;

  @override
  Future<int> insert(Person person) async {
    final int id = nextId++;
    rows.add(person.copyWith(id: id));
    return id;
  }

  @override
  Future<void> update(Person person) async {
    final int index = rows.indexWhere((Person p) => p.id == person.id);
    if (index >= 0) rows[index] = person;
  }

  @override
  Future<void> setArchived(int id, {required bool archived}) async {
    final int index = rows.indexWhere((Person p) => p.id == id);
    if (index < 0) return;
    rows[index] = rows[index].copyWith(archived: archived);
  }
}

class FakeDeliveryRepository implements DeliveryRepository {
  final List<DeliveryWithItems> rows = <DeliveryWithItems>[];
  int nextId = 1;
  int nextItemId = 1;

  @override
  Future<List<DeliveryWithItems>> all() async => List<DeliveryWithItems>.of(rows);

  @override
  Future<DeliveryWithItems?> byId(int id) async =>
      rows.where((DeliveryWithItems d) => d.delivery.id == id).firstOrNull;

  @override
  Future<List<DeliveryWithItems>> forPerson(int personId) async => rows
      .where((DeliveryWithItems d) => d.delivery.personId == personId)
      .toList(growable: false);

  @override
  Future<int> insert(Delivery delivery, List<DeliveryItem> items) async {
    final int id = nextId++;
    rows.add(
      DeliveryWithItems(
        delivery: Delivery(
          id: id,
          personId: delivery.personId,
          date: delivery.date,
          forMember: delivery.forMember,
          note: delivery.note,
        ),
        items: <DeliveryItem>[
          for (final DeliveryItem item in items)
            DeliveryItem(
              id: nextItemId++,
              deliveryId: id,
              productId: item.productId,
              qty: item.qty,
              unitPricePaise: item.unitPricePaise,
            ),
        ],
      ),
    );
    return id;
  }

  @override
  Future<void> update(Delivery delivery, List<DeliveryItem> items) async {
    final int index = rows.indexWhere(
      (DeliveryWithItems d) => d.delivery.id == delivery.id,
    );
    if (index < 0) return;
    rows[index] = DeliveryWithItems(delivery: delivery, items: items);
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((DeliveryWithItems d) => d.delivery.id == id);
}

class FakeMoneyRepository implements MoneyRepository {
  final List<MoneyEntry> rows = <MoneyEntry>[];
  int nextId = 1;

  @override
  Future<List<MoneyEntry>> forPerson(int personId) async => rows
      .where((MoneyEntry e) => e.personId == personId)
      .toList(growable: false);

  @override
  Future<int> insert(MoneyEntry entry) async {
    final int id = nextId++;
    rows.add(
      MoneyEntry(
        id: id,
        personId: entry.personId,
        date: entry.date,
        amountPaise: entry.amountPaise,
        direction: entry.direction,
        kind: entry.kind,
        method: entry.method,
        note: entry.note,
      ),
    );
    return id;
  }

  @override
  Future<void> update(MoneyEntry entry) async {
    final int index = rows.indexWhere((MoneyEntry e) => e.id == entry.id);
    if (index >= 0) rows[index] = entry;
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((MoneyEntry e) => e.id == id);
}

class FakeStockRepository implements StockRepository {
  FakeStockRepository(this._expenses);

  final FakeExpenseRepository _expenses;
  final List<StockAdjustment> rows = <StockAdjustment>[];
  int nextId = 1;

  @override
  Future<List<StockAdjustment>> all() async => List<StockAdjustment>.of(rows);

  @override
  Future<List<StockAdjustment>> forProduct(int productId) async => rows
      .where((StockAdjustment a) => a.productId == productId)
      .toList(growable: false);

  @override
  Future<int> insert(StockAdjustment adjustment) async {
    final int id = nextId++;
    rows.add(
      StockAdjustment(
        id: id,
        productId: adjustment.productId,
        qtyDelta: adjustment.qtyDelta,
        reason: adjustment.reason,
        date: adjustment.date,
        note: adjustment.note,
      ),
    );
    return id;
  }

  @override
  Future<int> insertWithExpense(
    StockAdjustment adjustment,
    Expense expense,
  ) async {
    final int id = await insert(adjustment);
    await _expenses.insert(
      Expense(
        id: null,
        date: expense.date,
        amountPaise: expense.amountPaise,
        categoryId: expense.categoryId,
        note: expense.note,
        stockAdjustmentId: id,
      ),
    );
    return id;
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((StockAdjustment a) => a.id == id);
}

class FakePurchaseRepository implements PurchaseRepository {
  final List<PurchaseWithItems> rows = <PurchaseWithItems>[];
  int nextId = 1;
  int nextItemId = 1;

  @override
  Future<List<PurchaseWithItems>> all() async =>
      List<PurchaseWithItems>.of(rows);

  @override
  Future<PurchaseWithItems?> byId(int id) async =>
      rows.where((PurchaseWithItems p) => p.purchase.id == id).firstOrNull;

  @override
  Future<int> insert(Purchase purchase, List<PurchaseItem> items) async {
    final int id = nextId++;
    rows.add(
      PurchaseWithItems(
        purchase: Purchase(
          id: id,
          date: purchase.date,
          totalPaidPaise: purchase.totalPaidPaise,
          vendor: purchase.vendor,
          note: purchase.note,
        ),
        items: <PurchaseItem>[
          for (final PurchaseItem item in items)
            PurchaseItem(
              id: nextItemId++,
              purchaseId: id,
              productId: item.productId,
              qty: item.qty,
              unitCostPaise: item.unitCostPaise,
            ),
        ],
      ),
    );
    return id;
  }

  @override
  Future<void> update(Purchase purchase, List<PurchaseItem> items) async {
    final int index = rows.indexWhere(
      (PurchaseWithItems p) => p.purchase.id == purchase.id,
    );
    if (index < 0) return;
    rows[index] = PurchaseWithItems(purchase: purchase, items: items);
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((PurchaseWithItems p) => p.purchase.id == id);
}

class FakeRequestRepository implements RequestRepository {
  FakeRequestRepository(this._deliveries);

  final FakeDeliveryRepository _deliveries;
  final List<ProductRequest> rows = <ProductRequest>[];
  int nextId = 1;

  @override
  Future<List<ProductRequest>> byStatus(RequestStatus status) async {
    final List<ProductRequest> matching = rows
        .where((ProductRequest r) => r.status == status)
        .toList()
      ..sort(
        (ProductRequest a, ProductRequest b) =>
            a.createdAt.compareTo(b.createdAt),
      );
    return matching;
  }

  @override
  Future<List<ProductRequest>> forPerson(int personId) async => rows
      .where((ProductRequest r) => r.personId == personId)
      .toList(growable: false);

  @override
  Future<int> insert(ProductRequest request) async {
    final int id = nextId++;
    rows.add(
      ProductRequest(
        id: id,
        personId: request.personId,
        productId: request.productId,
        qty: request.qty,
        status: request.status,
        createdAt: request.createdAt,
        forMember: request.forMember,
        note: request.note,
      ),
    );
    return id;
  }

  @override
  Future<void> setStatus(int id, RequestStatus status) async {
    final int index = rows.indexWhere((ProductRequest r) => r.id == id);
    if (index < 0) return;
    if (!rows[index].status.canMoveTo(status)) {
      throw StateError(
        'a request cannot move from ${rows[index].status.value} to '
        '${status.value}',
      );
    }
    rows[index] = rows[index].copyWith(status: status);
  }

  @override
  Future<int> convertToDelivery(int requestId, DeliveryItem item) async {
    final int index = rows.indexWhere((ProductRequest r) => r.id == requestId);
    if (index < 0) throw StateError('no request $requestId');
    final ProductRequest request = rows[index];
    final int deliveryId = await _deliveries.insert(
      Delivery(
        id: null,
        personId: request.personId,
        date: Dates.today(),
        forMember: request.forMember,
      ),
      <DeliveryItem>[item],
    );
    rows[index] = request.copyWith(status: RequestStatus.delivered);
    return deliveryId;
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((ProductRequest r) => r.id == id);
}

class FakeExpenseRepository implements ExpenseRepository {
  final List<Expense> rows = <Expense>[];
  final List<ExpenseCategory> categoryRows = <ExpenseCategory>[];
  int nextId = 1;
  int nextCategoryId = 1;

  @override
  Future<List<Expense>> all() async => List<Expense>.of(rows);

  @override
  Future<List<Expense>> inMonth(int year, int month) async => rows
      .where((Expense e) => e.date.year == year && e.date.month == month)
      .toList(growable: false);

  @override
  Future<int> insert(Expense expense) async {
    final int id = nextId++;
    rows.add(
      Expense(
        id: id,
        date: expense.date,
        amountPaise: expense.amountPaise,
        categoryId: expense.categoryId,
        note: expense.note,
        stockAdjustmentId: expense.stockAdjustmentId,
      ),
    );
    return id;
  }

  @override
  Future<void> update(Expense expense) async {
    final int index = rows.indexWhere((Expense e) => e.id == expense.id);
    if (index >= 0) rows[index] = expense;
  }

  @override
  Future<void> delete(int id) async =>
      rows.removeWhere((Expense e) => e.id == id);

  @override
  Future<List<ExpenseCategory>> categories({
    bool includeArchived = false,
  }) async => categoryRows
      .where((ExpenseCategory c) => includeArchived || !c.archived)
      .toList(growable: false);

  @override
  Future<int> ensureCategory(String name) async {
    final String wanted = name.trim().toLowerCase();
    for (final ExpenseCategory category in categoryRows) {
      if (category.name.trim().toLowerCase() == wanted) {
        return category.id ?? -1;
      }
    }
    final int id = nextCategoryId++;
    categoryRows.add(ExpenseCategory(id: id, name: name.trim()));
    return id;
  }

  @override
  Future<void> setCategoryArchived(int id, {required bool archived}) async {
    final int index = categoryRows.indexWhere(
      (ExpenseCategory c) => c.id == id,
    );
    if (index < 0) return;
    categoryRows[index] = categoryRows[index].copyWith(archived: archived);
  }
}

class FakeSettingsRepository implements SettingsRepository {
  final Map<String, String> rows = <String, String>{};

  @override
  Future<String?> read(String key) async => rows[key];

  @override
  Future<Map<String, String>> readAll() async => Map<String, String>.of(rows);

  @override
  Future<void> write(String key, String value) async => rows[key] = value;
}
