import '../constants.dart';

/// Which pool a payment settles.
///
/// The collect screen asks for this only where the person carries money in
/// both pools, because that is the one case the app cannot work out alone.
enum SettlementPool {
  products('Product dues'),
  cash('Cash loan');

  const SettlementPool(this.label);
  final String label;
}

/// What one collection would do, worked out from the figures already on
/// screen. Pure, so the collect screen can be tested without the ledger
/// arithmetic behind it.
class CollectPlan {
  const CollectPlan({
    required this.productDuePaise,
    required this.cashDuePaise,
    required this.paidPaise,
    required this.pool,
  });

  final int productDuePaise;
  final int cashDuePaise;

  /// What the person is handing over right now.
  final int paidPaise;

  /// What the user picked, used only where [needsPoolChoice] is true.
  final SettlementPool pool;

  /// The exact balance, products and cash together.
  int get balancePaise => productDuePaise + cashDuePaise;

  /// True only where both pools carry a balance.
  bool get needsPoolChoice => productDuePaise != 0 && cashDuePaise != 0;

  /// Where only one pool carries a balance there is nothing to ask about, so
  /// the payment lands in that one.
  SettlementPool get effectivePool {
    if (needsPoolChoice) return pool;
    if (productDuePaise == 0 && cashDuePaise != 0) return SettlementPool.cash;
    return SettlementPool.products;
  }

  /// A cash repayment can never pay down a product bill, so the pool decides
  /// the kind. See spec-27 dec-12.
  MoneyKind get kind => effectivePool == SettlementPool.cash
      ? MoneyKind.repayment
      : MoneyKind.paymentReceived;

  /// What is still owed once this payment is recorded. Positive means the
  /// person still owes. Nothing is ever rounded to reach it.
  int get remainderPaise => balancePaise - paidPaise;

  bool get hasPayment => paidPaise > 0;

  bool get hasRemainder => hasPayment && remainderPaise != 0;

  /// The person handed over less than they owe, so the difference is a
  /// discount the owner can choose to give at the moment of collection. It is
  /// a deliberate concession on cash being counted, not a debt abandoned.
  bool get canGiveDiscount => hasRemainder && remainderPaise > 0;

  /// The person handed over more than they owe, so the difference is change
  /// the owner can choose to keep. Recording it keeps the payment equal to
  /// the cash that actually moved. See dec-13.
  bool get canKeepChange => hasRemainder && remainderPaise < 0;

  CollectPlan copyWith({int? paidPaise, SettlementPool? pool}) => CollectPlan(
    productDuePaise: productDuePaise,
    cashDuePaise: cashDuePaise,
    paidPaise: paidPaise ?? this.paidPaise,
    pool: pool ?? this.pool,
  );
}

/// The gap between what a purchase cost in total and what its lines add up
/// to, while the purchase is still being typed in. See spec-27 dec-7.
class PurchaseGap {
  const PurchaseGap({
    required this.lineTotalPaise,
    required this.totalPaidPaise,
  });

  final int lineTotalPaise;
  final int totalPaidPaise;

  /// Positive means the owner paid more than the lines say, which is the
  /// shipping case. Negative means an offer made the order cheaper.
  int get absorbedPaise => totalPaidPaise - lineTotalPaise;

  bool get hasGap => absorbedPaise != 0;

  /// The owner paid out more than the lines account for, so the gap cost her
  /// money and writing it to expenses is a fair offer.
  bool get isAbsorbed => absorbedPaise > 0;

  /// The order came in under its lines, so the gap is a discount she
  /// received. A saving is never an expense, so nothing is offered here.
  bool get isDiscount => absorbedPaise < 0;
}

/// Matches a noun to its count [per std-24]: "1 bottle", "0 bottles".
///
/// Pass [plural] for anything the trailing "s" gets wrong.
String countLabel(int count, String noun, {String? plural}) =>
    count == 1 ? '$count $noun' : '$count ${plural ?? '${noun}s'}';
