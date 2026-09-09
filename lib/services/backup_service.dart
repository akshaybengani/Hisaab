import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../constants.dart';
import 'database_service.dart';

/// What kind of value a column holds in the backup file. Money is an integer
/// count of paise and dates are ISO 8601 text, so these two cover every
/// column in the book.
enum BackupValueKind { integer, text }

/// One column of one table, as the file is expected to carry it.
class BackupField {
  const BackupField(
    this.name,
    this.kind, {
    this.nullable = false,
    this.allowed,
    this.since = 1,
  });

  final String name;
  final BackupValueKind kind;
  final bool nullable;

  /// The only values accepted, for the columns that store an enum.
  final Set<String>? allowed;

  /// The schema version that introduced the column. A file written by an
  /// older version may leave it out; a file written by this version may not.
  final int since;
}

/// What a backup file contains, read without opening the database. The UI
/// shows this before the user confirms an import, because replacing the book
/// is not something to find out about afterwards.
class BackupSummary {
  const BackupSummary({
    required this.schemaVersion,
    required this.generatedAt,
    required this.rowCounts,
  });

  final int schemaVersion;
  final DateTime generatedAt;

  /// Row count per table, in write order.
  final Map<String, int> rowCounts;

  int get totalRows =>
      rowCounts.values.fold(0, (int sum, int count) => sum + count);

  bool get isEmpty => totalRows == 0;
}

/// Thrown when a file is not a Hisaab backup, or is one that has been
/// truncated or hand-edited into something the app cannot trust. Every check
/// runs before the first row is written, so a file that raises this leaves the
/// book exactly as it was.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => 'BackupFormatException: $message';
}

/// Table write order: a table only ever appears after the tables it points
/// at. Clearing walks this list backwards for the same reason.
const List<String> backupTableOrder = <String>[
  'people',
  'products',
  'product_price_history',
  'expense_categories',
  'purchases',
  'purchase_items',
  'deliveries',
  'delivery_items',
  'requests',
  'money_entries',
  'stock_adjustments',
  'expenses',
  'app_settings',
];

Set<String> _valuesOf(Iterable<String> values) => values.toSet();

/// The expected shape of every table in the file.
final Map<String, List<BackupField>> backupShape =
    <String, List<BackupField>>{
      'people': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('name', BackupValueKind.text),
        BackupField('phone', BackupValueKind.text, nullable: true),
        BackupField('note', BackupValueKind.text, nullable: true),
        BackupField('is_household', BackupValueKind.integer),
        BackupField('archived', BackupValueKind.integer),
      ],
      'products': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('name', BackupValueKind.text),
        BackupField('unit_label', BackupValueKind.text),
        BackupField('current_price_paise', BackupValueKind.integer),
        BackupField('category', BackupValueKind.text, nullable: true),
        BackupField('archived', BackupValueKind.integer),
      ],
      'product_price_history': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('product_id', BackupValueKind.integer),
        BackupField('price_paise', BackupValueKind.integer),
        BackupField('effective_from', BackupValueKind.text),
      ],
      'expense_categories': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('name', BackupValueKind.text),
        BackupField('archived', BackupValueKind.integer),
      ],
      'purchases': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('date', BackupValueKind.text),
        BackupField('total_paid_paise', BackupValueKind.integer),
        BackupField('vendor', BackupValueKind.text, nullable: true),
        BackupField('note', BackupValueKind.text, nullable: true),
      ],
      'purchase_items': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('purchase_id', BackupValueKind.integer),
        BackupField('product_id', BackupValueKind.integer),
        BackupField('qty', BackupValueKind.integer),
        BackupField('unit_cost_paise', BackupValueKind.integer),
      ],
      'deliveries': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('person_id', BackupValueKind.integer),
        BackupField('date', BackupValueKind.text),
        BackupField('for_member', BackupValueKind.text, nullable: true),
        BackupField('note', BackupValueKind.text, nullable: true),
      ],
      'delivery_items': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('delivery_id', BackupValueKind.integer),
        BackupField('product_id', BackupValueKind.integer),
        BackupField('qty', BackupValueKind.integer),
        BackupField('unit_price_paise', BackupValueKind.integer),
      ],
      'requests': <BackupField>[
        const BackupField('id', BackupValueKind.integer),
        const BackupField('person_id', BackupValueKind.integer),
        const BackupField('product_id', BackupValueKind.integer),
        const BackupField('qty', BackupValueKind.integer),
        BackupField(
          'status',
          BackupValueKind.text,
          allowed: _valuesOf(
            RequestStatus.values.map((RequestStatus s) => s.value),
          ),
        ),
        const BackupField('created_at', BackupValueKind.text),
        const BackupField('for_member', BackupValueKind.text, nullable: true),
        const BackupField('note', BackupValueKind.text, nullable: true),
      ],
      'money_entries': <BackupField>[
        const BackupField('id', BackupValueKind.integer),
        const BackupField('person_id', BackupValueKind.integer),
        const BackupField('date', BackupValueKind.text),
        const BackupField('amount_paise', BackupValueKind.integer),
        BackupField(
          'direction',
          BackupValueKind.text,
          allowed: _valuesOf(
            MoneyDirection.values.map((MoneyDirection d) => d.value),
          ),
        ),
        BackupField(
          'kind',
          BackupValueKind.text,
          allowed: _valuesOf(MoneyKind.values.map((MoneyKind k) => k.value)),
        ),
        const BackupField('method', BackupValueKind.text, nullable: true),
        const BackupField('note', BackupValueKind.text, nullable: true),
      ],
      'stock_adjustments': <BackupField>[
        const BackupField('id', BackupValueKind.integer),
        const BackupField('product_id', BackupValueKind.integer),
        const BackupField('qty_delta', BackupValueKind.integer),
        BackupField(
          'reason',
          BackupValueKind.text,
          allowed: _valuesOf(
            StockReason.values.map((StockReason r) => r.value),
          ),
        ),
        const BackupField('date', BackupValueKind.text),
        const BackupField('note', BackupValueKind.text, nullable: true),
      ],
      'expenses': const <BackupField>[
        BackupField('id', BackupValueKind.integer),
        BackupField('date', BackupValueKind.text),
        BackupField('amount_paise', BackupValueKind.integer),
        BackupField('category_id', BackupValueKind.integer, nullable: true),
        BackupField('note', BackupValueKind.text, nullable: true),
        BackupField(
          'stock_adjustment_id',
          BackupValueKind.integer,
          nullable: true,
        ),
      ],
      'app_settings': const <BackupField>[
        BackupField('key', BackupValueKind.text),
        BackupField('value', BackupValueKind.text),
      ],
    };

