import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/repositories/contracts.dart';
import 'package:hisaab/repositories/factory.dart';
import 'package:hisaab/repositories/sqflite_repositories.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory home;
  late SqfliteRepositories repos;
  late int counter;

  /// A fresh file per test, so nothing leaks between them.
  setUp(() async {
    home = await Directory.systemTemp.createTemp('hisaab-repository-');
    counter = 0;
    final Repositories opened = await openRepositories(
      path: '${home.path}/book.db',
    );
    repos = opened as SqfliteRepositories;
  });

  tearDown(() async {
    await repos.close();
    await home.delete(recursive: true);
  });

  DateTime day(int d) => DateTime(2026, 2, d);

  Future<int> aPerson({String name = 'Meera', bool household = false}) =>
      repos.people.insert(
        Person(id: null, name: name, isHousehold: household),
      );

  Future<int> aProduct({String name = 'Formula 1', int paise = 205000}) =>
      repos.products.insert(
        Product(
          id: null,
          name: name,
          unitLabel: 'tub',
          currentPricePaise: paise,
        ),
      );

  /// A delivery line for [productId] that has not been attached yet.
  DeliveryItem line(int productId, {int qty = 1, int paise = 205000}) =>
      DeliveryItem(
        id: null,
        deliveryId: null,
        productId: productId,
        qty: qty,
        unitPricePaise: paise,
      );

  int nextId() => ++counter + 900000;

  group('products', () {
    test('insert, read back, and update the name', () async {
      final int id = await aProduct();
      final Product? stored = await repos.products.byId(id);

      expect(stored, isNotNull);
      expect(stored!.name, 'Formula 1');
      expect(stored.unitLabel, 'tub');
      expect(stored.currentPricePaise, 205000);
      expect(stored.archived, isFalse);

      await repos.products.update(stored.copyWith(name: 'Formula 1 vanilla'));
      expect((await repos.products.byId(id))!.name, 'Formula 1 vanilla');
    });

    test('listing is alphabetical and ignores case', () async {
      await aProduct(name: 'afresh');
      await aProduct(name: 'Formula 1');
      await aProduct(name: 'Beta heart');

      expect(
        (await repos.products.all())
            .map((Product product) => product.name)
            .toList(),
        <String>['afresh', 'Beta heart', 'Formula 1'],
      );
    });

    test('an unchanged price writes no history row', () async {
      final int id = await aProduct();
      final Product stored = (await repos.products.byId(id))!;

      await repos.products.update(stored.copyWith(unitLabel: 'jar'));
      await repos.products.update(stored.copyWith(category: 'shakes'));

      expect(await repos.products.priceHistory(id), isEmpty);
    });

    test('a changed price appends one history row carrying the new price',
        () async {
      final int id = await aProduct();
      final Product stored = (await repos.products.byId(id))!;

      await repos.products.update(stored.copyWith(currentPricePaise: 215000));
      await repos.products.update(stored.copyWith(currentPricePaise: 220000));

      final List<PriceChange> history = await repos.products.priceHistory(id);
      expect(
        history.map((PriceChange change) => change.pricePaise).toList(),
        <int>[215000, 220000],
      );
      expect(history.every((PriceChange change) => change.productId == id),
          isTrue);
      expect((await repos.products.byId(id))!.currentPricePaise, 220000);
    });

    test('a price change never rewrites a delivery line', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(3)),
        <DeliveryItem>[line(productId, qty: 2)],
      );

      final Product stored = (await repos.products.byId(productId))!;
      await repos.products.update(stored.copyWith(currentPricePaise: 300000));

      final List<DeliveryWithItems> after =
          await repos.deliveries.forPerson(personId);
      expect(after.single.items.single.unitPricePaise, 205000);
      expect(after.single.totalPaise, 410000);
    });

    test('updating a product that is not there is refused', () async {
      await expectLater(
        repos.products.update(
          Product(
            id: nextId(),
            name: 'ghost',
            unitLabel: 'tub',
            currentPricePaise: 1,
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('archiving hides the product and leaves its lines alone', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(3)),
        <DeliveryItem>[line(productId)],
      );

      await repos.products.setArchived(productId, archived: true);

      expect(await repos.products.all(), isEmpty);
      expect(await repos.products.all(includeArchived: true), hasLength(1));
      expect(await repos.products.byId(productId), isNotNull);
      final List<DeliveryWithItems> deliveries =
          await repos.deliveries.forPerson(personId);
      expect(deliveries.single.items.single.productId, productId);

      await repos.products.setArchived(productId, archived: false);
      expect(await repos.products.all(), hasLength(1));
    });
  });

  group('people', () {
    test('insert, read, update, and archive', () async {
      final int id = await repos.people.insert(
        const Person(
          id: null,
          name: 'Meera',
          phone: '9876500001',
          isHousehold: true,
        ),
      );
      final Person stored = (await repos.people.byId(id))!;
      expect(stored.phone, '9876500001');
      expect(stored.isHousehold, isTrue);

      await repos.people.update(stored.copyWith(note: 'flat 402'));
      expect((await repos.people.byId(id))!.note, 'flat 402');

      await repos.people.setArchived(id, archived: true);
      expect(await repos.people.all(), isEmpty);
      expect(await repos.people.all(includeArchived: true), hasLength(1));
    });

    test('archiving leaves every delivery and payment intact', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(3)),
        <DeliveryItem>[line(productId)],
      );
      await repos.money.insert(
        MoneyEntry(
          id: null,
          personId: personId,
          date: day(5),
          amountPaise: 100000,
          direction: MoneyDirection.incoming,
          kind: MoneyKind.paymentReceived,
        ),
      );

      await repos.people.setArchived(personId, archived: true);

      expect(await repos.deliveries.forPerson(personId), hasLength(1));
      expect(await repos.money.forPerson(personId), hasLength(1));
    });

    test('updating a person with no id is refused', () async {
      await expectLater(
        repos.people.update(const Person(id: null, name: 'ghost')),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('deliveries', () {
    test('the header and its lines land together', () async {
      final int personId = await aPerson();
      final int first = await aProduct(name: 'Formula 1');
      final int second = await aProduct(name: 'Afresh', paise: 62000);

      final int id = await repos.deliveries.insert(
        Delivery(
          id: null,
          personId: personId,
          date: day(3),
          forMember: 'Anu',
          note: 'left at the door',
        ),
        <DeliveryItem>[
          line(first, qty: 2),
          line(second, qty: 1, paise: 62000),
        ],
      );

      final DeliveryWithItems stored = (await repos.deliveries.byId(id))!;
      expect(stored.delivery.forMember, 'Anu');
      expect(stored.delivery.note, 'left at the door');
      expect(stored.items, hasLength(2));
      expect(stored.totalPaise, 472000);
      expect(
        stored.items.every((DeliveryItem item) => item.deliveryId == id),
        isTrue,
      );
    });

    test('a line naming a product that is not there rolls the whole insert '
        'back', () async {
      final int personId = await aPerson();

      await expectLater(
        repos.deliveries.insert(
          Delivery(id: null, personId: personId, date: day(3)),
          <DeliveryItem>[line(nextId())],
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await repos.deliveries.all(), isEmpty);
      final List<Map<String, Object?>> items =
          await repos.database.query('delivery_items');
      expect(items, isEmpty);
    });

    test('update replaces the lines rather than adding to them', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(3)),
        <DeliveryItem>[line(productId, qty: 1)],
      );

      await repos.deliveries.update(
        Delivery(id: id, personId: personId, date: day(4), note: 'corrected'),
        <DeliveryItem>[line(productId, qty: 5)],
      );

      final DeliveryWithItems stored = (await repos.deliveries.byId(id))!;
      expect(stored.items, hasLength(1));
      expect(stored.items.single.qty, 5);
      expect(stored.delivery.note, 'corrected');
    });

    test('a failed update leaves the old lines in place', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(3)),
        <DeliveryItem>[line(productId, qty: 1)],
      );

      await expectLater(
        repos.deliveries.update(
          Delivery(id: id, personId: personId, date: day(4)),
          <DeliveryItem>[line(nextId())],
        ),
        throwsA(isA<DatabaseException>()),
      );

      final DeliveryWithItems stored = (await repos.deliveries.byId(id))!;
      expect(stored.items, hasLength(1));
      expect(stored.items.single.qty, 1);
      expect(stored.delivery.date, day(3));
    });

    test('delete takes the lines with it', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(3)),
        <DeliveryItem>[line(productId)],
      );

      await repos.deliveries.delete(id);

      expect(await repos.deliveries.byId(id), isNull);
      expect(await repos.database.query('delivery_items'), isEmpty);
    });

    test('a person reads their deliveries oldest first', () async {
      final int personId = await aPerson();
      final int other = await aPerson(name: 'Sunita');
      final int productId = await aProduct();

      await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(9)),
        <DeliveryItem>[line(productId)],
      );
      await repos.deliveries.insert(
        Delivery(id: null, personId: personId, date: day(2)),
        <DeliveryItem>[line(productId)],
      );
      await repos.deliveries.insert(
        Delivery(id: null, personId: other, date: day(5)),
        <DeliveryItem>[line(productId)],
      );

      expect(
        (await repos.deliveries.forPerson(personId))
            .map((DeliveryWithItems each) => each.delivery.date)
            .toList(),
        <DateTime>[day(2), day(9)],
      );
      expect(await repos.deliveries.all(), hasLength(3));
    });
  });

  group('money', () {
    test('insert, read, update, and delete', () async {
      final int personId = await aPerson();
      final int id = await repos.money.insert(
        MoneyEntry(
          id: null,
          personId: personId,
          date: day(5),
          amountPaise: 100000,
          direction: MoneyDirection.incoming,
          kind: MoneyKind.paymentReceived,
          method: 'UPI',
        ),
      );

      MoneyEntry stored = (await repos.money.forPerson(personId)).single;
      expect(stored.id, id);
      expect(stored.amountPaise, 100000);
      expect(stored.direction, MoneyDirection.incoming);
      expect(stored.kind, MoneyKind.paymentReceived);
      expect(stored.method, 'UPI');
      expect(stored.signedPaise, -100000);

      await repos.money.update(
        MoneyEntry(
          id: id,
          personId: personId,
          date: day(5),
          amountPaise: 120000,
          direction: MoneyDirection.incoming,
          kind: MoneyKind.paymentReceived,
          method: 'cash',
        ),
      );
      stored = (await repos.money.forPerson(personId)).single;
      expect(stored.amountPaise, 120000);
      expect(stored.method, 'cash');

      await repos.money.delete(id);
      expect(await repos.money.forPerson(personId), isEmpty);
    });

    test('every kind round trips', () async {
      final int personId = await aPerson();
      for (final MoneyKind kind in MoneyKind.values) {
        await repos.money.insert(
          MoneyEntry(
            id: null,
            personId: personId,
            date: day(5),
            amountPaise: 1000,
            direction: MoneyDirection.outgoing,
            kind: kind,
          ),
        );
      }

      expect(
        (await repos.money.forPerson(personId))
            .map((MoneyEntry entry) => entry.kind)
            .toSet(),
        MoneyKind.values.toSet(),
      );
    });
  });

  group('stock', () {
    test('every tap writes one row and reads back oldest first', () async {
      final int productId = await aProduct();
      for (final int d in <int>[6, 2, 4]) {
        await repos.stock.insert(
          StockAdjustment(
            id: null,
            productId: productId,
            qtyDelta: -1,
            reason: StockReason.manual,
            date: day(d),
          ),
        );
      }

      expect(
        (await repos.stock.forProduct(productId))
            .map((StockAdjustment each) => each.date)
            .toList(),
        <DateTime>[day(2), day(4), day(6)],
      );
      expect(await repos.stock.all(), hasLength(3));
    });

    test('personal use writes the adjustment and its expense together',
        () async {
      final int productId = await aProduct();
      final int categoryId = await repos.expenses.ensureCategory('Personal');

      final int adjustmentId = await repos.stock.insertWithExpense(
        StockAdjustment(
          id: null,
          productId: productId,
          qtyDelta: -1,
          reason: StockReason.personalUse,
          date: day(6),
        ),
        Expense(
          id: null,
          date: day(6),
          amountPaise: 205000,
          categoryId: categoryId,
          note: 'used a tub',
        ),
      );

      final StockAdjustment adjustment =
          (await repos.stock.forProduct(productId)).single;
      expect(adjustment.id, adjustmentId);
      expect(adjustment.reason, StockReason.personalUse);

      final Expense expense = (await repos.expenses.all()).single;
      expect(expense.stockAdjustmentId, adjustmentId);
      expect(expense.isFromPersonalUse, isTrue);
      expect(expense.amountPaise, 205000);
    });

    test('a bad expense rolls the adjustment back too', () async {
      final int productId = await aProduct();

      await expectLater(
        repos.stock.insertWithExpense(
          StockAdjustment(
            id: null,
            productId: productId,
            qtyDelta: -1,
            reason: StockReason.personalUse,
            date: day(6),
          ),
          Expense(
            id: null,
            date: day(6),
            amountPaise: 205000,
            categoryId: nextId(),
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await repos.stock.all(), isEmpty);
      expect(await repos.expenses.all(), isEmpty);
    });

    test('deleting a personal use adjustment removes its expense only',
        () async {
      final int productId = await aProduct();
      final int adjustmentId = await repos.stock.insertWithExpense(
        StockAdjustment(
          id: null,
          productId: productId,
          qtyDelta: -1,
          reason: StockReason.personalUse,
          date: day(6),
        ),
        Expense(id: null, date: day(6), amountPaise: 205000),
      );
      await repos.expenses.insert(
        Expense(id: null, date: day(7), amountPaise: 30000, note: 'petrol'),
      );

      await repos.stock.delete(adjustmentId);

      final List<Expense> left = await repos.expenses.all();
      expect(left, hasLength(1));
      expect(left.single.note, 'petrol');
    });
  });

  group('purchases', () {
    test('the header and its lines land together', () async {
      final int productId = await aProduct();
      final int id = await repos.purchases.insert(
        Purchase(
          id: null,
          date: day(1),
          totalPaidPaise: 410000,
          vendor: 'distributor',
        ),
        <PurchaseItem>[
          PurchaseItem(
            id: null,
            purchaseId: null,
            productId: productId,
            qty: 2,
            unitCostPaise: 199000,
          ),
        ],
      );

      final PurchaseWithItems stored = (await repos.purchases.byId(id))!;
      expect(stored.purchase.vendor, 'distributor');
      expect(stored.items.single.qty, 2);
      expect(stored.lineTotalPaise, 398000);
      expect(stored.absorbedPaise, 12000);
    });

    test('a bad line rolls the whole insert back', () async {
      await expectLater(
        repos.purchases.insert(
          Purchase(id: null, date: day(1), totalPaidPaise: 410000),
          <PurchaseItem>[
            PurchaseItem(
              id: null,
              purchaseId: null,
              productId: nextId(),
              qty: 2,
              unitCostPaise: 199000,
            ),
          ],
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect(await repos.purchases.all(), isEmpty);
      expect(await repos.database.query('purchase_items'), isEmpty);
    });

    test('update replaces the lines, and delete takes them with it', () async {
      final int productId = await aProduct();
      final int id = await repos.purchases.insert(
        Purchase(id: null, date: day(1), totalPaidPaise: 410000),
        <PurchaseItem>[
          PurchaseItem(
            id: null,
            purchaseId: null,
            productId: productId,
            qty: 2,
            unitCostPaise: 199000,
          ),
        ],
      );

      await repos.purchases.update(
        Purchase(id: id, date: day(1), totalPaidPaise: 199000),
        <PurchaseItem>[
          PurchaseItem(
            id: null,
            purchaseId: null,
            productId: productId,
            qty: 1,
            unitCostPaise: 199000,
          ),
        ],
      );
      final PurchaseWithItems stored = (await repos.purchases.byId(id))!;
      expect(stored.items, hasLength(1));
      expect(stored.absorbedPaise, 0);

      await repos.purchases.delete(id);
      expect(await repos.purchases.all(), isEmpty);
      expect(await repos.database.query('purchase_items'), isEmpty);
    });
  });

  group('requests', () {
    Future<int> aRequest(int personId, int productId) => repos.requests.insert(
      ProductRequest(
        id: null,
        personId: personId,
        productId: productId,
        qty: 3,
        status: RequestStatus.pending,
        createdAt: day(4),
        note: 'asked on the stairs',
      ),
    );

    test('the lifecycle runs pending, ordered, delivered', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await aRequest(personId, productId);

      expect(
        (await repos.requests.byStatus(RequestStatus.pending)).single.id,
        id,
      );

      await repos.requests.setStatus(id, RequestStatus.ordered);
      expect(await repos.requests.byStatus(RequestStatus.pending), isEmpty);
      expect(
        (await repos.requests.byStatus(RequestStatus.ordered)).single.qty,
        3,
      );

      await repos.requests.setStatus(id, RequestStatus.delivered);
      expect(
        (await repos.requests.byStatus(RequestStatus.delivered)).single.id,
        id,
      );
    });

    test('a transition the lifecycle disallows is refused', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await aRequest(personId, productId);

      await expectLater(
        repos.requests.setStatus(id, RequestStatus.delivered),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        (await repos.requests.forPerson(personId)).single.status,
        RequestStatus.pending,
      );

      await repos.requests.setStatus(id, RequestStatus.cancelled);
      await expectLater(
        repos.requests.setStatus(id, RequestStatus.ordered),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        (await repos.requests.forPerson(personId)).single.status,
        RequestStatus.cancelled,
      );
    });

    test('a request that is not there is refused', () async {
      await expectLater(
        repos.requests.setStatus(nextId(), RequestStatus.ordered),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('converting writes the delivery and marks the request delivered',
        () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await aRequest(personId, productId);
      await repos.requests.setStatus(id, RequestStatus.ordered);

      final int deliveryId = await repos.requests.convertToDelivery(
        id,
        line(productId, qty: 3),
      );

      final DeliveryWithItems delivery =
          (await repos.deliveries.byId(deliveryId))!;
      expect(delivery.delivery.personId, personId);
      expect(delivery.delivery.note, 'asked on the stairs');
      expect(delivery.items.single.qty, 3);
      expect(delivery.totalPaise, 615000);
      expect(
        (await repos.requests.forPerson(personId)).single.status,
        RequestStatus.delivered,
      );
    });

    test('converting a pending request is refused, and nothing is written',
        () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await aRequest(personId, productId);

      await expectLater(
        repos.requests.convertToDelivery(id, line(productId, qty: 3)),
        throwsA(isA<ArgumentError>()),
      );

      expect(await repos.deliveries.all(), isEmpty);
      expect(
        (await repos.requests.forPerson(personId)).single.status,
        RequestStatus.pending,
      );
    });

    test('a bad line rolls the conversion back whole', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await aRequest(personId, productId);
      await repos.requests.setStatus(id, RequestStatus.ordered);

      await expectLater(
        repos.requests.convertToDelivery(id, line(nextId())),
        throwsA(isA<DatabaseException>()),
      );

      expect(await repos.deliveries.all(), isEmpty);
      expect(await repos.database.query('delivery_items'), isEmpty);
      expect(
        (await repos.requests.forPerson(personId)).single.status,
        RequestStatus.ordered,
      );
    });

    test('a status listing is oldest first', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      for (final int d in <int>[8, 1, 5]) {
        await repos.requests.insert(
          ProductRequest(
            id: null,
            personId: personId,
            productId: productId,
            qty: 1,
            status: RequestStatus.pending,
            createdAt: day(d),
          ),
        );
      }

      expect(
        (await repos.requests.byStatus(RequestStatus.pending))
            .map((ProductRequest each) => each.createdAt)
            .toList(),
        <DateTime>[day(1), day(5), day(8)],
      );
    });

    test('delete removes the request', () async {
      final int personId = await aPerson();
      final int productId = await aProduct();
      final int id = await aRequest(personId, productId);

      await repos.requests.delete(id);

      expect(await repos.requests.forPerson(personId), isEmpty);
    });
  });

  group('expenses', () {
    test('insert, read, update, and delete', () async {
      final int categoryId = await repos.expenses.ensureCategory('Petrol');
      final int id = await repos.expenses.insert(
        Expense(
          id: null,
          date: day(7),
          amountPaise: 30000,
          categoryId: categoryId,
          note: 'scooter',
        ),
      );

      Expense stored = (await repos.expenses.all()).single;
      expect(stored.id, id);
      expect(stored.categoryId, categoryId);
      expect(stored.isFromPersonalUse, isFalse);

      await repos.expenses.update(
        Expense(
          id: id,
          date: day(7),
          amountPaise: 35000,
          categoryId: categoryId,
          note: 'scooter, full tank',
        ),
      );
      stored = (await repos.expenses.all()).single;
      expect(stored.amountPaise, 35000);
      expect(stored.note, 'scooter, full tank');

      await repos.expenses.delete(id);
      expect(await repos.expenses.all(), isEmpty);
    });

    test('a month holds its own rows and no neighbours', () async {
      await repos.expenses.insert(
        Expense(id: null, date: DateTime(2026, 1, 31), amountPaise: 100),
      );
      await repos.expenses.insert(
        Expense(id: null, date: DateTime(2026, 2, 1), amountPaise: 200),
      );
      await repos.expenses.insert(
        Expense(id: null, date: DateTime(2026, 2, 28), amountPaise: 300),
      );
      await repos.expenses.insert(
        Expense(id: null, date: DateTime(2026, 3, 1), amountPaise: 400),
      );

      expect(
        (await repos.expenses.inMonth(2026, 2))
            .map((Expense each) => each.amountPaise)
            .toList(),
        <int>[300, 200],
      );
      expect(
        (await repos.expenses.inMonth(2026, 12))
            .map((Expense each) => each.amountPaise)
            .toList(),
        <int>[],
      );
    });

    test('December rolls into the next year rather than month thirteen',
        () async {
      await repos.expenses.insert(
        Expense(id: null, date: DateTime(2026, 12, 20), amountPaise: 500),
      );
      await repos.expenses.insert(
        Expense(id: null, date: DateTime(2027, 1, 2), amountPaise: 600),
      );

      expect(
        (await repos.expenses.inMonth(2026, 12))
            .map((Expense each) => each.amountPaise)
            .toList(),
        <int>[500],
      );
    });

    test('a month outside one to twelve is refused', () async {
      await expectLater(
        repos.expenses.inMonth(2026, 0),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repos.expenses.inMonth(2026, 13),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ensureCategory matches ignoring case rather than creating a twin',
        () async {
      final int first = await repos.expenses.ensureCategory('Petrol');

      expect(await repos.expenses.ensureCategory('petrol'), first);
      expect(await repos.expenses.ensureCategory('PETROL'), first);
      expect(await repos.expenses.ensureCategory('  Petrol  '), first);
      expect(await repos.expenses.categories(), hasLength(1));

      final int second = await repos.expenses.ensureCategory('Groceries');
      expect(second, isNot(first));
      expect(
        (await repos.expenses.categories())
            .map((ExpenseCategory each) => each.name)
            .toList(),
        <String>['Groceries', 'Petrol'],
      );
    });

    test('ensureCategory brings an archived match back', () async {
      final int id = await repos.expenses.ensureCategory('Petrol');
      await repos.expenses.setCategoryArchived(id, archived: true);
      expect(await repos.expenses.categories(), isEmpty);

      expect(await repos.expenses.ensureCategory('petrol'), id);
      expect(await repos.expenses.categories(), hasLength(1));
    });

    test('a category with no name is refused', () async {
      await expectLater(
        repos.expenses.ensureCategory('   '),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('archiving a category leaves every expense pointing at it', () async {
      final int categoryId = await repos.expenses.ensureCategory('Petrol');
      await repos.expenses.insert(
        Expense(
          id: null,
          date: day(7),
          amountPaise: 30000,
          categoryId: categoryId,
        ),
      );

      await repos.expenses.setCategoryArchived(categoryId, archived: true);

      expect(await repos.expenses.categories(), isEmpty);
      expect(
        await repos.expenses.categories(includeArchived: true),
        hasLength(1),
      );
      expect((await repos.expenses.all()).single.categoryId, categoryId);
    });
  });

  group('settings', () {
    test('write, read, overwrite, and read all', () async {
      expect(await repos.settings.read(SettingKeys.upiHandle), isNull);

      await repos.settings.write(SettingKeys.upiHandle, 'meera@upi');
      await repos.settings.write(SettingKeys.themeMode, 'dark');
      expect(await repos.settings.read(SettingKeys.upiHandle), 'meera@upi');

      await repos.settings.write(SettingKeys.upiHandle, 'meera2@upi');
      expect(await repos.settings.read(SettingKeys.upiHandle), 'meera2@upi');

      expect(await repos.settings.readAll(), <String, String>{
        SettingKeys.themeMode: 'dark',
        SettingKeys.upiHandle: 'meera2@upi',
      });
    });
  });

  group('the bundle', () {
    test('openRepositories hands back every repository, live', () async {
      expect(repos.products, isA<ProductRepository>());
      expect(repos.people, isA<PersonRepository>());
      expect(repos.deliveries, isA<DeliveryRepository>());
      expect(repos.money, isA<MoneyRepository>());
      expect(repos.stock, isA<StockRepository>());
      expect(repos.purchases, isA<PurchaseRepository>());
      expect(repos.requests, isA<RequestRepository>());
      expect(repos.expenses, isA<ExpenseRepository>());
      expect(repos.settings, isA<SettingsRepository>());

      await aProduct();
      expect(await repos.products.all(), hasLength(1));
    });
  });
}
