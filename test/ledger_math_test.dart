import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/helpers/ledger_math.dart';
import 'package:hisaab/models/models.dart';

import 'support/memex_ac.dart';

/// The money arithmetic, asserted with the worked figures from spec-27.
///
/// Every amount is an `int` count of paise, so 2,050 rupees is 205000. These
/// tests are the reason the app can claim a balance is right: nothing here
/// touches a database, so every case is cheap to state exactly.

// Deliveries and entries in these tests use fixed dates, never DateTime.now(),
// so a test can never pass or fail because of the clock.
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

const Person asha = Person(id: 7, name: 'Asha');

Map<int, Product> catalogue([
  List<Product> products = const <Product>[formula1, afresh],
]) => <int, Product>{for (final Product p in products) p.id!: p};

DeliveryItem line({
  int id = 1,
  int productId = 1,
  required int qty,
  required int unitPricePaise,
}) => DeliveryItem(
  id: id,
  deliveryId: null,
  productId: productId,
  qty: qty,
  unitPricePaise: unitPricePaise,
);

DeliveryWithItems handover({
  required int? id,
  required DateTime date,
  required List<DeliveryItem> items,
  String? forMember,
  int personId = 7,
}) => DeliveryWithItems(
  delivery: Delivery(
    id: id,
    personId: personId,
    date: date,
    forMember: forMember,
  ),
  items: items,
);

/// The direction each kind is recorded with in normal use. Cash lent is the
/// only one that leaves the owner's pocket.
MoneyDirection directionFor(MoneyKind kind) => switch (kind) {
  MoneyKind.cashLent => MoneyDirection.outgoing,
  MoneyKind.paymentReceived ||
  MoneyKind.cashBorrowed ||
  MoneyKind.repayment ||
  MoneyKind.adjustment ||
  MoneyKind.writeOff => MoneyDirection.incoming,
};

MoneyEntry money({
  int id = 1,
  required DateTime date,
  required int amountPaise,
  required MoneyKind kind,
  MoneyDirection? direction,
  int personId = 7,
  String? method,
  String? note,
}) => MoneyEntry(
  id: id,
  personId: personId,
  date: date,
  amountPaise: amountPaise,
  direction: direction ?? directionFor(kind),
  kind: kind,
  method: method,
  note: note,
);

/// 3 Sep 2026, two tubs at 2,050 each, so 4,100.
DeliveryWithItems get sep3Delivery => handover(
  id: 1,
  date: sep3,
  items: <DeliveryItem>[line(qty: 2, unitPricePaise: 205000)],
);

/// 7 Sep 2026, one pack at 950.
DeliveryWithItems get sep7Delivery => handover(
  id: 2,
  date: sep7,
  items: <DeliveryItem>[
    line(id: 2, productId: 2, qty: 1, unitPricePaise: 95000),
  ],
);