/// A validated file, ready to be written. Nothing constructs one of these
/// until every row in the file has passed.
class _CheckedBook {
  const _CheckedBook({required this.summary, required this.rows});

  final BackupSummary summary;
  final Map<String, List<Map<String, Object?>>> rows;
}

/// Exports the whole book to one JSON file and imports one back.
///
/// Import replaces. There is no merge path anywhere in this class or anywhere
/// else in the app, because merging two books means guessing which copy of a
/// changed row is right, and a ledger that guesses is worse than one that asks
/// the user to pick a file.
class BackupService {
  const BackupService(this._db);

  final Database _db;

  /// Names the file as ours, so an unrelated JSON file is refused with a
  /// sentence rather than a type error.
  static const String format = 'hisaab-backup';

  /// Every table, in write order, plus the schema version the rows were
  /// written under. The migration ledger is not exported: it records what a
  /// particular file on a particular phone has run, and after an import that
  /// is a property of the receiving database, not of the file.
  Future<String> exportJson({DateTime? generatedAt}) async {
    final Map<String, Object?> tables = <String, Object?>{};
    for (final String table in backupTableOrder) {
      tables[table] = await _db.query(table, orderBy: _orderBy(table));
    }
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'format': format,
      'schema_version': DatabaseService.latestVersion,
      'generated_at': (generatedAt ?? DateTime.now()).toIso8601String(),
      'tables': tables,
    });
  }

  /// Writes the export to [path] and returns the file, for the share sheet.
  Future<File> exportToFile(String path, {DateTime? generatedAt}) async {
    final File file = File(path);
    await file.writeAsString(await exportJson(generatedAt: generatedAt));
    return file;
  }

  /// Reads a file's contents without opening the database, so the confirm
  /// dialog can say what is about to replace the book. Throws
  /// [BackupFormatException] on anything it cannot vouch for.
  static BackupSummary summarise(String source) => _check(source).summary;

  /// Validates the whole file, then replaces every table inside one
  /// transaction. A file that fails validation never reaches the database, and
  /// a failure part way through the write rolls the whole replacement back, so
  /// the book is either the old one or the new one and never a mixture.
  Future<BackupSummary> importJson(String source) async {
    final _CheckedBook book = _check(source);
    await _db.transaction((Transaction txn) async {
      for (final String table in backupTableOrder.reversed) {
        await txn.delete(table);
      }
      for (final String table in backupTableOrder) {
        for (final Map<String, Object?> row in book.rows[table]!) {
          await txn.insert(table, row);
        }
      }
    });
    return book.summary;
  }

  /// Convenience for the import screen, which holds a path rather than text.
  Future<BackupSummary> importFile(String path) async =>
      importJson(await File(path).readAsString());

  static String _orderBy(String table) =>
      table == 'app_settings' ? 'key ASC' : 'id ASC';

  static Object? _decode(String source) {
    try {
      return jsonDecode(source) as Object?;
    } on FormatException catch (error) {
      throw BackupFormatException(
        'this file is not valid JSON, so it is probably truncated or was not '
        'written by Hisaab (${error.message})',
      );
    }
  }

  static _CheckedBook _check(String source) {
    final Object? decoded = _decode(source);
    if (decoded is! Map<String, Object?>) {
      throw const BackupFormatException(
        'the file should hold one JSON object',
      );
    }

    if (decoded['format'] != format) {
      throw const BackupFormatException(
        'this is not a Hisaab backup file',
      );
    }

    final Object? version = decoded['schema_version'];
    if (version is! int) {
      throw const BackupFormatException(
        'schema_version is missing or is not a whole number',
      );
    }
    if (version < 1) {
      throw BackupFormatException('schema_version $version is not a version');
    }
    if (version > DatabaseService.latestVersion) {
      throw BackupFormatException(
        'this file was written by a newer build (schema version $version, '
        'this build understands ${DatabaseService.latestVersion}). Import it '
        'there instead.',
      );
    }

    final Object? stamp = decoded['generated_at'];
    final DateTime? generatedAt =
        stamp is String ? DateTime.tryParse(stamp) : null;
    if (generatedAt == null) {
      throw const BackupFormatException(
        'generated_at is missing or is not a date',
      );
    }

    final Object? tables = decoded['tables'];
    if (tables is! Map<String, Object?>) {
      throw const BackupFormatException('tables is missing');
    }
    final Set<String> unexpected = tables.keys.toSet()
      ..removeAll(backupTableOrder);
    if (unexpected.isNotEmpty) {
      throw BackupFormatException(
        'the file holds tables this build does not know: '
        '${(unexpected.toList()..sort())}',
      );
    }

    final Map<String, List<Map<String, Object?>>> rows =
        <String, List<Map<String, Object?>>>{};
    final Map<String, int> counts = <String, int>{};
    for (final String table in backupTableOrder) {
      final Object? raw = tables[table];
      if (raw == null) {
        throw BackupFormatException('the file is missing the $table table');
      }
      if (raw is! List<Object?>) {
        throw BackupFormatException('$table should hold a list of rows');
      }
      final List<Map<String, Object?>> checked = <Map<String, Object?>>[];
      for (int index = 0; index < raw.length; index++) {
        checked.add(_checkRow(table, index, raw[index], version));
      }
      rows[table] = checked;
      counts[table] = checked.length;
    }

    return _CheckedBook(
      summary: BackupSummary(
        schemaVersion: version,
        generatedAt: generatedAt,
        rowCounts: counts,
      ),
      rows: rows,
    );
  }

  static Map<String, Object?> _checkRow(
    String table,
    int index,
    Object? raw,
    int fileVersion,
  ) {
    if (raw is! Map<String, Object?>) {
      throw BackupFormatException('$table row $index is not an object');
    }
    final List<BackupField> fields = backupShape[table]!;
    final Set<String> known = fields
        .map((BackupField field) => field.name)
        .toSet();
    final Set<String> extra = raw.keys.toSet()..removeAll(known);
    if (extra.isNotEmpty) {
      throw BackupFormatException(
        '$table row $index holds columns this build does not know: '
        '${(extra.toList()..sort())}',
      );
    }

    final Map<String, Object?> row = <String, Object?>{};
    for (final BackupField field in fields) {
      final bool present = raw.containsKey(field.name);
      final Object? value = raw[field.name];
      if (!present || value == null) {
        final bool optional = field.nullable || field.since > fileVersion;
        if (!optional) {
          throw BackupFormatException(
            '$table row $index is missing ${field.name}',
          );
        }
        if (present) row[field.name] = null;
        continue;
      }
      switch (field.kind) {
        case BackupValueKind.integer:
          if (value is! int) {
            throw BackupFormatException(
              '$table row $index has ${field.name} as ${value.runtimeType}, '
              'and it should be a whole number',
            );
          }
        case BackupValueKind.text:
          if (value is! String) {
            throw BackupFormatException(
              '$table row $index has ${field.name} as ${value.runtimeType}, '
              'and it should be text',
            );
          }
          final Set<String>? allowed = field.allowed;
          if (allowed != null && !allowed.contains(value)) {
            throw BackupFormatException(
              '$table row $index has ${field.name} as "$value", which is not '
              'one of ${(allowed.toList()..sort())}',
            );
          }
      }
      row[field.name] = value;
    }
    return row;
  }
}
