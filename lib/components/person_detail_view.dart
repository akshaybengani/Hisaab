import 'package:flutter/material.dart';

import '../constants.dart';
import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import 'section_header.dart';

/// One person's position: the statement in its two groups with a single net
/// figure, then the ledger, then what the owner can do next.
///
/// Takes a built [Statement], so it renders without the ledger arithmetic
/// behind it.
class PersonDetailView extends StatelessWidget {
  const PersonDetailView({
    required this.statement,
    required this.onCollect,
    required this.onLendCash,
    required this.onShareText,
    required this.onSharePdf,
    super.key,
  });

  final Statement statement;
  final VoidCallback onCollect;
  final VoidCallback onLendCash;
  final VoidCallback onShareText;
  final VoidCallback onSharePdf;

  @override
  Widget build(BuildContext context) {
    final List<StatementLine> ledger = <StatementLine>[
      ...statement.products.lines,
      ...statement.cash.lines,
    ]..sort((StatementLine a, StatementLine b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        _NetCard(statement: statement),
        _ActionBar(
          onCollect: onCollect,
          onLendCash: onLendCash,
          onShareText: onShareText,
          onSharePdf: onSharePdf,
        ),
        if (!statement.products.isEmpty)
          _GroupCard(group: statement.products),
        if (!statement.cash.isEmpty) _GroupCard(group: statement.cash),
        if (statement.products.isEmpty && statement.cash.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Text(
              'No handovers and no cash yet. Record a delivery or lend cash '
              'and the statement fills in.',
              textAlign: TextAlign.center,
            ),
          ),
        if (ledger.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Ledger'),
          for (final StatementLine line in ledger) _LedgerRow(line: line),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
          child: Text(
            'Worked out on ${Dates.format(statement.generatedAt)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _NetCard extends StatelessWidget {
  const _NetCard({required this.statement});

  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final int net = statement.netPaise;
    final String label = net > 0
        ? '${statement.person.name} owes you'
        : net < 0
        ? 'You owe ${statement.person.name}'
        : 'Settled';
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: net < 0 ? colours.errorContainer : colours.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: text.labelLarge?.copyWith(
                color: net < 0
                    ? colours.onErrorContainer
                    : colours.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.formatWithSymbol(net.abs()),
                style: text.displaySmall?.copyWith(
                  color: net < 0
                      ? colours.onErrorContainer
                      : colours.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (statement.hasBothPools) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Products ${Money.formatWithSymbol(statement.products.subtotalPaise)}, '
                'cash ${Money.formatWithSymbol(statement.cash.subtotalPaise)}.',
                style: text.bodySmall?.copyWith(
                  color: net < 0
                      ? colours.onErrorContainer
                      : colours.onPrimaryContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onCollect,
    required this.onLendCash,
    required this.onShareText,
    required this.onSharePdf,
  });

  final VoidCallback onCollect;
  final VoidCallback onLendCash;
  final VoidCallback onShareText;
  final VoidCallback onSharePdf;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          FilledButton.icon(
            onPressed: onCollect,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Collect payment'),
          ),
          OutlinedButton.icon(
            onPressed: onLendCash,
            icon: const Icon(Icons.volunteer_activism_outlined),
            label: const Text('Lend cash'),
          ),
          OutlinedButton.icon(
            onPressed: onShareText,
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Share as text'),
          ),
          OutlinedButton.icon(
            onPressed: onSharePdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Share as PDF'),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final StatementGroup group;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(group.title, style: text.titleMedium),
            ),
            const SizedBox(height: 4),
            for (final StatementLine line in group.lines)
              _StatementRow(line: line),
            const Divider(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text('Subtotal', style: text.titleSmall)),
                  Text(
                    Money.formatWithSymbol(group.subtotalPaise),
                    style: text.titleSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatementRow extends StatelessWidget {
  const _StatementRow({required this.line});

  final StatementLine line;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<String> parts = <String>[
      Dates.format(line.date),
      if (line.forMember != null) 'for ${line.forMember}',
      if (line.detail != null) line.detail!,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(line.description, style: text.bodyLarge),
                Text(parts.join(', '), style: text.bodySmall),
                if (line.settlement != null) ...<Widget>[
                  const SizedBox(height: 4),
                  _SettlementChip(state: line.settlement!),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            Money.formatWithSymbol(line.amountPaise),
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SettlementChip extends StatelessWidget {
  const _SettlementChip({required this.state});

  final SettlementState state;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final (String label, Color background, Color foreground) look =
        switch (state) {
          SettlementState.paid => (
            'Paid',
            colours.secondaryContainer,
            colours.onSecondaryContainer,
          ),
          SettlementState.partlyPaid => (
            'Partly paid',
            colours.tertiaryContainer,
            colours.onTertiaryContainer,
          ),
          SettlementState.unpaid => (
            'Unpaid',
            colours.errorContainer,
            colours.onErrorContainer,
          ),
        };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: look.$2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        look.$1,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: look.$3),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.line});

  final StatementLine line;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool reduces = line.amountPaise < 0;
    return ListTile(
      dense: true,
      leading: Icon(
        reduces ? Icons.south_west : Icons.north_east,
        color: reduces ? colours.primary : colours.error,
        size: 20,
      ),
      title: Text(line.description),
      subtitle: Text(Dates.format(line.date)),
      trailing: Text(Money.formatWithSymbol(line.amountPaise)),
    );
  }
}
