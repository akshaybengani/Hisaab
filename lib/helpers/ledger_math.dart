import '../constants.dart';
import '../models/models.dart';

/// The money arithmetic, as pure functions with no I/O.
///
/// Nothing here reads the database or holds state, which is what makes the
/// worked cases in spec-27 cheap to assert exhaustively. The lane that owns
/// this file owns nothing else.
abstract final class LedgerMath {
  /// What a person owes for products: the sum of their delivery lines minus
  /// every money entry that settles deliveries.
  ///
  /// Positive means they owe. There is no stored balance column anywhere in
  /// the schema. See spec-27 dec-1, verified by ac-8.
  static int productBalance(
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    throw UnimplementedError('owned by lane/math');
  }

  /// What a person owes on plain cash loans, kept apart from products so a
  /// product payment can never pay one down. See dec-4 and dec-12, verified
  /// by ac-34.
  static int cashBalance(List<MoneyEntry> entries) {
    throw UnimplementedError('owned by lane/math');
  }

  /// Marks each delivery paid, partly paid, or unpaid by consuming
  /// delivery-settling payments oldest first.
  ///
  /// Pure, and the result is never persisted, so it cannot drift from the
  /// balance. Returns a map keyed by delivery id. See dec-1, verified by
  /// ac-9 and ac-10.
  static Map<int, SettlementState> allocate(
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    throw UnimplementedError('owned by lane/math');
  }

  /// How much of one delivery is covered, in paise, for the partly-paid case.
  static int coveredPaise(
    int deliveryId,
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    throw UnimplementedError('owned by lane/math');
  }

  /// Builds the object every renderer reads. Product dues and cash appear as
  /// two subtotalled groups with one net figure. See dec-6, verified by
  /// ac-20 and ac-18.
  static Statement buildStatement({
    required Person person,
    required List<DeliveryWithItems> deliveries,
    required List<MoneyEntry> entries,
    required Map<int, Product> productsById,
    required DateTime generatedAt,
  }) {
    throw UnimplementedError('owned by lane/math');
  }

  /// Every person's position, for the dues list, sorted by what they owe.
  static List<PersonBalance> balances({
    required List<Person> people,
    required Map<int, List<DeliveryWithItems>> deliveriesByPerson,
    required Map<int, List<MoneyEntry>> entriesByPerson,
  }) {
    throw UnimplementedError('owned by lane/math');
  }
}
