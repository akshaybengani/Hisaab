/// Domain vocabulary for Hisaab. Every enum here has a stable `value` that is
/// written to the database, so renaming a Dart constant never rewrites history.
///
/// Money is stored as an `int` count of paise, never a double. A ledger that
/// loses a rounding error is worse than useless, and 0.1 + 0.2 is not 0.3.
library;

/// Which way money moved, from the book owner's point of view.
enum MoneyDirection {
  /// Money came in, so a person owes less.
  incoming('in'),

  /// Money went out, so a person owes more or the owner owes less.
  outgoing('out');

  const MoneyDirection(this.value);
  final String value;

  static MoneyDirection fromValue(String value) =>
      MoneyDirection.values.firstWhere((d) => d.value == value);
}

/// What a money entry actually is. The kind decides which pool it settles
/// against, per spec-27 dec-12: a product payment can never pay down a cash
/// loan by accident.
enum MoneyKind {
  /// Cash or UPI received against product deliveries.
  paymentReceived('payment_received', settlesDeliveries: true),

  /// Plain cash handed to a person, unrelated to any product.
  cashLent('cash_lent'),

  /// Plain cash taken from a person, so the owner owes them.
  cashBorrowed('cash_borrowed'),

  /// Money coming back against a cash loan.
  repayment('repayment', settlesLoans: true),

  /// A concession made when the cash was counted: a discount given, or change
  /// kept. It closes the difference so the recorded payment stays equal to
  /// the cash that actually changed hands, and it settles the deliveries it
  /// covers. See dec-13 and dec-15.
  adjustment('adjustment', settlesDeliveries: true),

  /// A balance the owner has decided to stop chasing. It settles what it
  /// covers, because the delivery is closed either way. See dec-15.
  writeOff('write_off', settlesDeliveries: true);

  const MoneyKind(
    this.value, {
    this.settlesDeliveries = false,
    this.settlesLoans = false,
  });

  final String value;

  /// True where this kind is allocated against delivery balances.
  final bool settlesDeliveries;

  /// True where this kind is allocated against cash-lent balances.
  final bool settlesLoans;

  static MoneyKind fromValue(String value) =>
      MoneyKind.values.firstWhere((k) => k.value == value);
}

/// Why stock moved without a purchase or a delivery behind it.
enum StockReason {
  /// The owner consumed a unit themselves. Optionally writes an expense.
  personalUse('personal_use'),

  /// A physical count. Writes the delta needed to reach the counted figure,
  /// never the figure itself, so the movement history still reconciles.
  recount('recount'),

  /// Spoiled, broken, or expired.
  damaged('damaged'),

  /// Given away with no expectation of payment.
  gifted('gifted'),

  /// A correction with no better label, from the stepper on the stock card.
  manual('manual');

  const StockReason(this.value);
  final String value;

  static StockReason fromValue(String value) =>
      StockReason.values.firstWhere((r) => r.value == value);
}

/// Where a request sits in the request, order, deliver, collect pipeline.
enum RequestStatus {
  pending('pending'),
  ordered('ordered'),
  delivered('delivered'),
  cancelled('cancelled');

  const RequestStatus(this.value);
  final String value;

  /// The transitions a request is allowed to make. Anything else is rejected
  /// rather than silently applied.
  static const Map<RequestStatus, Set<RequestStatus>> allowed = {
    RequestStatus.pending: {RequestStatus.ordered, RequestStatus.cancelled},
    RequestStatus.ordered: {RequestStatus.delivered, RequestStatus.cancelled},
    RequestStatus.delivered: <RequestStatus>{},
    RequestStatus.cancelled: <RequestStatus>{},
  };

  bool canMoveTo(RequestStatus next) => allowed[this]!.contains(next);

  static RequestStatus fromValue(String value) =>
      RequestStatus.values.firstWhere((s) => s.value == value);
}

/// How much of one delivery a person has covered. Computed on read by
/// allocating their payments oldest first, and never stored. See dec-1.
enum SettlementState {
  /// Covered in full, every paisa of it by money.
  paid,

  /// Closed in full, but part of it was conceded rather than paid: a discount
  /// given, change kept, or a balance written off. Kept apart from [paid] so
  /// a screen never claims a payment that never happened, and so a zero
  /// balance never sits beside a line reading unpaid. See dec-15.
  settled,

  /// Some of it is covered and the rest is still owed.
  partlyPaid,

  /// Nothing is covered yet.
  unpaid,
}

/// Keys into the `app_settings` table. Values are always stored as text.
abstract final class SettingKeys {
  static const String pdfHeader = 'pdf_header';
  static const String pdfFooter = 'pdf_footer';
  static const String themeMode = 'theme_mode';
  static const String templateStatement = 'template_statement';
  static const String templateReminder = 'template_reminder';
  static const String templateReceipt = 'template_receipt';
  static const String templateShoppingList = 'template_shopping_list';
  static const String templateInStock = 'template_in_stock';
  static const String upiHandle = 'upi_handle';
}
