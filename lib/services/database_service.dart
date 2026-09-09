import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// One numbered, hand-authored step in the schema's history.
///
/// A step is a frozen list of SQL statements. Once committed it is never
/// edited, because a file created by version 3 must end up with exactly the
/// schema a file upgraded to version 3 has. Steps only ever add tables or
/// columns [per std-19].
class Migration {
  const Migration({
    required this.version,
    required this.name,
    required this.statements,
  });

  final int version;

  /// Recorded in the ledger so a support question ("which steps has this
  /// phone actually run?") has an answer that is not a guess.
  final String name;

  final List<String> statements;
}

/// Thrown when the file on disk was written by a newer build. Refusing is the
/// whole point: a downgrade that wiped the file would destroy the only copy of
/// the book.
class SchemaDowngradeException implements Exception {
  const SchemaDowngradeException({required this.onDisk, required this.wanted});

  final int onDisk;
  final int wanted;

  @override
  String toString() =>
      'SchemaDowngradeException: the database file is at version $onDisk and '
      'this build understands version $wanted. Install the newer build again, '
      'export from it, then import into this one.';
}

/// The applied-migration ledger. Created outside the numbered steps, because a
/// step cannot record itself into a table that does not exist yet.
const String _ledgerStatement = '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version INTEGER PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  applied_at TEXT NOT NULL
)''';

/// Version 1: the thirteen data tables, their foreign keys, and the indexes
/// every read filters on.
///
/// Two columns that deliberately do not exist: there is no `balance` on
/// `people` and no `qty` on `products`. Both figures are derived from the
/// movement rows every time they are read, so they cannot drift away from the
/// rows that explain them. See spec-27 dec-1 and dec-3.
const List<String> _version1 = <String>[
  '''
CREATE TABLE products (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  unit_label TEXT NOT NULL,
  current_price_paise INTEGER NOT NULL,
  category TEXT,
  archived INTEGER NOT NULL DEFAULT 0
)''',
  // Owned audit data rather than a record of use, so it follows the product
  // out. Every table that records use restricts instead.
  '''
CREATE TABLE product_price_history (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE CASCADE,
  price_paise INTEGER NOT NULL,
  effective_from TEXT NOT NULL
)''',
  '''
CREATE TABLE people (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT,
  note TEXT,
  is_household INTEGER NOT NULL DEFAULT 0,
  archived INTEGER NOT NULL DEFAULT 0
)''',
  '''
CREATE TABLE purchases (
  id INTEGER PRIMARY KEY,
  date TEXT NOT NULL,
  total_paid_paise INTEGER NOT NULL,
  vendor TEXT,
  note TEXT
)''',
  '''
CREATE TABLE purchase_items (
  id INTEGER PRIMARY KEY,
  purchase_id INTEGER NOT NULL REFERENCES purchases (id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  qty INTEGER NOT NULL,
  unit_cost_paise INTEGER NOT NULL
)''',
  '''
CREATE TABLE deliveries (
  id INTEGER PRIMARY KEY,
  person_id INTEGER NOT NULL REFERENCES people (id) ON DELETE RESTRICT,
  date TEXT NOT NULL,
  for_member TEXT,
  note TEXT
)''',
  // Deleting a delivery takes its lines with it, because a line has no
  // meaning on its own.
  '''
CREATE TABLE delivery_items (
  id INTEGER PRIMARY KEY,
  delivery_id INTEGER NOT NULL REFERENCES deliveries (id) ON DELETE CASCADE,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  qty INTEGER NOT NULL,
  unit_price_paise INTEGER NOT NULL
)''',
  '''
CREATE TABLE requests (
  id INTEGER PRIMARY KEY,
  person_id INTEGER NOT NULL REFERENCES people (id) ON DELETE RESTRICT,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  qty INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at TEXT NOT NULL,
  for_member TEXT,
  note TEXT
)''',
  // The amount is always positive and the direction carries the sign, so a
  // stored negative would let two sign conventions disagree. See dec-4.
  '''
CREATE TABLE money_entries (
  id INTEGER PRIMARY KEY,
  person_id INTEGER NOT NULL REFERENCES people (id) ON DELETE RESTRICT,
  date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL CHECK (amount_paise >= 0),
  direction TEXT NOT NULL,
  kind TEXT NOT NULL,
  method TEXT,
  note TEXT
)''',
  '''
CREATE TABLE stock_adjustments (
  id INTEGER PRIMARY KEY,
  product_id INTEGER NOT NULL REFERENCES products (id) ON DELETE RESTRICT,
  qty_delta INTEGER NOT NULL,
  reason TEXT NOT NULL,
  date TEXT NOT NULL,
  note TEXT
)''',
  '''
CREATE TABLE expense_categories (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  archived INTEGER NOT NULL DEFAULT 0
)''',
  // The stock link cascades because that expense was written by the app as
  // the mirror of one adjustment, never typed by the user. See dec-3.
  '''
CREATE TABLE expenses (
  id INTEGER PRIMARY KEY,
  date TEXT NOT NULL,
  amount_paise INTEGER NOT NULL,
  category_id INTEGER REFERENCES expense_categories (id) ON DELETE SET NULL,
  note TEXT,
  stock_adjustment_id INTEGER
    REFERENCES stock_adjustments (id) ON DELETE CASCADE
)''',
  '''
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT NOT NULL
)''',
  'CREATE INDEX idx_delivery_items_delivery ON delivery_items (delivery_id)',
  'CREATE INDEX idx_deliveries_person ON deliveries (person_id)',
  'CREATE INDEX idx_money_entries_person ON money_entries (person_id)',
  'CREATE INDEX idx_stock_adjustments_product ON stock_adjustments (product_id)',
  'CREATE INDEX idx_purchase_items_purchase ON purchase_items (purchase_id)',
  'CREATE INDEX idx_requests_status ON requests (status)',
  'CREATE INDEX idx_expenses_date ON expenses (date)',
  // Makes the case-insensitive rule in ExpenseRepository.ensureCategory an
  // invariant of the file rather than a promise the repository keeps.
  '''
