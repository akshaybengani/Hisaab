import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/repositories/contracts.dart';
import 'package:hisaab/repositories/factory.dart';
import 'package:hisaab/repositories/sqflite_repositories.dart';
import 'package:hisaab/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/memex_ac.dart';

/// The clauses the rest of the suite asserts around rather than at.
///
/// Tagging the existing tests surfaced a set of acceptance criteria whose
/// wording had a second half nothing checked: "and updates no other table",
/// "and moves no balance", "never written automatically". Those halves are
/// where a regression would actually hide, because the happy path keeps
/// passing while the side effect goes wrong.
void main() {
  useAcEmission('test/invariants_test.dart');

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('the price snapshot is a property of the type', () {
    const Product product = Product(
      id: 7,
      name: 'Formula 1',
      unitLabel: 'tub',
      currentPricePaise: 205000,
    );

    /// Verifies ac-11.
    acTest(
      'a line built by snapshot copies the price at that moment',
      <String>['ac-11'],
      () {
        final DeliveryItem line = DeliveryItem.snapshot(
          product: product,
          qty: 2,
        );

        expect(line.unitPricePaise, 205000);
        expect(line.productId, 7);
        expect(line.totalPaise, 410000);
      },
    );

    /// Verifies ac-11 and ac-12.
    acTest(
      'the line keeps its price after the product is repriced',
      <String>['ac-11', 'ac-12'],
      () {
        final DeliveryItem line = DeliveryItem.snapshot(
          product: product,
          qty: 2,
        );
        final Product repriced = product.copyWith(currentPricePaise: 215000);

        expect(repriced.currentPricePaise, 215000);
        expect(
          line.unitPricePaise,
          205000,
          reason: 'the line is a fact, not a view',
        );
        expect(line.totalPaise, 410000);
      },
    );

    acTest(
      'an unsaved product cannot become a delivery line',
      <String>['ac-11'],
      () {
        const Product unsaved = Product(
          id: null,
          name: 'Afresh',
          unitLabel: 'jar',
          currentPricePaise: 95000,
        );

        expect(
          () => DeliveryItem.snapshot(product: unsaved, qty: 1),
          throwsArgumentError,
        );
      },
    );
  });

  group('a payment is only ambiguous when both pools are owed', () {
    Statement statementWith({
      required int productsPaise,
      required int cashPaise,
      required bool cashHasLines,
    }) {
      final DateTime sep9 = DateTime(2026, 9, 9);
      return Statement(
        person: const Person(id: 1, name: 'Asha'),
        products: StatementGroup(
          title: 'Product dues',
          lines: <StatementLine>[
            StatementLine(
              date: sep9,
              description: 'Delivery',
              amountPaise: productsPaise,
            ),
          ],
        ),
        cash: StatementGroup(
          title: 'Cash loans',
          lines: <StatementLine>[
            if (cashHasLines)
              StatementLine(
                date: sep9,
                description: 'Cash lent',
                amountPaise: cashPaise,
              ),
          ],
        ),
        generatedAt: sep9,
      );
    }

    /// Verifies ac-35.
    acTest(
      'both pools owed, so the payment needs a pool',
      <String>['ac-35'],
      () {
        final Statement statement = statementWith(
          productsPaise: 95000,
          cashPaise: 500000,
          cashHasLines: true,
        );

        expect(statement.hasBothPools, isTrue);
      },
    );

    /// Verifies ac-35. This is the case the first implementation got wrong:
    /// a loan repaid in full still leaves cash lines behind, and asking which
    /// pool a payment settles would be a question with one real answer.
    acTest(
      'a loan repaid in full no longer needs a pool',
      <String>['ac-35'],
      () {
        final Statement statement = statementWith(
          productsPaise: 95000,
          cashPaise: 0,
          cashHasLines: true,
        );

        expect(
          statement.cash.isEmpty,
          isFalse,
          reason: 'the history is still there',
        );
        expect(statement.cash.subtotalPaise, 0);
        expect(statement.hasBothPools, isFalse);
        expect(
          statement.hasBothGroups,
          isTrue,
          reason: 'both sections still render',
        );
      },
    );

    acTest(
      'nothing owed on products means no pool question',
      <String>['ac-35'],
      () {
        final Statement statement = statementWith(
          productsPaise: 0,
          cashPaise: 500000,
          cashHasLines: true,
        );

        expect(statement.hasBothPools, isFalse);
      },
    );
  });

  group('side effects that must not happen', () {
    late Directory home;
    late SqfliteRepositories repos;

    setUp(() async {
      home = await Directory.systemTemp.createTemp('hisaab-invariants-');
      final Repositories opened = await openRepositories(
        path: '${home.path}/book.db',
      );
      repos = opened as SqfliteRepositories;
    });

    tearDown(() async {
      await repos.close();
      await home.delete(recursive: true);
    });

    Future<int> aProduct() => repos.products.insert(
      const Product(
        id: null,
        name: 'Formula 1',
        unitLabel: 'tub',
        currentPricePaise: 205000,
      ),
    );

    Future<int> rowsIn(String table) async {
      final List<Map<String, Object?>> result = await repos.database.rawQuery(
        'SELECT COUNT(*) AS n FROM $table',
      );
      return result.first['n']! as int;
    }

    /// Verifies ac-16. The expense linkage was already covered; this asserts
    /// the half that was not, which is that consuming a unit yourself is an
    /// expense and never a receivable.
    acTest(
      'personal use moves no money against any person',
      <String>['ac-16'],
      () async {
        final int productId = await aProduct();
        final DateTime today = DateTime(2026, 9, 9);

        await repos.stock.insertWithExpense(
          StockAdjustment(
            id: null,
            productId: productId,
            qtyDelta: -1,
            reason: StockReason.personalUse,
            date: today,
          ),
          Expense(id: null, date: today, amountPaise: 205000),
        );

        expect(await rowsIn('expenses'), 1);
        expect(await rowsIn('stock_adjustments'), 1);
        expect(
          await rowsIn('money_entries'),
          0,
          reason: 'nobody owes anything',
        );
        expect(await rowsIn('deliveries'), 0);
      },
    );

    /// Verifies ac-14. The stepper writing one row was covered; this asserts
    /// that it leaves every other table alone.
    acTest(
      'a stepper tap touches only stock_adjustments',
      <String>['ac-14'],
      () async {
        final int productId = await aProduct();
        final Map<String, int> before = <String, int>{
          for (final String table in DatabaseService.tableNames)
            table: await rowsIn(table),
        };

        await repos.stock.insert(
          StockAdjustment(
            id: null,
            productId: productId,
            qtyDelta: 1,
            reason: StockReason.manual,
            date: DateTime(2026, 9, 9),
          ),
        );

        for (final String table in DatabaseService.tableNames) {
          final int expected = table == 'stock_adjustments'
              ? before[table]! + 1
              : before[table]!;
          expect(await rowsIn(table), expected, reason: 'row count of $table');
        }
      },
    );

    /// Verifies ac-24. A purchase that cost more than its lines is a gap the
    /// user is OFFERED as an expense. Writing it for them would put money in
    /// the books nobody chose to record.
    acTest(
      'a purchase gap is never written to expenses on its own',
      <String>['ac-24'],
      () async {
        final int productId = await aProduct();

        final int purchaseId = await repos.purchases.insert(
          Purchase(
            id: null,
            date: DateTime(2026, 9, 9),
            totalPaidPaise: 430000,
            vendor: 'Distributor',
          ),
          <PurchaseItem>[
            PurchaseItem(
              id: null,
              purchaseId: null,
              productId: productId,
              qty: 2,
              unitCostPaise: 205000,
            ),
          ],
        );

        final PurchaseWithItems? saved = await repos.purchases.byId(purchaseId);
        expect(saved, isNotNull);
        expect(saved!.lineTotalPaise, 410000);
        expect(
          saved.absorbedPaise,
          20000,
          reason: 'shipping, named not hidden',
        );
        expect(
          await rowsIn('expenses'),
          0,
          reason: 'the user has not chosen yet',
        );
      },
    );

    /// Verifies ac-24. The other direction of the same gap, which is a saving
    /// rather than a cost and must never be recorded as an expense at all.
    acTest(
      'a discount received reads as a negative gap',
      <String>['ac-24'],
      () async {
        final int productId = await aProduct();

        final int purchaseId = await repos.purchases.insert(
          Purchase(
            id: null,
            date: DateTime(2026, 9, 9),
            totalPaidPaise: 405000,
          ),
          <PurchaseItem>[
            PurchaseItem(
              id: null,
              purchaseId: null,
              productId: productId,
              qty: 2,
              unitCostPaise: 205000,
            ),
          ],
        );

        final PurchaseWithItems saved = (await repos.purchases.byId(
          purchaseId,
        ))!;
        expect(
          saved.absorbedPaise,
          -5000,
          reason: 'a 50 rupee discount received',
        );
        expect(await rowsIn('expenses'), 0);
      },
    );

    /// Verifies ac-8 and ac-9. Both derived figures stay derived: there is no
    /// table or column anywhere that could hold a balance or an allocation.
    acTest(
      'the schema stores no balance and no allocation',
      <String>['ac-8', 'ac-9'],
      () async {
        final List<Map<String, Object?>> tables = await repos.database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        );
        final List<String> names = tables
            .map(
              (Map<String, Object?> row) =>
                  (row['name']! as String).toLowerCase(),
            )
            .toList();

        for (final String forbidden in <String>[
          'allocations',
          'balances',
          'settlements',
          'groups',
          'memberships',
        ]) {
          expect(names, isNot(contains(forbidden)));
        }

        for (final String table in DatabaseService.tableNames) {
          final List<Map<String, Object?>> columns = await repos.database
              .rawQuery('PRAGMA table_info($table)');
          final List<String> columnNames = columns
              .map(
                (Map<String, Object?> row) =>
                    (row['name']! as String).toLowerCase(),
              )
              .toList();
          for (final String forbidden in <String>[
            'balance',
            'balance_paise',
            'on_hand',
            'qty_on_hand',
            'settlement_state',
          ]) {
            expect(
              columnNames,
              isNot(contains(forbidden)),
              reason: '$table.$forbidden',
            );
          }
        }
      },
    );
  });
}
