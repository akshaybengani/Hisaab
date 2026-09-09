import 'package:sqflite/sqflite.dart';

import 'contracts.dart';
import 'delivery_repository.dart';
import 'expense_repository.dart';
import 'money_repository.dart';
import 'person_repository.dart';
import 'product_repository.dart';
import 'purchase_repository.dart';
import 'request_repository.dart';
import 'settings_repository.dart';
import 'stock_repository.dart';

/// The live storage bundle: nine repositories over one open database.
///
/// [database] is exposed for the two callers that need the connection itself
/// rather than a repository: the backup service, which reads and replaces
/// whole tables, and the derived-figure queries that span tables.
class SqfliteRepositories implements Repositories {
  SqfliteRepositories(Database db)
    : database = db,
      products = SqfliteProductRepository(db),
      people = SqflitePersonRepository(db),
      deliveries = SqfliteDeliveryRepository(db),
      money = SqfliteMoneyRepository(db),
      stock = SqfliteStockRepository(db),
      purchases = SqflitePurchaseRepository(db),
      requests = SqfliteRequestRepository(db),
      expenses = SqfliteExpenseRepository(db),
      settings = SqfliteSettingsRepository(db);

  final Database database;

  @override
  final ProductRepository products;

  @override
  final PersonRepository people;

  @override
  final DeliveryRepository deliveries;

  @override
  final MoneyRepository money;

  @override
  final StockRepository stock;

  @override
  final PurchaseRepository purchases;

  @override
  final RequestRepository requests;

  @override
  final ExpenseRepository expenses;

  @override
  final SettingsRepository settings;

  Future<void> close() => database.close();
}
