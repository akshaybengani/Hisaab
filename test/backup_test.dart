import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/repositories/factory.dart';
import 'package:hisaab/repositories/sqflite_repositories.dart';
import 'package:hisaab/services/backup_service.dart';
import 'package:hisaab/services/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/memex_ac.dart';

void main() {
  useAcEmission('test/backup_test.dart');

  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory home;
  late SqfliteRepositories book;
  late BackupService backup;

  Future<SqfliteRepositories> openBook(String name) async =>
      await openRepositories(path: '${home.path}/$name.db')
          as SqfliteRepositories;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('hisaab-backup-');
    book = await openBook('book');
    backup = BackupService(book.database);
  });

  tearDown(() async {
    await book.close();
    await home.delete(recursive: true);
  });

  DateTime day(int d) => DateTime(2026, 2, d);

  /// Puts at least one row in every table the backup carries.
  Future<void> fill(SqfliteRepositories repos) async {
    final int personId = await repos.people.insert(
      const Person(
        id: null,
        name: 'Meera',
        phone: '9876500001',
        note: 'flat 402',
        isHousehold: true,
      ),
    );
    final int productId = await repos.products.insert(
      const Product(
        id: null,
        name: 'Formula 1',
        unitLabel: 'tub',
        currentPricePaise: 205000,
        category: 'shakes',
      ),
    );
    // Writes the price history row.
    await repos.products.update(
      Product(
        id: productId,
        name: 'Formula 1',
        unitLabel: 'tub',
        currentPricePaise: 215000,
        category: 'shakes',
      ),
    );
    final int categoryId = await repos.expenses.ensureCategory('Petrol');
    await repos.purchases.insert(
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
    await repos.deliveries.insert(
      Delivery(
        id: null,
        personId: personId,
        date: day(3),
        forMember: 'Anu',
        note: 'left at the door',
      ),
      <DeliveryItem>[
        DeliveryItem(
          id: null,
          deliveryId: null,
          productId: productId,
          qty: 2,
          unitPricePaise: 205000,
        ),
      ],
    );
    await repos.requests.insert(
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
    await repos.money.insert(
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
    await repos.stock.insertWithExpense(
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
        amountPaise: 215000,
        categoryId: categoryId,
        note: 'used a tub',
      ),
    );
    await repos.settings.write(SettingKeys.upiHandle, 'meera@upi');
  }

  /// Every table's rows, in a stable order, for comparing before and after.
  Future<Map<String, List<Map<String, Object?>>>> snapshot(
    SqfliteRepositories repos,
  ) async {
    final Map<String, List<Map<String, Object?>>> all =
        <String, List<Map<String, Object?>>>{};
    for (final String table in backupTableOrder) {
      all[table] = await repos.database.query(
        table,
        orderBy: table == 'app_settings' ? 'key ASC' : 'id ASC',
      );
    }
    return all;
  }

  Map<String, Object?> decode(String source) =>
      jsonDecode(source) as Map<String, Object?>;

  Map<String, Object?> tablesOf(Map<String, Object?> document) =>
      document['tables']! as Map<String, Object?>;

  group('export', () {
    test('the file is readable JSON with a version and a stamp', () async {
      await fill(book);
      final DateTime stamp = DateTime(2026, 9, 9, 18, 30);
      final String text = await backup.exportJson(generatedAt: stamp);

      expect(text, contains('\n  "schema_version"'));
      final Map<String, Object?> document = decode(text);
      expect(document['format'], 'hisaab-backup');
      expect(document['schema_version'], DatabaseService.latestVersion);
      expect(document['generated_at'], stamp.toIso8601String());
      expect(tablesOf(document).keys.toSet(), backupTableOrder.toSet());
    });

    test('every table the schema holds is carried', () async {
      await fill(book);
      final Map<String, Object?> tables = tablesOf(
        decode(await backup.exportJson()),
      );

      for (final String table in backupTableOrder) {
        expect(tables[table], isA<List<Object?>>(), reason: table);
        expect(
          (tables[table]! as List<Object?>).length,
          greaterThan(0),
          reason: '$table should have been filled',
        );
      }
    });

    test('the migration ledger is not part of the book', () async {
      final Map<String, Object?> tables = tablesOf(
        decode(await backup.exportJson()),
      );
      expect(tables.containsKey('schema_migrations'), isFalse);
    });

    test('writing to a file gives back the same text', () async {
      await fill(book);
      final File file = await backup.exportToFile('${home.path}/out.json');

      expect(await file.exists(), isTrue);
      expect(decode(await file.readAsString())['format'], 'hisaab-backup');
    });
  });

  group('summary', () {
    acTest(
      'it reads the file without opening any database',
      <String>['ac-29'],
      () async {
        await fill(book);
        final String text = await backup.exportJson(
          generatedAt: DateTime(2026, 9, 9),
        );
        await book.close();

        final BackupSummary summary = BackupService.summarise(text);

        expect(summary.schemaVersion, DatabaseService.latestVersion);
        expect(summary.generatedAt, DateTime(2026, 9, 9));
        expect(summary.rowCounts['people'], 1);
        expect(summary.rowCounts['delivery_items'], 1);
        expect(summary.rowCounts.keys.toSet(), backupTableOrder.toSet());
        expect(summary.totalRows, 13);
        expect(summary.isEmpty, isFalse);

        // Reopen so the tear down has something to close.
        book = await openBook('book');
      },
    );

    acTest('an empty book summarises as empty', <String>['ac-32'], () async {
      final BackupSummary summary = BackupService.summarise(
        await backup.exportJson(),
      );
      expect(summary.totalRows, 0);
      expect(summary.isEmpty, isTrue);
    });
  });

  group('round trip', () {
    acTest(
      'export then import reproduces every row',
      <String>['ac-30'],
      () async {
        await fill(book);
        final Map<String, List<Map<String, Object?>>> before = await snapshot(
          book,
        );
        final String text = await backup.exportJson();

        final SqfliteRepositories other = await openBook('other');
        addTearDown(other.close);
        final BackupSummary summary = await BackupService(
          other.database,
        ).importJson(text);

        expect(summary.totalRows, 13);
        final Map<String, List<Map<String, Object?>>> after = await snapshot(
          other,
        );
        for (final String table in backupTableOrder) {
          expect(after[table], before[table], reason: table);
        }
      },
    );

    test('a second import of the same file changes nothing', () async {
      await fill(book);
      final String text = await backup.exportJson();
      await backup.importJson(text);
      final Map<String, List<Map<String, Object?>>> once = await snapshot(book);

      await backup.importJson(text);

      expect(await snapshot(book), once);
    });

    acTest(
      'import replaces the book rather than merging into it',
      <String>['ac-29'],
      () async {
        await fill(book);
        final String text = await backup.exportJson();

        final SqfliteRepositories other = await openBook('other');
        addTearDown(other.close);
        await other.people.insert(const Person(id: null, name: 'Sunita'));
        await other.people.insert(const Person(id: null, name: 'Kavita'));

        await BackupService(other.database).importJson(text);

        expect(
          (await other.people.all()).map((Person each) => each.name).toList(),
          <String>['Meera'],
        );
      },
    );

    test('an empty file empties the book', () async {
      final SqfliteRepositories empty = await openBook('empty');
      addTearDown(empty.close);
      final String text = await BackupService(empty.database).exportJson();

      await fill(book);
      await backup.importJson(text);

      expect(await book.people.all(), isEmpty);
      expect(await book.products.all(), isEmpty);
      expect(await book.expenses.all(), isEmpty);
      expect(await book.settings.readAll(), isEmpty);
    });
  });

  group('a file that cannot be trusted leaves the book alone', () {
    /// Runs [damage] on a valid export, imports the result, and proves the
    /// book is byte for byte what it was.
    Future<void> refuses(
      String Function(String valid) damage,
      Matcher message,
    ) async {
      await fill(book);
      final Map<String, List<Map<String, Object?>>> before = await snapshot(
        book,
      );
      final String broken = damage(await backup.exportJson());

      await expectLater(
        backup.importJson(broken),
        throwsA(
          isA<BackupFormatException>().having(
            (BackupFormatException error) => error.message,
            'message',
            message,
          ),
        ),
      );
      expect(() => BackupService.summarise(broken), throwsA(isA<Exception>()));

      final Map<String, List<Map<String, Object?>>> after = await snapshot(
        book,
      );
      for (final String table in backupTableOrder) {
        expect(after[table], before[table], reason: table);
        expect(after[table], hasLength(before[table]!.length), reason: table);
      }
    }

    acTest('a truncated file', <String>['ac-28'], () async {
      await refuses(
        (String valid) => valid.substring(0, valid.length ~/ 2),
        contains('not valid JSON'),
      );
    });

    acTest('a file cut off at the very end', <String>['ac-28'], () async {
      await refuses(
        (String valid) => valid.substring(0, valid.length - 1),
        contains('not valid JSON'),
      );
    });

    acTest('an unrelated JSON file', <String>['ac-28'], () async {
      await refuses(
        (String valid) => '{"hello": "world"}',
        contains('not a Hisaab backup'),
      );
    });

    acTest('a file written by a newer build', <String>['ac-28'], () async {
      await refuses((String valid) {
        final Map<String, Object?> document = decode(valid);
        document['schema_version'] = DatabaseService.latestVersion + 1;
        return jsonEncode(document);
      }, contains('newer build'));
    });

    acTest('a file with no stamp', <String>['ac-28'], () async {
      await refuses((String valid) {
        final Map<String, Object?> document = decode(valid);
        document.remove('generated_at');
        return jsonEncode(document);
      }, contains('generated_at'));
    });

    acTest('a file missing a whole table', <String>['ac-28'], () async {
      await refuses((String valid) {
        final Map<String, Object?> document = decode(valid);
        tablesOf(document).remove('money_entries');
        return jsonEncode(document);
      }, contains('missing the money_entries table'));
    });

    acTest(
      'a file holding a table this build does not know',
      <String>['ac-28'],
      () async {
        await refuses((String valid) {
          final Map<String, Object?> document = decode(valid);
          tablesOf(document)['invoices'] = <Object?>[];
          return jsonEncode(document);
        }, contains('invoices'));
      },
    );

    acTest('a row missing a column', <String>['ac-28'], () async {
      await refuses((String valid) {
        final Map<String, Object?> document = decode(valid);
        final List<Object?> rows =
            tablesOf(document)['people']! as List<Object?>;
        (rows.first! as Map<String, Object?>).remove('name');
        return jsonEncode(document);
      }, contains('is missing name'));
    });

    acTest(
      'a row with a column this build does not know',
      <String>['ac-28'],
      () async {
        await refuses((String valid) {
          final Map<String, Object?> document = decode(valid);
          final List<Object?> rows =
              tablesOf(document)['people']! as List<Object?>;
          (rows.first! as Map<String, Object?>)['nickname'] = 'Mee';
          return jsonEncode(document);
        }, contains('nickname'));
      },
    );

    acTest(
      'money written as a decimal rather than paise',
      <String>['ac-28'],
      () async {
        await refuses((String valid) {
          final Map<String, Object?> document = decode(valid);
          final List<Object?> rows =
              tablesOf(document)['money_entries']! as List<Object?>;
          (rows.first! as Map<String, Object?>)['amount_paise'] = 1000.5;
          return jsonEncode(document);
        }, contains('should be a whole number'));
      },
    );

    acTest('a status no build has ever written', <String>['ac-28'], () async {
      await refuses((String valid) {
        final Map<String, Object?> document = decode(valid);
        final List<Object?> rows =
            tablesOf(document)['requests']! as List<Object?>;
        (rows.first! as Map<String, Object?>)['status'] = 'posted';
        return jsonEncode(document);
      }, contains('"posted"'));
    });

    acTest(
      'a money kind no build has ever written',
      <String>['ac-28'],
      () async {
        await refuses((String valid) {
          final Map<String, Object?> document = decode(valid);
          final List<Object?> rows =
              tablesOf(document)['money_entries']! as List<Object?>;
          (rows.first! as Map<String, Object?>)['kind'] = 'refund';
          return jsonEncode(document);
        }, contains('"refund"'));
      },
    );

    acTest(
      'a table holding something other than rows',
      <String>['ac-28'],
      () async {
        await refuses((String valid) {
          final Map<String, Object?> document = decode(valid);
          tablesOf(document)['people'] = 'all of them';
          return jsonEncode(document);
        }, contains('should hold a list of rows'));
      },
    );

    acTest(
      'a line pointing at a delivery the file does not carry',
      <String>['ac-28'],
      () async {
        // Validation passes on shape, so the write starts and the foreign key
        // stops it. The rollback still has to leave the book untouched.
        await fill(book);
        final Map<String, List<Map<String, Object?>>> before = await snapshot(
          book,
        );
        final Map<String, Object?> document = decode(await backup.exportJson());
        final List<Object?> rows =
            tablesOf(document)['delivery_items']! as List<Object?>;
        (rows.first! as Map<String, Object?>)['delivery_id'] = 4242;

        await expectLater(
          backup.importJson(jsonEncode(document)),
          throwsA(isA<DatabaseException>()),
        );

        expect(await snapshot(book), before);
      },
    );
  });

  group('there is no merge path', () {
    acTest('nothing under lib/ offers one', <String>['ac-29'], () {
      final Directory lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: 'run this from the repo root');

      final RegExp merging = RegExp(
        r'\b(?:merge|mergeInto|mergeBackup|mergeWith|importMerge)\s*\(',
        caseSensitive: false,
      );
      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (merging.hasMatch(entity.readAsStringSync())) {
          offenders.add(entity.path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'import replaces the whole book. A merge would have to guess '
            'which copy of a changed row is right.',
      );
    });
  });
}