CREATE UNIQUE INDEX idx_expense_categories_name
  ON expense_categories (name COLLATE NOCASE)''',
];

/// The committed schema history, oldest first. Append here, never edit.
const List<Migration> schemaMigrations = <Migration>[
  Migration(version: 1, name: 'baseline', statements: _version1),
];

/// Opens the book and brings its schema up to date.
///
/// A fresh install and an upgrade run the same loop over the same committed
/// steps, so the two can never drift apart: `onCreate` replays every step from
/// zero, `onUpgrade` replays the ones the file has not seen.
abstract final class DatabaseService {
  static const String fileName = 'hisaab.db';

  /// The version a build of the app understands.
  static int get latestVersion => schemaMigrations.last.version;

  /// Every table the schema defines, including the ledger.
  static const List<String> tableNames = <String>[
    'app_settings',
    'deliveries',
    'delivery_items',
    'expense_categories',
    'expenses',
    'money_entries',
    'people',
    'product_price_history',
    'products',
    'purchase_items',
    'purchases',
    'requests',
    'schema_migrations',
    'stock_adjustments',
  ];

  /// [path] is the full path to the database file. Leave it out on a device,
  /// where the platform decides where databases live. [migrations] exists so
  /// the migration test can prove the replay machinery on a synthetic history
  /// without inventing a step the app then has to ship.
  static Future<Database> open({
    String? path,
    List<Migration>? migrations,
  }) async {
    final List<Migration> steps = migrations ?? schemaMigrations;
    if (steps.isEmpty) {
      throw ArgumentError('a schema needs at least one migration');
    }
    final int target = steps.last.version;
    final String file = path ?? p.join(await getDatabasesPath(), fileName);

    return openDatabase(
      file,
      version: target,
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (Database db, int version) =>
          _replay(db, steps, from: 0, to: version),
      onUpgrade: (Database db, int oldVersion, int newVersion) =>
          _replay(db, steps, from: oldVersion, to: newVersion),
      onDowngrade: (Database db, int oldVersion, int newVersion) async {
        throw SchemaDowngradeException(onDisk: oldVersion, wanted: newVersion);
      },
    );
  }

  /// Applies every committed step in `(from, to]` and records each one.
  static Future<void> _replay(
    DatabaseExecutor db,
    List<Migration> steps, {
    required int from,
    required int to,
  }) async {
    await db.execute(_ledgerStatement);
    int previous = 0;
    for (final Migration step in steps) {
      if (step.version <= previous) {
        throw StateError('migrations must be numbered upwards without gaps');
      }
      previous = step.version;
      if (step.version <= from || step.version > to) continue;
      for (final String statement in step.statements) {
        await db.execute(statement);
      }
      await db.insert('schema_migrations', <String, Object?>{
        'version': step.version,
        'name': step.name,
        'applied_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// The step versions this file has actually run, oldest first.
  static Future<List<int>> appliedVersions(DatabaseExecutor db) async {
    final List<Map<String, Object?>> rows = await db.query(
      'schema_migrations',
      columns: <String>['version'],
      orderBy: 'version ASC',
    );
    return rows.map((Map<String, Object?> row) => row['version']! as int)
        .toList();
  }
}
