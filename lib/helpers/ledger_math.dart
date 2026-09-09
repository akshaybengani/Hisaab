import '../constants.dart';
import '../models/models.dart';
import 'money.dart';

/// The money arithmetic, as pure functions with no I/O.
///
/// Nothing here reads the database or holds state, which is what makes the
/// worked cases in spec-27 cheap to assert exhaustively. The lane that owns
/// this file owns nothing else.
///
/// Two rules hold everywhere below. A money entry's [MoneyKind] decides which
/// pool it settles, never its date, so a product payment can never pay down a
/// cash loan. And [MoneyEntry.direction] carries the sign, so an entry that
/// came in always reduces what a person owes on its own pool.
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
    int balance = 0;
    for (final DeliveryWithItems delivery in deliveries) {
      balance += delivery.totalPaise;
    }
    for (final MoneyEntry entry in entries) {
      if (_isProductPool(entry.kind)) balance += entry.signedPaise;
    }
    return balance;
  }

  /// What a person owes on plain cash loans, kept apart from products so a
  /// product payment can never pay one down. See dec-4 and dec-12, verified
  /// by ac-34.
  static int cashBalance(List<MoneyEntry> entries) {
    int balance = 0;
    for (final MoneyEntry entry in entries) {
      if (_isCashPool(entry.kind)) balance += entry.signedPaise;
    }
    return balance;
  }

  /// Marks each delivery paid, settled, partly paid, or unpaid by consuming
  /// the money and then the concessions that settle deliveries, oldest first.
  ///
  /// A concession closes a delivery just as money does, so a delivery covered
  /// in part by a discount reads [SettlementState.settled] rather than
  /// leaving an unpaid line beside a zero balance. Covered entirely by money
  /// it reads [SettlementState.paid]. See dec-15, verified by ac-42.
  ///
  /// Pure, and the result is never persisted, so it cannot drift from the
  /// balance. Returns a map keyed by delivery id. See dec-1, verified by
  /// ac-9 and ac-10.
  ///
  /// A delivery that has not been saved yet has no id to key, so it consumes
  /// its share of the payments in date order but does not appear in the
  /// result.
  static Map<int, SettlementState> allocate(
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    final Map<int, SettlementState> states = <int, SettlementState>{};
    for (final _Coverage coverage in _cover(deliveries, entries)) {
      final int? id = coverage.delivery.delivery.id;
      if (id != null) states[id] = coverage.state;
    }
    return states;
  }

  /// How much of one delivery is covered, in paise, for the partly-paid case.
  static int coveredPaise(
    int deliveryId,
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    for (final _Coverage coverage in _cover(deliveries, entries)) {
      if (coverage.delivery.delivery.id == deliveryId) {
        return coverage.coveredPaise;
      }
    }
    return 0;
  }

  /// How much of one delivery's coverage was conceded rather than paid, in
  /// paise. Zero on a delivery covered entirely by money.
  ///
  /// Public because a settled delivery has to name the figure on screen, which
  /// is the whole reason [SettlementState.settled] exists. See dec-15,
  /// verified by ac-43.
  static int concededPaise(
    int deliveryId,
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    for (final _Coverage coverage in _cover(deliveries, entries)) {
      if (coverage.delivery.delivery.id == deliveryId) {
        return coverage.concededPaise;
      }
    }
    return 0;
  }

  /// Builds the object every renderer reads. Product dues and cash appear as
  /// two subtotalled groups with one net figure. See dec-6, verified by
  /// ac-20 and ac-18.
  ///
  /// A discount, change kept, and a write-off are lines of their own rather
  /// than a smaller delivery, so what was handed over still reads at the price
  /// it was handed over at. See dec-13.
  static Statement buildStatement({
    required Person person,
    required List<DeliveryWithItems> deliveries,
    required List<MoneyEntry> entries,
    required Map<int, Product> productsById,
    required DateTime generatedAt,
  }) {
    final List<MoneyEntry> ordered = _sortedEntries(entries);

    final List<StatementLine> productLines = <StatementLine>[
      for (final _Coverage coverage in _cover(deliveries, entries))
        StatementLine(
          date: coverage.delivery.delivery.date,
          description: _deliveryDescription(coverage.delivery, productsById),
          amountPaise: coverage.delivery.totalPaise,
          forMember: coverage.delivery.delivery.forMember,
          settlement: coverage.state,
          concededPaise: coverage.concededPaise,
          detail: _deliveryDetail(coverage.delivery, productsById),
        ),
      for (final MoneyEntry entry in ordered)
        if (_isProductPool(entry.kind)) _moneyLine(entry),
    ];

    final List<StatementLine> cashLines = <StatementLine>[
      for (final MoneyEntry entry in ordered)
        if (_isCashPool(entry.kind)) _moneyLine(entry),
    ];

    return Statement(
      person: person,
      products: StatementGroup(
        title: 'Product dues',
        lines: _stableByDate(productLines),
      ),
      cash: StatementGroup(title: 'Cash loans', lines: cashLines),
      generatedAt: generatedAt,
    );
  }

  /// Every person's position, for the dues list, sorted by what they owe.
  ///
  /// A person with nothing against them still gets a row, with a zero net and
  /// no last activity, because the dues list is also how someone is found.
  static List<PersonBalance> balances({
    required List<Person> people,
    required Map<int, List<DeliveryWithItems>> deliveriesByPerson,
    required Map<int, List<MoneyEntry>> entriesByPerson,
  }) {
    final List<PersonBalance> result = <PersonBalance>[];
    for (final Person person in people) {
      final int? id = person.id;
      final List<DeliveryWithItems> deliveries = id == null
          ? const <DeliveryWithItems>[]
          : deliveriesByPerson[id] ?? const <DeliveryWithItems>[];
      final List<MoneyEntry> entries = id == null
          ? const <MoneyEntry>[]
          : entriesByPerson[id] ?? const <MoneyEntry>[];
      result.add(
        PersonBalance(
          person: person,
          productDuePaise: productBalance(deliveries, entries),
          cashDuePaise: cashBalance(entries),
          lastActivity: _lastActivity(deliveries, entries),
        ),
      );
    }
    result.sort((PersonBalance a, PersonBalance b) {
      final int byNet = b.netPaise.compareTo(a.netPaise);
      if (byNet != 0) return byNet;
      return a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase());
    });
    return result;
  }

  /// The kinds allocated against product deliveries: a payment, and the two
  /// concessions that close a delivery without one.
  static bool _isProductPool(MoneyKind kind) => kind.settlesDeliveries;

  /// The kinds that close a delivery without money changing hands. Tracked
  /// apart from payments so a covered delivery can say which of the two did
  /// it. See dec-15.
  static bool _isConcession(MoneyKind kind) =>
      kind == MoneyKind.adjustment || kind == MoneyKind.writeOff;

  /// The kinds that belong to the cash pool: the two sides of a plain loan
  /// and the money coming back against one.
  static bool _isCashPool(MoneyKind kind) =>
      kind.settlesLoans ||
      kind == MoneyKind.cashLent ||
      kind == MoneyKind.cashBorrowed;

  /// The cash available to settle deliveries: the money the person actually
  /// handed over, concessions excluded. A net refund leaves nothing rather
  /// than a negative pool.
  static int _paidPaise(List<MoneyEntry> entries) =>
      _availablePaise(entries, conceded: false);

  /// The concessions available to settle deliveries: a discount given, change
  /// kept, or a balance written off. Consumed after the money, so a
  /// concession lands on the delivery the money did not reach. See dec-15.
  static int _concessionPaise(List<MoneyEntry> entries) =>
      _availablePaise(entries, conceded: true);

  static int _availablePaise(
    List<MoneyEntry> entries, {
    required bool conceded,
  }) {
    int available = 0;
    for (final MoneyEntry entry in entries) {
      if (entry.kind.settlesDeliveries &&
          _isConcession(entry.kind) == conceded) {
        available -= entry.signedPaise;
      }
    }
    return available < 0 ? 0 : available;
  }

  /// Walks the deliveries oldest first and consumes the delivery-settling
  /// money until it runs out, then does the same with the concessions.
  /// Deliveries are ordered by date, then by id, so the outcome never depends
  /// on the order the caller happened to read them.
  ///
  /// Money goes first on purpose. It means a concession lands on the part no
  /// payment reached, which is where it was actually granted, and a delivery
  /// money covered outright still reads as paid.
  static List<_Coverage> _cover(
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    final List<DeliveryWithItems> ordered = List<DeliveryWithItems>.of(
      deliveries,
    )..sort(_byDeliveryDate);
    int paid = _paidPaise(entries);
    int conceded = _concessionPaise(entries);
    final List<_Coverage> result = <_Coverage>[];
    for (final DeliveryWithItems delivery in ordered) {
      final int total = delivery.totalPaise;
      if (total <= 0) {
        result.add(_Coverage(delivery, total, 0));
        continue;
      }
      final int fromMoney = total <= paid ? total : paid;
      if (fromMoney > 0) paid -= fromMoney;
      final int shortfall = total - fromMoney;
      final int fromConcession = shortfall <= conceded ? shortfall : conceded;
      if (fromConcession > 0) conceded -= fromConcession;
      result.add(
        _Coverage(delivery, fromMoney + fromConcession, fromConcession),
      );
    }
    return result;
  }

  static int _byDeliveryDate(DeliveryWithItems a, DeliveryWithItems b) {
    final int byDate = a.delivery.date.compareTo(b.delivery.date);
    if (byDate != 0) return byDate;
    return (a.delivery.id ?? _noId).compareTo(b.delivery.id ?? _noId);
  }

  static List<MoneyEntry> _sortedEntries(List<MoneyEntry> entries) {
    return List<MoneyEntry>.of(entries)..sort((MoneyEntry a, MoneyEntry b) {
      final int byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      return (a.id ?? _noId).compareTo(b.id ?? _noId);
    });
  }

  /// Sorts by date without disturbing the order of lines that share one, so a
  /// delivery still reads above the payment made against it the same day.
  /// Dart's own sort makes no such promise.
  static List<StatementLine> _stableByDate(List<StatementLine> lines) {
    final List<StatementLine> sorted = List<StatementLine>.of(lines);
    for (int i = 1; i < sorted.length; i++) {
      final StatementLine current = sorted[i];
      int slot = i - 1;
      while (slot >= 0 && sorted[slot].date.isAfter(current.date)) {
        sorted[slot + 1] = sorted[slot];
        slot--;
      }
      sorted[slot + 1] = current;
    }
    return sorted;
  }

  static StatementLine _moneyLine(MoneyEntry entry) => StatementLine(
    date: entry.date,
    description: _describe(entry),
    amountPaise: entry.signedPaise,
    detail: _moneyDetail(entry),
  );

  /// An adjustment reads by its direction, because the two directions are
  /// different acts in the owner's own words: money in means she gave a
  /// discount, money out means she kept the change. A write-off is neither.
  static String _describe(MoneyEntry entry) => switch (entry.kind) {
    MoneyKind.paymentReceived => 'Payment received',
    MoneyKind.cashLent => 'Cash lent',
    MoneyKind.cashBorrowed => 'Cash borrowed',
    MoneyKind.repayment => 'Repayment',
    MoneyKind.adjustment =>
      entry.direction == MoneyDirection.incoming
          ? 'Discount given'
          : 'Change kept',
    MoneyKind.writeOff => 'Written off',
  };

  static String? _moneyDetail(MoneyEntry entry) {
    final List<String> parts = <String>[
      ?_trimmed(entry.method),
      ?_trimmed(entry.note),
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  static String? _trimmed(String? value) {
    if (value == null) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// One product on a delivery reads as that product. Several read as a
  /// delivery, with the products in the detail underneath.
  static String _deliveryDescription(
    DeliveryWithItems delivery,
    Map<int, Product> productsById,
  ) {
    if (delivery.items.length != 1) return 'Delivery';
    return _productName(delivery.items.single.productId, productsById);
  }

  /// "2 tub at 2,050", from the price snapshotted on the line rather than the
  /// product's price today. That is what stops a price edit from rewriting a
  /// statement already sent. See dec-2.
  static String? _deliveryDetail(
    DeliveryWithItems delivery,
    Map<int, Product> productsById,
  ) {
    if (delivery.items.isEmpty) return null;
    final bool nameEachLine = delivery.items.length > 1;
    return delivery.items
        .map((DeliveryItem item) {
          final Product? product = productsById[item.productId];
          return <String>[
            '${item.qty}',
            if (product != null) product.unitLabel,
            if (nameEachLine) _productName(item.productId, productsById),
            'at',
            Money.format(item.unitPricePaise),
          ].join(' ');
        })
        .join(', ');
  }

  /// A product deleted from the catalogue still has to render, because the
  /// delivery that named it happened.
  static String _productName(int productId, Map<int, Product> productsById) =>
      productsById[productId]?.name ?? 'Item $productId';

  static DateTime? _lastActivity(
    List<DeliveryWithItems> deliveries,
    List<MoneyEntry> entries,
  ) {
    DateTime? latest;
    for (final DeliveryWithItems delivery in deliveries) {
      if (latest == null || delivery.delivery.date.isAfter(latest)) {
        latest = delivery.delivery.date;
      }
    }
    for (final MoneyEntry entry in entries) {
      if (latest == null || entry.date.isAfter(latest)) latest = entry.date;
    }
    return latest;
  }

  /// Sorts an unsaved row last, since it has no id to compare.
  static const int _noId = -1 >>> 1;
}

/// How much of one delivery is covered and how much of that was conceded,
/// which is the only state allocation needs to carry between deliveries.
class _Coverage {
  const _Coverage(this.delivery, this.coveredPaise, this.concededPaise);

  final DeliveryWithItems delivery;
  final int coveredPaise;

  /// The part of [coveredPaise] that came from a discount, change kept, or a
  /// write-off rather than from money. Zero on a delivery covered by cash.
  final int concededPaise;

  SettlementState get state {
    final int total = delivery.totalPaise;
    if (coveredPaise >= total) {
      return concededPaise > 0 ? SettlementState.settled : SettlementState.paid;
    }
    if (coveredPaise <= 0) return SettlementState.unpaid;
    return SettlementState.partlyPaid;
  }
}
