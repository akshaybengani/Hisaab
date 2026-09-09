import '../constants.dart';
import '../models/models.dart';
import '../services/backup_service.dart';

/// The storage contracts every screen codes against.
///
/// These exist so the three build lanes can work in parallel: the data lane
/// implements them over sqflite, the UI lane builds against an in-memory fake,
/// and neither has to wait for the other. Nothing outside
/// `lib/repositories/` may talk to the database directly.
abstract interface class ProductRepository {
  /// Archived products are excluded unless [includeArchived] is set.
  Future<List<Product>> all({bool includeArchived = false});
  Future<Product?> byId(int id);
  Future<int> insert(Product product);

  /// Updating a price appends to the price history. Updating anything else
  /// does not. See spec-27 dec-2.
  Future<void> update(Product product);
  Future<void> setArchived(int id, {required bool archived});
  Future<List<PriceChange>> priceHistory(int productId);
}

abstract interface class PersonRepository {
  Future<List<Person>> all({bool includeArchived = false});
  Future<Person?> byId(int id);
  Future<int> insert(Person person);
  Future<void> update(Person person);
  Future<void> setArchived(int id, {required bool archived});
}

abstract interface class DeliveryRepository {
  Future<List<DeliveryWithItems>> forPerson(int personId);
  Future<List<DeliveryWithItems>> all();
  Future<DeliveryWithItems?> byId(int id);

  /// Inserts the delivery and its lines in one transaction. Each line's
  /// unit price must already be snapshotted by the caller.
  Future<int> insert(Delivery delivery, List<DeliveryItem> items);
  Future<void> update(Delivery delivery, List<DeliveryItem> items);
  Future<void> delete(int id);
}

abstract interface class MoneyRepository {
  Future<List<MoneyEntry>> forPerson(int personId);
  Future<int> insert(MoneyEntry entry);
  Future<void> update(MoneyEntry entry);
  Future<void> delete(int id);
}

abstract interface class StockRepository {
  Future<List<StockAdjustment>> forProduct(int productId);
  Future<List<StockAdjustment>> all();

  /// Every stepper tap lands here. Writes exactly one row.
  Future<int> insert(StockAdjustment adjustment);

  /// Writes the adjustment and, where [expense] is given, the expense row
  /// linked to it, in one transaction. Used by personal use.
  Future<int> insertWithExpense(StockAdjustment adjustment, Expense expense);
  Future<void> delete(int id);
}

abstract interface class PurchaseRepository {
  Future<List<PurchaseWithItems>> all();
  Future<PurchaseWithItems?> byId(int id);
  Future<int> insert(Purchase purchase, List<PurchaseItem> items);
  Future<void> update(Purchase purchase, List<PurchaseItem> items);
  Future<void> delete(int id);
}

abstract interface class RequestRepository {
  /// Oldest first, so a stale request stays visible. See spec-27 dec-8.
  Future<List<ProductRequest>> byStatus(RequestStatus status);
  Future<List<ProductRequest>> forPerson(int personId);
  Future<int> insert(ProductRequest request);

  /// Rejects a transition the lifecycle does not allow rather than applying
  /// it. See [RequestStatus.canMoveTo].
  Future<void> setStatus(int id, RequestStatus status);

  /// Creates the delivery from the request and marks the request delivered,
  /// in one transaction.
  Future<int> convertToDelivery(int requestId, DeliveryItem item);
  Future<void> delete(int id);
}

abstract interface class ExpenseRepository {
  Future<List<Expense>> all();
  Future<List<Expense>> inMonth(int year, int month);
  Future<int> insert(Expense expense);
  Future<void> update(Expense expense);
  Future<void> delete(int id);

  Future<List<ExpenseCategory>> categories({bool includeArchived = false});

  /// Returns the existing category where the name matches case-insensitively,
  /// rather than creating a near-duplicate. See spec-27 dec-14.
  Future<int> ensureCategory(String name);
  Future<void> setCategoryArchived(int id, {required bool archived});
}

abstract interface class SettingsRepository {
  Future<String?> read(String key);
  Future<Map<String, String>> readAll();
  Future<void> write(String key, String value);
}

/// The whole storage surface, injected as one object so a screen takes one
/// dependency instead of nine.
abstract interface class Repositories {
  ProductRepository get products;
  PersonRepository get people;
  DeliveryRepository get deliveries;
  MoneyRepository get money;
  StockRepository get stock;
  PurchaseRepository get purchases;
  RequestRepository get requests;
  ExpenseRepository get expenses;
  SettingsRepository get settings;

  /// Exports and restores the whole book.
  ///
  /// Null where there is no file behind the data, which is only ever an
  /// in-memory fake in a test. On a device this is always present, and the
  /// settings screen offering a dead tile instead is a bug that reached the
  /// emulator once already.
  BackupService? get backup;
}
