import 'package:flutter/material.dart';

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/view_models.dart';
import 'empty_state.dart';
import 'section_header.dart';

/// The home surface: one figure for everything that is out, then who owes and
/// who is owed.
///
/// Takes balances already worked out, so it renders without the ledger
/// arithmetic behind it.
class DuesView extends StatelessWidget {
  const DuesView({
    required this.balances,
    required this.onTapPerson,
    required this.onAddPerson,
    this.onSeePeople,
    super.key,
  });

  final List<PersonBalance> balances;

  /// Tapping a row goes to collect.
  final ValueChanged<PersonBalance> onTapPerson;

  final VoidCallback onAddPerson;
  final VoidCallback? onSeePeople;

  @override
  Widget build(BuildContext context) {
    if (balances.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        message:
            'Dues is where you see what is still out with people and what '
            'you owe them. Add the first person to start a book.',
        actionLabel: 'Add person',
        onAction: onAddPerson,
      );
    }

    final List<PersonBalance> toCollect =
        balances.where((PersonBalance b) => b.owes).toList()
          ..sort(
            (PersonBalance a, PersonBalance b) =>
                b.netPaise.compareTo(a.netPaise),
          );
    final List<PersonBalance> toPay =
        balances.where((PersonBalance b) => b.isOwed).toList()
          ..sort(
            (PersonBalance a, PersonBalance b) =>
                a.netPaise.compareTo(b.netPaise),
          );

    final int cashOut = toCollect.fold(
      0,
      (int sum, PersonBalance b) => sum + b.netPaise,
    );
    final int owedOut = toPay.fold(
      0,
      (int sum, PersonBalance b) => sum + b.netPaise.abs(),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        _CashOutCard(
          cashOutPaise: cashOut,
          peopleCount: toCollect.length,
          onSeePeople: onSeePeople,
        ),
        if (toCollect.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: 'To collect',
            trailing: Money.formatWithSymbol(cashOut),
          ),
          for (final PersonBalance balance in toCollect)
            _DuesRow(balance: balance, onTap: onTapPerson),
        ],
        if (toPay.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: 'To pay',
            trailing: Money.formatWithSymbol(owedOut),
          ),
          for (final PersonBalance balance in toPay)
            _DuesRow(balance: balance, onTap: onTapPerson),
        ],
        if (toCollect.isEmpty && toPay.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Everyone is square. Nothing to collect and nothing to pay.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _CashOutCard extends StatelessWidget {
  const _CashOutCard({
    required this.cashOutPaise,
    required this.peopleCount,
    this.onSeePeople,
  });

  final int cashOutPaise;
  final int peopleCount;
  final VoidCallback? onSeePeople;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final VoidCallback? onSeePeople = this.onSeePeople;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: colours.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Cash out',
              style: text.labelLarge?.copyWith(
                color: colours.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.formatWithSymbol(cashOutPaise),
                style: text.displaySmall?.copyWith(
                  color: colours.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Waiting with ${countLabel(peopleCount, 'person', plural: 'people')}.',
              style: text.bodySmall?.copyWith(
                color: colours.onPrimaryContainer,
              ),
            ),
            if (onSeePeople != null) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(onPressed: onSeePeople, child: const Text('See everyone')),
            ],
          ],
        ),
      ),
    );
  }
}

class _DuesRow extends StatelessWidget {
  const _DuesRow({required this.balance, required this.onTap});

  final PersonBalance balance;
  final ValueChanged<PersonBalance> onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final DateTime? last = balance.lastActivity;
    final List<String> parts = <String>[
      if (balance.productDuePaise != 0)
        'products ${Money.formatWithSymbol(balance.productDuePaise)}',
      if (balance.cashDuePaise != 0)
        'cash ${Money.formatWithSymbol(balance.cashDuePaise)}',
      if (last != null) Dates.format(last),
    ];
    return ListTile(
      title: Text(balance.person.name),
      subtitle: parts.isEmpty ? null : Text(parts.join(', ')),
      trailing: Text(
        Money.formatWithSymbol(balance.netPaise.abs()),
        style: text.titleMedium?.copyWith(
          color: balance.owes ? colours.primary : colours.error,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => onTap(balance),
    );
  }
}
