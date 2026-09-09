import 'package:flutter/material.dart';

import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/view_models.dart';
import 'money_field.dart';

/// Taking a payment.
///
/// Shows the exact balance, what is being handed over, and what is left. It
/// never rounds on its own: where a remainder is left it offers to clear it in
/// one tap, labelled with the real figure, and the user decides.
///
/// It asks which pool the payment settles only where the person carries a
/// balance in both products and cash.
class CollectView extends StatefulWidget {
  const CollectView({
    required this.person,
    required this.productDuePaise,
    required this.cashDuePaise,
    required this.onRecord,
    super.key,
  });

  final Person person;
  final int productDuePaise;
  final int cashDuePaise;

  /// Called with the payment and, where the user chose to clear the leftover,
  /// the write-off or round-off that goes with it.
  final void Function(CollectPlan plan, {required bool clearRemainder})
  onRecord;

  @override
  State<CollectView> createState() => _CollectViewState();
}

class _CollectViewState extends State<CollectView> {
  final TextEditingController _amount = TextEditingController();
  SettlementPool _pool = SettlementPool.products;
  bool _clearRemainder = false;

  @override
  void initState() {
    super.initState();
    final int balance = widget.productDuePaise + widget.cashDuePaise;
    if (balance > 0) {
      _amount.text = Money.format(balance);
    }
    if (widget.productDuePaise == 0 && widget.cashDuePaise != 0) {
      _pool = SettlementPool.cash;
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  CollectPlan get _plan => CollectPlan(
    productDuePaise: widget.productDuePaise,
    cashDuePaise: widget.cashDuePaise,
    paidPaise: Money.parse(_amount.text) ?? 0,
    pool: _pool,
  );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final CollectPlan plan = _plan;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        Card(
          color: colours.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '${widget.person.name} owes',
                  style: text.labelLarge?.copyWith(
                    color: colours.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    Money.formatWithSymbol(plan.balancePaise),
                    style: text.displaySmall?.copyWith(
                      color: colours.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (plan.needsPoolChoice) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(
                    'Products ${Money.formatWithSymbol(widget.productDuePaise)}, '
                    'cash ${Money.formatWithSymbol(widget.cashDuePaise)}.',
                    style: text.bodySmall?.copyWith(
                      color: colours.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        MoneyField(
          controller: _amount,
          label: 'Amount being paid',
          autofocus: true,
          onChanged: (String _) => setState(() {}),
        ),
        if (plan.needsPoolChoice) ...<Widget>[
          const SizedBox(height: 20),
          Text('What does this settle?', style: text.titleSmall),
          const SizedBox(height: 4),
          RadioGroup<SettlementPool>(
            groupValue: _pool,
            onChanged: (SettlementPool? next) =>
                setState(() => _pool = next ?? _pool),
            child: Column(
              children: <Widget>[
                for (final SettlementPool pool in SettlementPool.values)
                  RadioListTile<SettlementPool>(
                    value: pool,
                    title: Text(pool.label),
                    subtitle: Text(
                      pool == SettlementPool.products
                          ? Money.formatWithSymbol(widget.productDuePaise)
                          : Money.formatWithSymbol(widget.cashDuePaise),
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _RemainderCard(plan: plan),
        if (plan.canWriteOff || plan.canAdjust) ...<Widget>[
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _clearRemainder,
            onChanged: (bool? next) =>
                setState(() => _clearRemainder = next ?? false),
            contentPadding: EdgeInsets.zero,
            title: Text(
              plan.canWriteOff
                  ? 'Write off ${Money.formatWithSymbol(plan.remainderPaise)}'
                  : 'Adjust ${Money.formatWithSymbol(plan.remainderPaise.abs())}',
            ),
            subtitle: Text(
              plan.canWriteOff
                  ? 'Records the leftover as a balance you have stopped chasing, '
                        'so the payment stays equal to the cash you took.'
                  : 'Records the overpayment as a deliberate round-off, so the '
                        'payment stays equal to the cash you took.',
            ),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: plan.hasPayment
              ? () => widget.onRecord(plan, clearRemainder: _clearRemainder)
              : null,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _RemainderCard extends StatelessWidget {
  const _RemainderCard({required this.plan});

  final CollectPlan plan;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final int remainder = plan.remainderPaise;
    final String line = remainder == 0
        ? 'Nothing left after this.'
        : remainder > 0
        ? '${Money.formatWithSymbol(remainder)} still owed after this.'
        : '${Money.formatWithSymbol(remainder.abs())} paid over, so you will owe it back.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Line(
              label: 'Balance',
              value: Money.formatWithSymbol(plan.balancePaise),
            ),
            _Line(
              label: 'Paying now',
              value: Money.formatWithSymbol(plan.paidPaise),
            ),
            const Divider(),
            _Line(
              label: 'Remainder',
              value: Money.formatWithSymbol(remainder),
              strong: true,
            ),
            const SizedBox(height: 8),
            Text(line, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final TextStyle? style = strong ? text.titleMedium : text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
