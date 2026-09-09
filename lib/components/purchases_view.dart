import 'package:flutter/material.dart';

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/view_models.dart';
import 'empty_state.dart';

/// What the owner bought and paid for.
class PurchasesView extends StatelessWidget {
  const PurchasesView({
    required this.purchases,
    required this.productsById,
    required this.onAddPurchase,
    required this.onTapPurchase,
    super.key,
  });

  final List<PurchaseWithItems> purchases;
  final Map<int, Product> productsById;
  final VoidCallback onAddPurchase;
  final ValueChanged<PurchaseWithItems> onTapPurchase;

  @override
  Widget build(BuildContext context) {
    if (purchases.isEmpty) {
      return EmptyState(
        icon: Icons.local_shipping_outlined,
        message:
            'Purchases records the orders you paid for, which is what puts '
            'units into stock. Add the first order to start.',
        actionLabel: 'Add purchase',
        onAction: onAddPurchase,
      );
    }
    final TextTheme text = Theme.of(context).textTheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: purchases.length,
      itemBuilder: (BuildContext context, int index) {
        final PurchaseWithItems purchase = purchases[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => onTapPurchase(purchase),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          purchase.purchase.vendor ?? 'Order',
                          style: text.titleMedium,
                        ),
                      ),
                      Text(
                        Money.formatWithSymbol(
                          purchase.purchase.totalPaidPaise,
                        ),
                        style: text.titleMedium,
                      ),
                    ],
                  ),
                  Text(
                    Dates.format(purchase.purchase.date),
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final PurchaseItem item in purchase.items)
                    Text(
                      '${productsById[item.productId]?.name ?? 'Unknown product'}, '
                      '${countLabel(item.qty, productsById[item.productId]?.unitLabel ?? 'unit')} '
                      'at ${Money.formatWithSymbol(item.unitCostPaise)}',
                      style: text.bodyMedium,
                    ),
                  if (purchase.absorbedPaise != 0) ...<Widget>[
                    const SizedBox(height: 8),
                    _AbsorbedLine(paise: purchase.absorbedPaise),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AbsorbedLine extends StatelessWidget {
  const _AbsorbedLine({required this.paise});

  final int paise;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Icon(Icons.info_outline, size: 16, color: colours.tertiary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            paise > 0
                ? 'You absorbed ${Money.formatWithSymbol(paise)} over the lines.'
                : 'An offer took ${Money.formatWithSymbol(paise.abs())} off the lines.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
