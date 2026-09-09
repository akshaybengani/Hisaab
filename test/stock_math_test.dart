import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/helpers/stock_math.dart';
import 'package:hisaab/models/models.dart';

import 'support/memex_ac.dart';

/// The stock arithmetic. On hand is always derived from purchases,
/// deliveries, and adjustments, so every figure here can be traced to rows.

final DateTime sep3 = DateTime(2026, 9, 3);
final DateTime sep7 = DateTime(2026, 9, 7);
final DateTime sep8 = DateTime(2026, 9, 8);
final DateTime sep9 = DateTime(2026, 9, 9);

const Product formula1 = Product(
  id: 1,
  name: 'Formula 1',
  unitLabel: 'tub',
  currentPricePaise: 205000,
);

const Product afresh = Product(
  id: 2,
  name: 'Afresh',
  unitLabel: 'pack',
  currentPricePaise: 95000,
);

PurchaseItem bought({
  int id = 1,
  int? purchaseId = 1,
  int productId = 1,
  required int qty,
  int unitCostPaise = 180000,
}) => PurchaseItem(
  id: id,
  purchaseId: purchaseId,
  productId: productId,
  qty: qty,
  unitCostPaise: unitCostPaise,
);

DeliveryItem handedOut({
  int id = 1,
  int? deliveryId = 1,
  int productId = 1,
  required int qty,
  int unitPricePaise = 205000,
}) => DeliveryItem(
  id: id,
  deliveryId: deliveryId,
  productId: productId,
  qty: qty,
  unitPricePaise: unitPricePaise,
);

StockAdjustment adjusted({
  int id = 1,
  int productId = 1,
  required int qtyDelta,
  StockReason reason = StockReason.manual,
  required DateTime date,
  String? note,
}) => StockAdjustment(
  id: id,
  productId: productId,
  qtyDelta: qtyDelta,
  reason: reason,
  date: date,
  note: note,
);

StockLevel levelOf({
  Product product = formula1,
  List<PurchaseItem> purchases = const <PurchaseItem>[],
  List<DeliveryItem> deliveries = const <DeliveryItem>[],
  List<StockAdjustment> adjustments = const <StockAdjustment>[],
}) => StockMath.level(
  product: product,
  purchaseItems: purchases,
  deliveryItems: deliveries,
  adjustments: adjustments,
);

ProductRequest asked({
  int id = 1,
  int personId = 7,
  int productId = 1,
  required int qty,
  RequestStatus status = RequestStatus.pending,
  DateTime? createdAt,
}) => ProductRequest(
  id: id,
  personId: personId,
  productId: productId,
  qty: qty,
  status: status,
  createdAt: createdAt ?? sep3,
);

