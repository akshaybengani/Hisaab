import 'dart:async';

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
import '../services/share_service.dart';
import '../services/statement_text_service.dart';

/// Taking a payment off a person's balance.
class CollectScreen extends StatelessWidget {
  const CollectScreen({
    required this.person,
    this.share = const ShareService(),
    super.key,
  });

  final Person person;

  /// The one way out of the app, injected so a test can read the receipt that
  /// would have been sent instead of standing up a method channel.
  final ShareService share;

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

    // The messenger is read before the pop, because it is the one thing here
    // that belongs to this route's context. The offer itself outlives the
    // screen on purpose: the owner is usually still counting cash, and a
    // receipt is worth sending a few seconds later.
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Took ${Money.formatWithSymbol(plan.paidPaise)}.'),
          action: SnackBarAction(
            label: 'Send receipt',
            onPressed: () => unawaited(_sendReceipt(state, plan.paidPaise)),
          ),
        ),
      );
  }

  /// The receipt for the payment just taken.
  ///
  /// [paidPaise] is what makes the message name this payment rather than
  /// everything ever received from this person, and the statement is read
  /// after the write so the figure it leaves open is the one that is actually
  /// left. Offered, never sent on its own.
  Future<void> _sendReceipt(AppState state, int paidPaise) async {
    final Statement? statement = state.statementFor(person);
    if (statement == null) return;
    final String body = await StatementTextService(
      state.repositories.settings,
    ).receipt(statement, paidPaise: paidPaise);
    await share.sendText(person, body);
  }
}
