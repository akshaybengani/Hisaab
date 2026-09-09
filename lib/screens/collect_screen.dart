import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/collect_view.dart';
import '../components/notice.dart';
import '../constants.dart';
import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../providers/view_models.dart';
import 'navigation.dart';

/// Taking a payment off a person's balance.
class CollectScreen extends StatelessWidget {
  const CollectScreen({required this.person, super.key});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final int? id = person.id;
    final int? productDue = id == null ? null : state.productDueFor(id);
    final int? cashDue = id == null ? null : state.cashDueFor(id);

    return Scaffold(
      appBar: AppBar(title: Text('Collect from ${person.name}')),
      body: productDue == null || cashDue == null || id == null
          ? const Notice(
              message:
                  'This balance could not be worked out from the records on '
                  'this phone, so nothing can be collected against it yet.',
            )
          : CollectView(
              person: person,
              productDuePaise: productDue,
              cashDuePaise: cashDue,
              onRecord: (CollectPlan plan, {required bool clearRemainder}) =>
                  _record(context, state, id, plan, clearRemainder),
            ),
    );
  }

  Future<void> _record(
    BuildContext context,
    AppState state,
    int personId,
    CollectPlan plan,
    bool clearRemainder,
  ) async {
    final DateTime today = Dates.today();
    final MoneyEntry payment = MoneyEntry(
      id: null,
      personId: personId,
      date: today,
      amountPaise: plan.paidPaise,
      direction: MoneyDirection.incoming,
      kind: plan.kind,
    );

    // Both clearing entries are adjustments. A concession made while the cash
    // is being counted is not a debt abandoned, so nothing here writes a
    // [MoneyKind.writeOff]. Direction carries which way it went: a discount
    // reduces what the person owes, change kept brings a negative balance
    // back to zero.
    MoneyEntry? clearing;
    if (clearRemainder && plan.canGiveDiscount) {
      clearing = MoneyEntry(
        id: null,
        personId: personId,
        date: today,
        amountPaise: plan.remainderPaise,
        direction: MoneyDirection.incoming,
        kind: MoneyKind.adjustment,
        note: 'Discount given on collection',
      );
    } else if (clearRemainder && plan.canKeepChange) {
      clearing = MoneyEntry(
        id: null,
        personId: personId,
        date: today,
        amountPaise: plan.remainderPaise.abs(),
        direction: MoneyDirection.outgoing,
        kind: MoneyKind.adjustment,
        note: 'Change kept on collection',
      );
    }

    await state.recordCollection(payment, clearing: clearing);
    if (!context.mounted) return;
    say(context, 'Took ${Money.formatWithSymbol(plan.paidPaise)}.');
    Navigator.of(context).pop();
  }
}