void main() {
  useAcEmission('test/stock_math_test.dart');

  group('level', () {
    acTest(
      'on hand comes from purchases alone where nothing has moved out',
      <String>['ac-13'],
      () {
        final StockLevel level = levelOf(
          purchases: <PurchaseItem>[
            bought(qty: 6),
            bought(id: 2, purchaseId: 2, qty: 4),
          ],
        );

        expect(level.purchased, 10);
        expect(level.delivered, 0);
        expect(level.adjusted, 0);
        expect(level.onHand, 10);
        expect(level.isOut, isFalse);
        expect(level.valuePaise, 2050000);
      },
    );

    acTest('deliveries come off the purchased figure', <String>['ac-13'], () {
      final StockLevel level = levelOf(
        purchases: <PurchaseItem>[bought(qty: 10)],
        deliveries: <DeliveryItem>[
          handedOut(qty: 2),
          handedOut(id: 2, deliveryId: 2, qty: 3),
        ],
      );

      expect(level.delivered, 5);
      expect(level.onHand, 5);
    });

    acTest(
      'every adjustment reason moves on hand by its own delta',
      <String>['ac-13'],
      () {
        for (final StockReason reason in StockReason.values) {
          final StockLevel level = levelOf(
            purchases: <PurchaseItem>[bought(qty: 10)],
            adjustments: <StockAdjustment>[
              adjusted(qtyDelta: -1, reason: reason, date: sep8),
            ],
          );

          expect(level.adjusted, -1, reason: reason.value);
          expect(level.onHand, 9, reason: reason.value);
        }
      },
    );

    acTest('adjustments in both directions net out', <String>['ac-13'], () {
      final StockLevel level = levelOf(
        purchases: <PurchaseItem>[bought(qty: 10)],
        deliveries: <DeliveryItem>[handedOut(qty: 4)],
        adjustments: <StockAdjustment>[
          adjusted(qtyDelta: -1, reason: StockReason.damaged, date: sep7),
          adjusted(id: 2, qtyDelta: -1, reason: StockReason.gifted, date: sep8),
          adjusted(id: 3, qtyDelta: 2, reason: StockReason.manual, date: sep9),
        ],
      );

      expect(level.adjusted, 0);
      expect(level.onHand, 6);
    });

    acTest(
      'a negative on hand is kept, because it means a row is missing',
      <String>['ac-13'],
      () {
        final StockLevel level = levelOf(
          purchases: <PurchaseItem>[bought(qty: 1)],
          deliveries: <DeliveryItem>[handedOut(qty: 3)],
        );

        expect(level.onHand, -2);
        expect(level.isOut, isTrue);
        expect(level.valuePaise, -410000);
      },
    );

    test('empty lists give a zero level rather than an error', () {
      final StockLevel level = levelOf();

      expect(level.purchased, 0);
      expect(level.delivered, 0);
      expect(level.adjusted, 0);
      expect(level.onHand, 0);
      expect(level.isOut, isTrue);
      expect(level.valuePaise, 0);
      expect(level.product.name, 'Formula 1');
    });

    acTest('rows for another product are left out', <String>['ac-13'], () {
      final StockLevel level = levelOf(
        purchases: <PurchaseItem>[
          bought(qty: 10),
          bought(id: 2, purchaseId: 2, productId: 2, qty: 5),
        ],
        deliveries: <DeliveryItem>[
          handedOut(qty: 1),
          handedOut(id: 2, deliveryId: 2, productId: 2, qty: 4),
        ],
        adjustments: <StockAdjustment>[
          adjusted(qtyDelta: -1, date: sep8),
          adjusted(id: 2, productId: 2, qtyDelta: -2, date: sep8),
        ],
      );

      expect(level.purchased, 10);
      expect(level.delivered, 1);
      expect(level.adjusted, -1);
      expect(level.onHand, 8);
    });
  });

  group('recountDelta', () {
    acTest(
      'a count of 5 against 7 on hand stores minus 2',
      <String>['ac-15'],
      () {
        expect(StockMath.recountDelta(currentOnHand: 7, countedOnHand: 5), -2);
      },
    );

    acTest(
      'a count above the derived figure stores a positive delta',
      <String>['ac-15'],
      () {
        expect(StockMath.recountDelta(currentOnHand: 5, countedOnHand: 7), 2);
      },
    );

    acTest('a count that agrees stores nothing', <String>['ac-15'], () {
      expect(StockMath.recountDelta(currentOnHand: 5, countedOnHand: 5), 0);
    });

    acTest(
      'the delta lands on hand exactly on the counted figure',
      <String>['ac-15'],
      () {
        final StockLevel before = levelOf(
          purchases: <PurchaseItem>[bought(qty: 7)],
        );
        final int delta = StockMath.recountDelta(
          currentOnHand: before.onHand,
          countedOnHand: 5,
        );
        final StockLevel after = levelOf(
          purchases: <PurchaseItem>[bought(qty: 7)],
          adjustments: <StockAdjustment>[
            adjusted(qtyDelta: delta, reason: StockReason.recount, date: sep9),
          ],
        );

        expect(delta, -2);
        expect(after.onHand, 5);
        expect(after.purchased, 7);
      },
    );

    acTest(
      'a count against a negative on hand still reconciles',
      <String>['ac-15'],
      () {
        expect(StockMath.recountDelta(currentOnHand: -2, countedOnHand: 3), 5);
      },
    );
  });

  group('history', () {
    test('movements run oldest first with the running figure after each', () {
      final List<StockMovement> movements = StockMath.history(
        purchaseItems: <PurchaseItem>[bought(qty: 10)],
        deliveryItems: <DeliveryItem>[handedOut(qty: 2)],
        adjustments: <StockAdjustment>[
          adjusted(
            qtyDelta: -1,
            reason: StockReason.damaged,
            date: sep8,
            note: 'seal broken',
          ),
          adjusted(
            id: 2,
            qtyDelta: -2,
            reason: StockReason.recount,
            date: sep9,
          ),
        ],
        purchaseDates: <int, DateTime>{1: sep3},
        deliveryDates: <int, DateTime>{1: sep7},
      );

      expect(movements.map((StockMovement m) => m.date).toList(), <DateTime>[
        sep3,
        sep7,
        sep8,
        sep9,
      ]);
      expect(movements.map((StockMovement m) => m.label).toList(), <String>[
        'Purchased',
        'Delivered',
        'Damaged',
        'Recount',
      ]);
      expect(movements.map((StockMovement m) => m.qtyDelta).toList(), <int>[
        10,
        -2,
        -1,
        -2,
      ]);
      expect(
        movements.map((StockMovement m) => m.runningOnHand).toList(),
        <int>[10, 8, 7, 5],
      );
      expect(movements[2].detail, 'seal broken');
    });

    test('the running figure ends on the level for the same rows', () {
      final List<PurchaseItem> purchases = <PurchaseItem>[
        bought(qty: 10),
        bought(id: 2, purchaseId: 2, qty: 5),
      ];
      final List<DeliveryItem> deliveries = <DeliveryItem>[handedOut(qty: 4)];
      final List<StockAdjustment> adjustments = <StockAdjustment>[
        adjusted(qtyDelta: -3, reason: StockReason.personalUse, date: sep9),
      ];

      final List<StockMovement> movements = StockMath.history(
        purchaseItems: purchases,
        deliveryItems: deliveries,
        adjustments: adjustments,
        purchaseDates: <int, DateTime>{1: sep3, 2: sep8},
        deliveryDates: <int, DateTime>{1: sep7},
      );

      expect(
        movements.last.runningOnHand,
        levelOf(
          purchases: purchases,
          deliveries: deliveries,
          adjustments: adjustments,
        ).onHand,
      );
      expect(movements.last.label, 'Personal use');
    });

    test('stock arriving on a day is counted before stock leaving it', () {
      final List<StockMovement> movements = StockMath.history(
        purchaseItems: <PurchaseItem>[bought(qty: 3)],
        deliveryItems: <DeliveryItem>[handedOut(qty: 3)],
        adjustments: const <StockAdjustment>[],
        purchaseDates: <int, DateTime>{1: sep3},
        deliveryDates: <int, DateTime>{1: sep3},
      );

      expect(movements.map((StockMovement m) => m.label).toList(), <String>[
        'Purchased',
        'Delivered',
      ]);
      expect(
        movements.map((StockMovement m) => m.runningOnHand).toList(),
        <int>[3, 0],
      );
    });

    test('a movement whose date is unknown is left out', () {
      final List<StockMovement> movements = StockMath.history(
        purchaseItems: <PurchaseItem>[
          bought(qty: 10),
          bought(id: 2, purchaseId: 99, qty: 4),
          bought(id: 3, purchaseId: null, qty: 4),
        ],
        deliveryItems: <DeliveryItem>[
          handedOut(qty: 2),
          handedOut(id: 2, deliveryId: 98, qty: 1),
        ],
        adjustments: const <StockAdjustment>[],
        purchaseDates: <int, DateTime>{1: sep3},
        deliveryDates: <int, DateTime>{1: sep7},
      );

      expect(movements.length, 2);
      expect(movements.last.runningOnHand, 8);
    });

    test('no rows give no movements', () {
      expect(
        StockMath.history(
          purchaseItems: const <PurchaseItem>[],
          deliveryItems: const <DeliveryItem>[],
          adjustments: const <StockAdjustment>[],
          purchaseDates: const <int, DateTime>{},
          deliveryDates: const <int, DateTime>{},
        ),
        isEmpty,
      );
    });

    test('a history that goes negative is not clamped', () {
      final List<StockMovement> movements = StockMath.history(
        purchaseItems: <PurchaseItem>[bought(qty: 1)],
        deliveryItems: <DeliveryItem>[handedOut(qty: 3)],
        adjustments: const <StockAdjustment>[],
        purchaseDates: <int, DateTime>{1: sep3},
        deliveryDates: <int, DateTime>{1: sep7},
      );

      expect(movements.last.runningOnHand, -2);
    });
  });

  group('shoppingList', () {
    acTest(
      'three people asking for one product collapse into one line',
      <String>['ac-27'],
      () {
        final List<ShoppingListLine> lines = StockMath.shoppingList(
          pending: <ProductRequest>[
            asked(qty: 2),
            asked(id: 2, personId: 8, qty: 1),
            asked(id: 3, personId: 9, qty: 3),
          ],
          productsById: <int, Product>{1: formula1},
        );

        final ShoppingListLine line = lines.single;
        expect(line.productId, 1);
        expect(line.productName, 'Formula 1');
        expect(line.unitLabel, 'tub');
        expect(line.qty, 6);
        expect(line.requestCount, 3);
      },
    );

    acTest(
      'two requests from one person count as one person asking',
      <String>['ac-27'],
      () {
        final List<ShoppingListLine> lines = StockMath.shoppingList(
          pending: <ProductRequest>[asked(qty: 2), asked(id: 2, qty: 1)],
          productsById: <int, Product>{1: formula1},
        );

        expect(lines.single.qty, 3);
        expect(lines.single.requestCount, 1);
      },
    );

    acTest('one line per product, ordered by name', <String>['ac-27'], () {
      final List<ShoppingListLine> lines = StockMath.shoppingList(
        pending: <ProductRequest>[
          asked(qty: 2),
          asked(id: 2, personId: 8, productId: 2, qty: 5),
        ],
        productsById: <int, Product>{1: formula1, 2: afresh},
      );

      expect(
        lines.map((ShoppingListLine l) => l.productName).toList(),
        <String>['Afresh', 'Formula 1'],
      );
      expect(lines.map((ShoppingListLine l) => l.qty).toList(), <int>[5, 2]);
    });

    acTest(
      'anything past the pending stage is left off the list',
      <String>['ac-27'],
      () {
        final List<ShoppingListLine> lines = StockMath.shoppingList(
          pending: <ProductRequest>[
            asked(qty: 2),
            asked(id: 2, personId: 8, qty: 4, status: RequestStatus.ordered),
            asked(id: 3, personId: 9, qty: 8, status: RequestStatus.delivered),
            asked(id: 4, personId: 9, qty: 16, status: RequestStatus.cancelled),
          ],
          productsById: <int, Product>{1: formula1},
        );

        expect(lines.single.qty, 2);
        expect(lines.single.requestCount, 1);
      },
    );

    test('a request for a product that is gone is left off the list', () {
      final List<ShoppingListLine> lines = StockMath.shoppingList(
        pending: <ProductRequest>[
          asked(qty: 2),
          asked(id: 2, personId: 8, productId: 42, qty: 4),
        ],
        productsById: <int, Product>{1: formula1},
      );

      expect(lines.single.productId, 1);
    });

    test('no pending requests give an empty list', () {
      expect(
        StockMath.shoppingList(
          pending: const <ProductRequest>[],
          productsById: const <int, Product>{},
        ),
        isEmpty,
      );
    });
  });
}
