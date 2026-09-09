import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The ledger table as a version 1 install has it. Typed out here rather than
/// read from the service, so a change to the shipped DDL shows up as a failing
/// comparison instead of quietly agreeing with itself.
const String _v1Ledger = '''
CREATE TABLE schema_migrations (
  version INTEGER PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
)''';

/// A step that only this test ships. It exists so the replay machinery is
/// exercised for real, adding both a table and a column, without the app
/// having to carry a migration it does not need.
const Migration _step2 = Migration(
  version: 2,
  name: 'test only, adds one table and one column',
  statements: <String>[
    'ALTER TABLE products ADD COLUMN shelf TEXT',
    '''
CREATE TABLE product_notes (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  body TEXT NOT NULL
)''',
    'CREATE INDEX idx_product_notes_product ON product_notes (product_id)',
  ],
);

final List<Migration> _throughStep2 = <Migration>[
  schemaMigrations.first,
  _step2,
];

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory home;
  late List<Database> open;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hisaab-migration-');
    open = <Database>[];
  });

  tearDown(() async {
    for (final Database db in open) {
      await db.close();
    }
    await home.delete(recursive: true);
  });

  String at(String name) => '${home.path}/$name.db';

  Future<Database> track(Future<Database> opening) async {
    final Database db = await opening;
    open.add(db);
    return db;
  }

  /// Every table in the file, with its column names.
  Future<Map<String, Set<String>>> columnsByTable(Database db) async {
    final List<Map<String, Object?>> tables = await db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: "type = 'table' AND name NOT LIKE 'sqlite_%'",
      orderBy: 'name ASC',
    );
    final Map<String, Set<String>> shape = <String, Set<String>>{};
    for (final Map<String, Object?> table in tables) {
      final String name = table['name']! as String;
      final List<Map<String, Object?>> info = await db.rawQuery(
        'PRAGMA table_info($name)',
      );
      shape[name] = info
          .map((Map<String, Object?> column) => column['name']! as String)
          .toSet();
    }
    return shape;
  }

  Future<Set<String>> indexNames(Database db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'sqlite_master',
      columns: <String>['name'],
      where: "type = 'index' AND name NOT LIKE 'sqlite_%'",
      orderBy: 'name ASC',
    );
    return rows
        .map((Map<String, Object?> row) => row['name']! as String)
        .toSet();
  }

  /// Builds a version 1 file the way a phone that installed version 1 has it:
  /// the committed baseline statements, the ledger with one row in it, and a
  /// user version of 1 so the next open takes the upgrade path.
  Future<void> handBuildVersion1(String path) async {
    final Database db = await databaseFactory.openDatabase(path);
    await db.execute(_v1Ledger);
    for (final String statement in schemaMigrations.first.statements) {
      await db.execute(statement);
    }
    await db.insert('schema_migrations', <String, Object?>{
      'version': 1,
      'name': 'baseline',
      'applied_at': '2026-01-01T00:00:00.000',
    });
    await db.execute('PRAGMA user_version = 1');
    await db.close();
  }

  group('schema', () {
    test('a fresh install creates every table the schema names', () async {
      final Database db = await track(DatabaseService.open(path: at('fresh')));
      final Map<String, Set<String>> shape = await columnsByTable(db);

      expect(shape.keys.toList()..sort(), DatabaseService.tableNames);
      expect(shape.length, 14);
    });

    test('money columns are integers and dates are text', () async {
      final Database db = await track(DatabaseService.open(path: at('types')));
      final List<Map<String, Object?>> info = await db.rawQuery(
        'PRAGMA table_info(delivery_items)',
      );
      final Map<String, Object?> types = <String, Object?>{
        for (final Map<String, Object?> column in info)
          column['name']! as String: column['type'],
      };
      expect(types['unit_price_paise'], 'INTEGER');

      final List<Map<String, Object?>> deliveries = await db.rawQuery(
        'PRAGMA table_info(deliveries)',
      );
      final Map<String, Object?> deliveryTypes = <String, Object?>{
        for (final Map<String, Object?> column in deliveries)
          column['name']! as String: column['type'],
      };
      expect(deliveryTypes['date'], 'TEXT');
    });

    test('there is no stored balance and no stored quantity', () async {
      final Database db = await track(
        DatabaseService.open(path: at('derived')),
      );
      final Map<String, Set<String>> shape = await columnsByTable(db);

      expect(shape['people'], isNot(contains('balance')));
      expect(shape['people'], isNot(contains('due_paise')));
      expect(shape['products'], isNot(contains('qty')));
      expect(shape['products'], isNot(contains('on_hand')));
      expect(shape['products'], isNot(contains('stock')));
    });

    test('every column each read filters on is indexed', () async {
      final Database db = await track(
        DatabaseService.open(path: at('indexes')),
      );
      expect(await indexNames(db), <String>{
        'idx_deliveries_person',
        'idx_delivery_items_delivery',
        'idx_expense_categories_name',
        'idx_expenses_date',
        'idx_money_entries_person',
        'idx_purchase_items_purchase',
        'idx_requests_status',
        'idx_stock_adjustments_product',
      });
    });
  });

  group('create and upgrade cannot drift apart', () {
    test('the shipped history reaches the same schema either way', () async {
      final Database created = await track(
        DatabaseService.open(path: at('created')),
      );
      await handBuildVersion1(at('upgraded'));
      final Database upgraded = await track(
        DatabaseService.open(path: at('upgraded')),
      );

      expect(await columnsByTable(upgraded), await columnsByTable(created));
      expect(await indexNames(upgraded), await indexNames(created));
    });

    test('a history with a real added step reaches it too', () async {
      final Database created = await track(
        DatabaseService.open(
          path: at('created2'),
          migrations: _throughStep2,
        ),
      );
      await handBuildVersion1(at('upgraded2'));
      final Database upgraded = await track(
        DatabaseService.open(
          path: at('upgraded2'),
          migrations: _throughStep2,
        ),
      );

      final Map<String, Set<String>> shape = await columnsByTable(created);
      expect(shape.containsKey('product_notes'), isTrue);
      expect(shape['products'], contains('shelf'));

      expect(await columnsByTable(upgraded), shape);
      expect(await indexNames(upgraded), await indexNames(created));
    });

    test('the ledger records every step that ran', () async {
      final Database created = await track(
        DatabaseService.open(
          path: at('ledger-created'),
          migrations: _throughStep2,
        ),
      );
      expect(await DatabaseService.appliedVersions(created), <int>[1, 2]);

      await handBuildVersion1(at('ledger-upgraded'));
      final Database upgraded = await track(
        DatabaseService.open(
          path: at('ledger-upgraded'),
          migrations: _throughStep2,
        ),
      );
      expect(await DatabaseService.appliedVersions(upgraded), <int>[1, 2]);
    });
  });

  group('downgrades', () {
    test('a newer file is refused rather than wiped', () async {
      final String path = at('newer');
      final Database newer = await DatabaseService.open(
        path: path,
        migrations: _throughStep2,
      );
      await newer.insert('people', <String, Object?>{
        'id': 1,
        'name': 'Meera',
        'is_household': 0,
        'archived': 0,
      });
      await newer.close();

      await expectLater(
        DatabaseService.open(path: path),
        throwsA(isA<SchemaDowngradeException>()),
      );

      final Database reopened = await track(
        DatabaseService.open(path: path, migrations: _throughStep2),
      );
      final List<Map<String, Object?>> people = await reopened.query('people');
      expect(people, hasLength(1));
      expect(people.first['name'], 'Meera');
      expect(await columnsByTable(reopened), contains('product_notes'));
    });
  });

  group('a version 1 book survives the upgrade', () {
    /// Rows for all thirteen data tables, keyed by table, in write order.
    Map<String, List<Map<String, Object?>>> seed() {
      return <String, List<Map<String, Object?>>>{
        'people': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'name': 'Meera',
            'phone': '9876500001',
            'note': 'flat 402',
            'is_household': 1,
            'archived': 0,
          },
        ],
        'products': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'name': 'Formula 1',
            'unit_label': 'tub',
            'current_price_paise': 205000,
            'category': 'shakes',
            'archived': 0,
          },
        ],
        'product_price_history': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'product_id': 1,
            'price_paise': 199000,
            'effective_from': '2026-01-05T00:00:00.000',
          },
        ],
        'expense_categories': <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'name': 'Petrol', 'archived': 0},
        ],
        'purchases': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'date': '2026-02-01T00:00:00.000',
            'total_paid_paise': 410000,
            'vendor': 'distributor',
            'note': null,
          },
        ],
        'purchase_items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'purchase_id': 1,
            'product_id': 1,
            'qty': 2,
            'unit_cost_paise': 199000,
          },
        ],
        'deliveries': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'person_id': 1,
            'date': '2026-02-03T00:00:00.000',
            'for_member': 'Anu',
            'note': null,
          },
        ],
        'delivery_items': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'delivery_id': 1,
            'product_id': 1,
            'qty': 1,
            'unit_price_paise': 205000,
          },
        ],
        'requests': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'person_id': 1,
            'product_id': 1,
            'qty': 3,
            'status': 'pending',
            'created_at': '2026-02-04T00:00:00.000',
            'for_member': null,
            'note': 'asked on the stairs',
          },
        ],
        'money_entries': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'person_id': 1,
            'date': '2026-02-05T00:00:00.000',
            'amount_paise': 100000,
            'direction': 'in',
            'kind': 'payment_received',
            'method': 'UPI',
            'note': null,
          },
        ],
        'stock_adjustments': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'product_id': 1,
            'qty_delta': -1,
            'reason': 'personal_use',
            'date': '2026-02-06T00:00:00.000',
            'note': null,
          },
        ],
        'expenses': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'date': '2026-02-06T00:00:00.000',
            'amount_paise': 205000,
            'category_id': 1,
            'note': 'used a tub',
            'stock_adjustment_id': 1,
          },
        ],
        'app_settings': <Map<String, Object?>>[
          <String, Object?>{'key': 'upi_handle', 'value': 'meera@upi'},
        ],
      };
    }

    Future<void> fill(String path) async {
      await handBuildVersion1(path);
      final Database db = await databaseFactory.openDatabase(path);
      await db.execute('PRAGMA foreign_keys = ON');
      for (final MapEntry<String, List<Map<String, Object?>>> entry
          in seed().entries) {
        for (final Map<String, Object?> row in entry.value) {
          await db.insert(entry.key, row);
        }
      }
      await db.close();
    }

    test('opening a version 1 book changes not one row', () async {
      final String path = at('v1-untouched');
      await fill(path);
      final Database db = await track(DatabaseService.open(path: path));

      for (final MapEntry<String, List<Map<String, Object?>>> entry
          in seed().entries) {
        final List<Map<String, Object?>> stored = await db.query(
          entry.key,
          orderBy: entry.key == 'app_settings' ? 'key ASC' : 'id ASC',
        );
        expect(stored, entry.value, reason: '${entry.key} changed');
      }
    });

    test('a step that adds to the schema keeps every row', () async {
      final String path = at('v1-to-step2');
      await fill(path);
      final Database db = await track(
        DatabaseService.open(path: path, migrations: _throughStep2),
      );

      for (final MapEntry<String, List<Map<String, Object?>>> entry
          in seed().entries) {
        final List<Map<String, Object?>> stored = await db.query(
          entry.key,
          orderBy: entry.key == 'app_settings' ? 'key ASC' : 'id ASC',
        );
        expect(stored, hasLength(entry.value.length));
        for (int row = 0; row < entry.value.length; row++) {
          entry.value[row].forEach((String column, Object? expected) {
            expect(
              stored[row][column],
              expected,
              reason: '${entry.key} row $row column $column changed',
            );
          });
        }
      }
      // The added column exists and is empty, rather than having taken a
      // value from somewhere.
      final List<Map<String, Object?>> products = await db.query('products');
      expect(products.first['shelf'], isNull);
    });
  });

  group('foreign keys', () {
    test('deleting a delivery removes its items', () async {
      final Database db = await track(DatabaseService.open(path: at('fk-1')));
      await db.insert('people', <String, Object?>{
        'id': 1,
        'name': 'Meera',
        'is_household': 0,
        'archived': 0,
      });
      await db.insert('products', <String, Object?>{
        'id': 1,
        'name': 'Formula 1',
        'unit_label': 'tub',
        'current_price_paise': 205000,
        'archived': 0,
      });
      await db.insert('deliveries', <String, Object?>{
        'id': 1,
        'person_id': 1,
        'date': '2026-02-03T00:00:00.000',
      });
      await db.insert('delivery_items', <String, Object?>{
        'delivery_id': 1,
        'product_id': 1,
        'qty': 2,
        'unit_price_paise': 205000,
      });

      await db.delete('deliveries', where: 'id = ?', whereArgs: <Object?>[1]);

      expect(await db.query('delivery_items'), isEmpty);
    });

    test('deleting a product that has history is refused', () async {
      final Database db = await track(DatabaseService.open(path: at('fk-2')));
      await db.insert('people', <String, Object?>{
        'id': 1,
        'name': 'Meera',
        'is_household': 0,
        'archived': 0,
      });
      await db.insert('products', <String, Object?>{
        'id': 1,
        'name': 'Formula 1',
        'unit_label': 'tub',
        'current_price_paise': 205000,
        'archived': 0,
      });
      await db.insert('deliveries', <String, Object?>{
        'id': 1,
        'person_id': 1,
        'date': '2026-02-03T00:00:00.000',
      });
      await db.insert('delivery_items', <String, Object?>{
        'delivery_id': 1,
        'product_id': 1,
        'qty': 2,
        'unit_price_paise': 205000,
      });

      await expectLater(
        db.delete('products', where: 'id = ?', whereArgs: <Object?>[1]),
        throwsA(isA<DatabaseException>()),
      );
      expect(await db.query('products'), hasLength(1));
    });

    test('deleting a person who owes is refused', () async {
      final Database db = await track(DatabaseService.open(path: at('fk-3')));
      await db.insert('people', <String, Object?>{
        'id': 1,
        'name': 'Meera',
        'is_household': 0,
        'archived': 0,
      });
      await db.insert('money_entries', <String, Object?>{
        'person_id': 1,
        'date': '2026-02-05T00:00:00.000',
        'amount_paise': 100000,
        'direction': 'in',
        'kind': 'payment_received',
      });

      await expectLater(
        db.delete('people', where: 'id = ?', whereArgs: <Object?>[1]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('a money entry cannot store a negative amount', () async {
      final Database db = await track(DatabaseService.open(path: at('fk-4')));
      await db.insert('people', <String, Object?>{
        'id': 1,
        'name': 'Meera',
        'is_household': 0,
        'archived': 0,
      });

      await expectLater(
        db.insert('money_entries', <String, Object?>{
          'person_id': 1,
          'date': '2026-02-05T00:00:00.000',
          'amount_paise': -100000,
          'direction': 'in',
          'kind': 'payment_received',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });
}