void main() {
  useAcEmission('test/ledger_math_test.dart');

  group('productBalance', () {
    acTest(
      'sums delivery lines and subtracts a payment that settles them',
      <String>['ac-8', 'ac-38'],
      () {
        final int balance = LedgerMath.productBalance(
          <DeliveryWithItems>[sep3Delivery, sep7Delivery],
          <MoneyEntry>[
            money(
              date: sep8,
              amountPaise: 450000,
              kind: MoneyKind.paymentReceived,
            ),
          ],
        );

        expect(balance, 55000);
      },
    );

    acTest(
      'returns the full total where nothing has been paid',
      <String>['ac-8'],
      () {
        expect(
          LedgerMath.productBalance(<DeliveryWithItems>[
            sep3Delivery,
            sep7Delivery,
          ], const <MoneyEntry>[]),
          505000,
        );
      },
    );

    acTest(
      'goes negative where a payment covers more than is owed',
      <String>['ac-8'],
      () {
        final int balance = LedgerMath.productBalance(
          <DeliveryWithItems>[sep7Delivery],
          <MoneyEntry>[
            money(
              date: sep8,
              amountPaise: 100000,
              kind: MoneyKind.paymentReceived,
            ),
          ],
        );

        expect(balance, -5000);
      },
    );

    acTest('ignores a cash loan and a repayment', <String>['ac-34'], () {
      final int balance = LedgerMath.productBalance(
        <DeliveryWithItems>[sep7Delivery],
        <MoneyEntry>[
          money(date: sep3, amountPaise: 500000, kind: MoneyKind.cashLent),
          money(
            id: 2,
            date: sep8,
            amountPaise: 95000,
            kind: MoneyKind.repayment,
          ),
        ],
      );

      expect(balance, 95000);
    });

    acTest('an adjustment reduces the product balance', <String>['ac-37'], () {
      final int balance = LedgerMath.productBalance(
        <DeliveryWithItems>[sep7Delivery],
        <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 90000,
            kind: MoneyKind.paymentReceived,
          ),
          money(
            id: 2,
            date: sep8,
            amountPaise: 5000,
            kind: MoneyKind.adjustment,
          ),
        ],
      );

      expect(balance, 0);
    });

    test('an adjustment recorded as outgoing adds to what is owed', () {
      // Direction carries the sign, so a round-off that went the other way,
      // where the person handed over less than the bill, reads as more owed
      // rather than less.
      final int balance = LedgerMath.productBalance(
        <DeliveryWithItems>[sep7Delivery],
        <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 5000,
            kind: MoneyKind.adjustment,
            direction: MoneyDirection.outgoing,
          ),
        ],
      );

      expect(balance, 100000);
    });

    test('a write off clears what is left', () {
      final int balance = LedgerMath.productBalance(
        <DeliveryWithItems>[sep7Delivery],
        <MoneyEntry>[
          money(date: sep9, amountPaise: 95000, kind: MoneyKind.writeOff),
        ],
      );

      expect(balance, 0);
    });

    test('two empty lists give zero', () {
      expect(
        LedgerMath.productBalance(
          const <DeliveryWithItems>[],
          const <MoneyEntry>[],
        ),
        0,
      );
    });

    test('a delivery with no items adds nothing', () {
      final int balance = LedgerMath.productBalance(<DeliveryWithItems>[
        handover(id: 3, date: sep3, items: const <DeliveryItem>[]),
        sep7Delivery,
      ], const <MoneyEntry>[]);

      expect(balance, 95000);
    });

    test('payments with no deliveries leave a credit', () {
      final int balance = LedgerMath.productBalance(
        const <DeliveryWithItems>[],
        <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 20000,
            kind: MoneyKind.paymentReceived,
          ),
        ],
      );

      expect(balance, -20000);
    });
  });

  group('cashBalance', () {
    test('cash lent increases what the person owes', () {
      expect(
        LedgerMath.cashBalance(<MoneyEntry>[
          money(date: sep3, amountPaise: 500000, kind: MoneyKind.cashLent),
        ]),
        500000,
      );
    });

    test('cash borrowed can push the balance negative', () {
      expect(
        LedgerMath.cashBalance(<MoneyEntry>[
          money(date: sep3, amountPaise: 500000, kind: MoneyKind.cashBorrowed),
        ]),
        -500000,
      );
    });

    test('a repayment reduces a loan', () {
      expect(
        LedgerMath.cashBalance(<MoneyEntry>[
          money(date: sep3, amountPaise: 500000, kind: MoneyKind.cashLent),
          money(
            id: 2,
            date: sep8,
            amountPaise: 200000,
            kind: MoneyKind.repayment,
          ),
        ]),
        300000,
      );
    });

    acTest(
      'a product payment never touches the cash pool',
      <String>['ac-34'],
      () {
        expect(
          LedgerMath.cashBalance(<MoneyEntry>[
            money(date: sep3, amountPaise: 500000, kind: MoneyKind.cashLent),
            money(
              id: 2,
              date: sep8,
              amountPaise: 95000,
              kind: MoneyKind.paymentReceived,
            ),
          ]),
          500000,
        );
      },
    );

    acTest(
      'an adjustment and a write off never touch the cash pool',
      <String>['ac-34'],
      () {
        expect(
          LedgerMath.cashBalance(<MoneyEntry>[
            money(date: sep8, amountPaise: 5000, kind: MoneyKind.adjustment),
            money(
              id: 2,
              date: sep9,
              amountPaise: 95000,
              kind: MoneyKind.writeOff,
            ),
          ]),
          0,
        );
      },
    );

    test('an empty list gives zero', () {
      expect(LedgerMath.cashBalance(const <MoneyEntry>[]), 0);
    });
  });

  group('two pools stay separate', () {
    final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
      sep7Delivery,
    ];
    final MoneyEntry loan = money(
      date: sep3,
      amountPaise: 500000,
      kind: MoneyKind.cashLent,
    );

    acTest(
      'a payment clears the product due and leaves the loan alone',
      <String>['ac-34'],
      () {
        final List<MoneyEntry> entries = <MoneyEntry>[
          loan,
          money(
            id: 2,
            date: sep8,
            amountPaise: 95000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        expect(LedgerMath.productBalance(deliveries, entries), 0);
        expect(LedgerMath.cashBalance(entries), 500000);
      },
    );

    acTest(
      'a repayment pays down the loan and leaves the product due alone',
      <String>['ac-34'],
      () {
        final List<MoneyEntry> entries = <MoneyEntry>[
          loan,
          money(
            id: 2,
            date: sep8,
            amountPaise: 95000,
            kind: MoneyKind.repayment,
          ),
        ];

        expect(LedgerMath.productBalance(deliveries, entries), 95000);
        expect(LedgerMath.cashBalance(entries), 405000);
      },
    );
  });

  group('allocate', () {
    acTest(
      'a partial payment spans two deliveries oldest first',
      <String>['ac-9', 'ac-10'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 450000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        final Map<int, SettlementState> states = LedgerMath.allocate(
          deliveries,
          entries,
        );

        expect(states[1], SettlementState.paid);
        expect(states[2], SettlementState.partlyPaid);
        expect(LedgerMath.coveredPaise(2, deliveries, entries), 40000);
        expect(LedgerMath.productBalance(deliveries, entries), 55000);
      },
    );

    acTest(
      'one payment covering several deliveries marks them all paid',
      <String>['ac-9'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 505000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        expect(LedgerMath.allocate(deliveries, entries), <int, SettlementState>{
          1: SettlementState.paid,
          2: SettlementState.paid,
        });
        expect(LedgerMath.productBalance(deliveries, entries), 0);
      },
    );

    acTest(
      'a payment larger than everything owed still marks each paid',
      <String>['ac-9'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 600000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        expect(LedgerMath.allocate(deliveries, entries), <int, SettlementState>{
          1: SettlementState.paid,
          2: SettlementState.paid,
        });
        expect(LedgerMath.productBalance(deliveries, entries), -95000);
      },
    );

    acTest(
      'several payments add up before they are allocated',
      <String>['ac-9'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 200000,
            kind: MoneyKind.paymentReceived,
          ),
          money(
            id: 2,
            date: sep9,
            amountPaise: 250000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        final Map<int, SettlementState> states = LedgerMath.allocate(
          deliveries,
          entries,
        );

        expect(states[1], SettlementState.paid);
        expect(states[2], SettlementState.partlyPaid);
        expect(LedgerMath.coveredPaise(2, deliveries, entries), 40000);
      },
    );

    acTest(
      'order in the input list does not change the outcome',
      <String>['ac-9'],
      () {
        final List<DeliveryWithItems> newestFirst = <DeliveryWithItems>[
          sep7Delivery,
          sep3Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 410000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        expect(
          LedgerMath.allocate(newestFirst, entries),
          <int, SettlementState>{
            1: SettlementState.paid,
            2: SettlementState.unpaid,
          },
        );
        expect(LedgerMath.coveredPaise(2, newestFirst, entries), 0);
      },
    );

    acTest('nothing paid reads unpaid', <String>['ac-9'], () {
      expect(
        LedgerMath.allocate(<DeliveryWithItems>[
          sep3Delivery,
        ], const <MoneyEntry>[]),
        <int, SettlementState>{1: SettlementState.unpaid},
      );
    });

    acTest(
      'a repayment does not settle a delivery',
      <String>['ac-9', 'ac-34'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(date: sep8, amountPaise: 95000, kind: MoneyKind.repayment),
        ];

        expect(LedgerMath.allocate(deliveries, entries), <int, SettlementState>{
          2: SettlementState.unpaid,
        });
        expect(LedgerMath.coveredPaise(2, deliveries, entries), 0);
      },
    );

    acTest(
      'a write off zeroes the balance without marking a delivery paid',
      <String>['ac-9'],
      () {
        // The person never paid, so the delivery still reads unpaid. The owner
        // simply stopped chasing it, and that shows as its own statement line.
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(date: sep9, amountPaise: 95000, kind: MoneyKind.writeOff),
        ];

        expect(LedgerMath.productBalance(deliveries, entries), 0);
        expect(LedgerMath.allocate(deliveries, entries), <int, SettlementState>{
          2: SettlementState.unpaid,
        });
      },
    );

    acTest(
      'a refund recorded as outgoing gives back what it took',
      <String>['ac-9'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 410000,
            kind: MoneyKind.paymentReceived,
          ),
          money(
            id: 2,
            date: sep9,
            amountPaise: 410000,
            kind: MoneyKind.paymentReceived,
            direction: MoneyDirection.outgoing,
          ),
        ];

        expect(LedgerMath.productBalance(deliveries, entries), 410000);
        expect(LedgerMath.allocate(deliveries, entries), <int, SettlementState>{
          1: SettlementState.unpaid,
        });
      },
    );

    test('a delivery with no items reads paid', () {
      expect(
        LedgerMath.allocate(<DeliveryWithItems>[
          handover(id: 5, date: sep3, items: const <DeliveryItem>[]),
        ], const <MoneyEntry>[]),
        <int, SettlementState>{5: SettlementState.paid},
      );
    });

    test('an unsaved delivery is left out of the result', () {
      final Map<int, SettlementState> states = LedgerMath.allocate(
        <DeliveryWithItems>[
          handover(
            id: null,
            date: sep3,
            items: <DeliveryItem>[line(qty: 1, unitPricePaise: 95000)],
          ),
          sep7Delivery,
        ],
        const <MoneyEntry>[],
      );

      expect(states, <int, SettlementState>{2: SettlementState.unpaid});
    });

    test('empty lists give an empty map rather than an error', () {
      expect(
        LedgerMath.allocate(const <DeliveryWithItems>[], const <MoneyEntry>[]),
        isEmpty,
      );
    });
  });

  group('coveredPaise', () {
    acTest('a paid delivery is covered in full', <String>['ac-10'], () {
      final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
        sep3Delivery,
        sep7Delivery,
      ];
      final List<MoneyEntry> entries = <MoneyEntry>[
        money(date: sep8, amountPaise: 450000, kind: MoneyKind.paymentReceived),
      ];

      expect(LedgerMath.coveredPaise(1, deliveries, entries), 410000);
    });

    test('an overpayment does not cover more than the delivery total', () {
      final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
        sep7Delivery,
      ];
      final List<MoneyEntry> entries = <MoneyEntry>[
        money(date: sep8, amountPaise: 400000, kind: MoneyKind.paymentReceived),
      ];

      expect(LedgerMath.coveredPaise(2, deliveries, entries), 95000);
    });

    test('an unknown delivery id is covered by nothing', () {
      expect(
        LedgerMath.coveredPaise(99, <DeliveryWithItems>[
          sep3Delivery,
        ], const <MoneyEntry>[]),
        0,
      );
    });
  });

  group('buildStatement', () {
    Statement statementOf({
      required List<DeliveryWithItems> deliveries,
      required List<MoneyEntry> entries,
      Map<int, Product>? products,
      Person person = asha,
    }) => LedgerMath.buildStatement(
      person: person,
      deliveries: deliveries,
      entries: entries,
      productsById: products ?? catalogue(),
      generatedAt: sep9,
    );

    acTest(
      'product lines and cash lines sit in separate groups',
      <String>['ac-18'],
      () {
        final Statement statement = statementOf(
          deliveries: <DeliveryWithItems>[sep3Delivery, sep7Delivery],
          entries: <MoneyEntry>[
            money(
              date: sep8,
              amountPaise: 450000,
              kind: MoneyKind.paymentReceived,
            ),
            money(
              id: 2,
              date: sep3,
              amountPaise: 500000,
              kind: MoneyKind.cashLent,
            ),
            money(
              id: 3,
              date: sep9,
              amountPaise: 100000,
              kind: MoneyKind.repayment,
            ),
          ],
        );

        expect(statement.products.lines.length, 3);
        expect(statement.cash.lines.length, 2);
        expect(statement.products.subtotalPaise, 55000);
        expect(statement.cash.subtotalPaise, 400000);
        expect(statement.netPaise, 455000);
        expect(statement.hasBothPools, isTrue);
        expect(statement.generatedAt, sep9);
        expect(statement.person.name, 'Asha');
      },
    );

    acTest(
      'each subtotal equals the balance function for that pool',
      <String>['ac-18'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 200000,
            kind: MoneyKind.paymentReceived,
          ),
          money(
            id: 2,
            date: sep8,
            amountPaise: 5000,
            kind: MoneyKind.adjustment,
          ),
          money(
            id: 3,
            date: sep3,
            amountPaise: 60000,
            kind: MoneyKind.cashBorrowed,
          ),
        ];

        final Statement statement = statementOf(
          deliveries: deliveries,
          entries: entries,
        );

        expect(
          statement.products.subtotalPaise,
          LedgerMath.productBalance(deliveries, entries),
        );
        expect(statement.cash.subtotalPaise, LedgerMath.cashBalance(entries));
        expect(
          statement.netPaise,
          statement.products.subtotalPaise + statement.cash.subtotalPaise,
        );
      },
    );

    test('lines run oldest first inside each group', () {
      final Statement statement = statementOf(
        deliveries: <DeliveryWithItems>[sep7Delivery, sep3Delivery],
        entries: <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 10000,
            kind: MoneyKind.paymentReceived,
          ),
          money(
            id: 2,
            date: sep9,
            amountPaise: 20000,
            kind: MoneyKind.paymentReceived,
          ),
        ],
      );

      expect(
        statement.products.lines.map((StatementLine l) => l.date).toList(),
        <DateTime>[sep3, sep7, sep8, sep9],
      );
    });

    test('a delivery line carries its snapshotted price in the detail', () {
      final Statement statement = statementOf(
        deliveries: <DeliveryWithItems>[sep3Delivery],
        entries: const <MoneyEntry>[],
      );

      final StatementLine delivery = statement.products.lines.single;
      expect(delivery.description, 'Formula 1');
      expect(delivery.detail, '2 tub at 2,050');
      expect(delivery.amountPaise, 410000);
      expect(delivery.settlement, SettlementState.unpaid);
    });

    acTest(
      'a household line surfaces the member it was for',
      <String>['ac-19'],
      () {
        final Statement statement = statementOf(
          person: const Person(
            id: 7,
            name: 'Sharma household',
            isHousehold: true,
          ),
          deliveries: <DeliveryWithItems>[
            handover(
              id: 4,
              date: sep3,
              forMember: 'Priya',
              items: <DeliveryItem>[line(qty: 1, unitPricePaise: 205000)],
            ),
          ],
          entries: const <MoneyEntry>[],
        );

        expect(statement.products.lines.single.forMember, 'Priya');
      },
    );

    test('a delivery with several products describes itself as a delivery', () {
      final Statement statement = statementOf(
        deliveries: <DeliveryWithItems>[
          handover(
            id: 6,
            date: sep3,
            items: <DeliveryItem>[
              line(qty: 2, unitPricePaise: 205000),
              line(id: 2, productId: 2, qty: 1, unitPricePaise: 95000),
            ],
          ),
        ],
        entries: const <MoneyEntry>[],
      );

      final StatementLine delivery = statement.products.lines.single;
      expect(delivery.description, 'Delivery');
      expect(delivery.detail, '2 tub Formula 1 at 2,050, 1 pack Afresh at 950');
      expect(delivery.amountPaise, 505000);
    });

    acTest(
      'a round-off is its own line rather than a smaller delivery',
      <String>['ac-37', 'ac-39'],
      () {
        final Statement statement = statementOf(
          deliveries: <DeliveryWithItems>[sep7Delivery],
          entries: <MoneyEntry>[
            money(
              date: sep8,
              amountPaise: 90000,
              kind: MoneyKind.paymentReceived,
            ),
            money(
              id: 2,
              date: sep9,
              amountPaise: 5000,
              kind: MoneyKind.adjustment,
            ),
          ],
        );

        expect(statement.products.lines.length, 3);
        expect(statement.products.lines.first.amountPaise, 95000);
        expect(
          statement.products.lines.last.description,
          'Round-off adjustment',
        );
        expect(statement.products.lines.last.amountPaise, -5000);
        expect(statement.products.subtotalPaise, 0);
        expect(statement.isSettled, isTrue);
      },
    );

    acTest('every money kind reads as itself', <String>['ac-18'], () {
      final Statement statement = statementOf(
        deliveries: const <DeliveryWithItems>[],
        entries: <MoneyEntry>[
          money(date: sep3, amountPaise: 1000, kind: MoneyKind.paymentReceived),
          money(id: 2, date: sep7, amountPaise: 2000, kind: MoneyKind.writeOff),
          money(id: 3, date: sep8, amountPaise: 3000, kind: MoneyKind.cashLent),
          money(
            id: 4,
            date: sep8,
            amountPaise: 4000,
            kind: MoneyKind.cashBorrowed,
          ),
          money(
            id: 5,
            date: sep9,
            amountPaise: 5000,
            kind: MoneyKind.repayment,
          ),
        ],
      );

      expect(
        statement.products.lines
            .map((StatementLine l) => l.description)
            .toList(),
        <String>['Payment received', 'Written off'],
      );
      expect(
        statement.cash.lines.map((StatementLine l) => l.description).toList(),
        <String>['Cash lent', 'Cash borrowed', 'Repayment'],
      );
      expect(
        statement.cash.lines.map((StatementLine l) => l.amountPaise).toList(),
        <int>[3000, -4000, -5000],
      );
    });

    test('the method and the note become the detail on a money line', () {
      final Statement statement = statementOf(
        deliveries: const <DeliveryWithItems>[],
        entries: <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 1000,
            kind: MoneyKind.paymentReceived,
            method: 'UPI',
            note: 'sent on the app',
          ),
        ],
      );

      expect(statement.products.lines.single.detail, 'UPI, sent on the app');
      expect(statement.products.lines.single.settlement, isNull);
    });

    acTest(
      'a person with no activity gets two empty groups and a zero net',
      <String>['ac-18'],
      () {
        final Statement statement = statementOf(
          deliveries: const <DeliveryWithItems>[],
          entries: const <MoneyEntry>[],
        );

        expect(statement.products.isEmpty, isTrue);
        expect(statement.cash.isEmpty, isTrue);
        expect(statement.hasBothPools, isFalse);
        expect(statement.netPaise, 0);
        expect(statement.isSettled, isTrue);
      },
    );

    test('a product missing from the catalogue still names its line', () {
      final Statement statement = statementOf(
        deliveries: <DeliveryWithItems>[
          handover(
            id: 8,
            date: sep3,
            items: <DeliveryItem>[
              line(productId: 42, qty: 1, unitPricePaise: 12300),
            ],
          ),
        ],
        entries: const <MoneyEntry>[],
        products: catalogue(const <Product>[]),
      );

      final StatementLine delivery = statement.products.lines.single;
      expect(delivery.description, 'Item 42');
      expect(delivery.amountPaise, 12300);
      expect(delivery.detail, '1 at 123');
    });

    acTest(
      'a price change does not rewrite a statement already built',
      <String>['ac-11', 'ac-12'],
      () {
        final List<DeliveryWithItems> deliveries = <DeliveryWithItems>[
          sep3Delivery,
          sep7Delivery,
        ];
        final List<MoneyEntry> entries = <MoneyEntry>[
          money(
            date: sep8,
            amountPaise: 450000,
            kind: MoneyKind.paymentReceived,
          ),
        ];

        final Statement before = statementOf(
          deliveries: deliveries,
          entries: entries,
        );

        // The owner raises the price after the handover. The delivery line
        // carries its own snapshotted price, so nothing already recorded moves.
        final Product raised = formula1.copyWith(currentPricePaise: 250000);
        final Statement after = LedgerMath.buildStatement(
          person: asha,
          deliveries: deliveries,
          entries: entries,
          productsById: catalogue(<Product>[raised, afresh]),
          generatedAt: sep9,
        );

        expect(after.products.subtotalPaise, before.products.subtotalPaise);
        expect(after.netPaise, before.netPaise);
        expect(
          after.products.lines.map((StatementLine l) => l.amountPaise).toList(),
          before.products.lines
              .map((StatementLine l) => l.amountPaise)
              .toList(),
        );
        expect(after.products.lines.first.detail, '2 tub at 2,050');
        expect(LedgerMath.productBalance(deliveries, entries), 55000);
      },
    );
  });

  group('balances', () {
    const Person bina = Person(id: 8, name: 'Bina');
    const Person chandra = Person(id: 9, name: 'Chandra');

    test('returns one balance per person, sorted by what they owe', () {
      final List<PersonBalance> result = LedgerMath.balances(
        people: const <Person>[chandra, asha, bina],
        deliveriesByPerson: <int, List<DeliveryWithItems>>{
          7: <DeliveryWithItems>[sep3Delivery],
          8: <DeliveryWithItems>[sep7Delivery],
        },
        entriesByPerson: <int, List<MoneyEntry>>{
          8: <MoneyEntry>[
            money(
              date: sep8,
              amountPaise: 200000,
              kind: MoneyKind.cashBorrowed,
              personId: 8,
            ),
          ],
        },
      );

      expect(result.length, 3);
      expect(result.map((PersonBalance b) => b.person.name).toList(), <String>[
        'Asha',
        'Chandra',
        'Bina',
      ]);
      expect(result.first.productDuePaise, 410000);
      expect(result.first.cashDuePaise, 0);
      expect(result.first.owes, isTrue);
      expect(result.last.netPaise, -105000);
      expect(result.last.isOwed, isTrue);
    });

    test('a person with no activity has a zero net and no last activity', () {
      final List<PersonBalance> result = LedgerMath.balances(
        people: const <Person>[chandra],
        deliveriesByPerson: const <int, List<DeliveryWithItems>>{},
        entriesByPerson: const <int, List<MoneyEntry>>{},
      );

      final PersonBalance quiet = result.single;
      expect(quiet.productDuePaise, 0);
      expect(quiet.cashDuePaise, 0);
      expect(quiet.netPaise, 0);
      expect(quiet.owes, isFalse);
      expect(quiet.isOwed, isFalse);
      expect(quiet.lastActivity, isNull);
    });

    test('last activity is the most recent delivery or money entry', () {
      final List<PersonBalance> result = LedgerMath.balances(
        people: const <Person>[asha],
        deliveriesByPerson: <int, List<DeliveryWithItems>>{
          7: <DeliveryWithItems>[sep7Delivery, sep3Delivery],
        },
        entriesByPerson: <int, List<MoneyEntry>>{
          7: <MoneyEntry>[
            money(
              date: sep8,
              amountPaise: 1000,
              kind: MoneyKind.paymentReceived,
            ),
          ],
        },
      );

      expect(result.single.lastActivity, sep8);
    });

    test('last activity ignores a money entry older than the delivery', () {
      final List<PersonBalance> result = LedgerMath.balances(
        people: const <Person>[asha],
        deliveriesByPerson: <int, List<DeliveryWithItems>>{
          7: <DeliveryWithItems>[sep7Delivery],
        },
        entriesByPerson: <int, List<MoneyEntry>>{
          7: <MoneyEntry>[
            money(
              date: sep3,
              amountPaise: 1000,
              kind: MoneyKind.paymentReceived,
            ),
          ],
        },
      );

      expect(result.single.lastActivity, sep7);
    });

    test('no people gives an empty list', () {
      expect(
        LedgerMath.balances(
          people: const <Person>[],
          deliveriesByPerson: const <int, List<DeliveryWithItems>>{},
          entriesByPerson: const <int, List<MoneyEntry>>{},
        ),
        isEmpty,
      );
    });
  });
}
