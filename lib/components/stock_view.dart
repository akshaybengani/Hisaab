import 'package:flutter/material.dart';

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/view_models.dart';
import 'empty_state.dart';

/// One row per product with the derived figure on hand.
///
/// The stepper writes a movement rather than setting a counter, which is why
/// the history under each row always adds up to the figure above it. See
/// spec-27 dec-3.
class StockView extends StatelessWidget {
  const StockView({
    required this.levels,
    required this.onStep,
    required this.onOpenHistory,
    required this.onPersonalUse,
    required this.onRecount,
    required this.onAddProduct,
    super.key,
  });

  final List<StockLevel> levels;

  /// Called with a signed delta, one per tap.
  final void Function(StockLevel level, int delta) onStep;

  final ValueChanged<StockLevel> onOpenHistory;
  final ValueChanged<StockLevel> onPersonalUse;
  final ValueChanged<StockLevel> onRecount;
  final VoidCallback onAddProduct;

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message:
            'Stock counts what you are holding, worked out from purchases, '
            'deliveries and corrections. Add a product to start counting.',
        actionLabel: 'Add product',
        onAction: onAddProduct,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      itemCount: levels.length,
      itemBuilder: (BuildContext context, int index) => _StockCard(
        level: levels[index],
        onStep: onStep,
        onOpenHistory: onOpenHistory,
        onPersonalUse: onPersonalUse,
        onRecount: onRecount,
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.level,
    required this.onStep,
    required this.onOpenHistory,
    required this.onPersonalUse,
    required this.onRecount,
  });

  final StockLevel level;
  final void Function(StockLevel level, int delta) onStep;
  final ValueChanged<StockLevel> onOpenHistory;
  final ValueChanged<StockLevel> onPersonalUse;
  final ValueChanged<StockLevel> onRecount;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => onOpenHistory(level),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(level.product.name, style: text.titleMedium),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Stock actions',
                    onSelected: (int choice) {
                      switch (choice) {
                        case 0:
                          onPersonalUse(level);
                        case 1:
                          onRecount(level);
                        case 2:
                          onOpenHistory(level);
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        const <PopupMenuEntry<int>>[
                          PopupMenuItem<int>(
                            value: 0,
                            child: Text('Used it myself'),
                          ),
                          PopupMenuItem<int>(
                            value: 1,
                            child: Text('Recount'),
                          ),
                          PopupMenuItem<int>(
                            value: 2,
                            child: Text('Movement history'),
                          ),
                        ],
                  ),
                ],
              ),
              Text(
                '${countLabel(level.onHand, level.product.unitLabel)} on hand, '
                'worth ${Money.formatWithSymbol(level.valuePaise)}',
                style: text.bodySmall?.copyWith(
                  color: level.isOut ? colours.error : null,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Bought ${level.purchased}, out ${level.delivered}, '
                      'corrected ${level.adjusted}',
                      style: text.bodySmall,
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: () => onStep(level, -1),
                    icon: const Icon(Icons.remove),
                    tooltip: 'One less',
                  ),
                  const SizedBox(width: 4),
                  Text('${level.onHand}', style: text.titleMedium),
                  const SizedBox(width: 4),
                  IconButton.outlined(
                    onPressed: () => onStep(level, 1),
                    icon: const Icon(Icons.add),
                    tooltip: 'One more',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product's movements, each with the running figure after it.
class StockHistoryView extends StatelessWidget {
  const StockHistoryView({
    required this.product,
    required this.movements,
    super.key,
  });

  final Product product;
  final List<StockMovement> movements;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    if (movements.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing has moved for ${product.name} yet. A purchase, a '
            'delivery or a correction all show up here.',
            textAlign: TextAlign.center,
            style: text.bodyLarge,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: movements.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final StockMovement movement = movements[index];
        final bool up = movement.qtyDelta > 0;
        final ColorScheme colours = Theme.of(context).colorScheme;
        return ListTile(
          leading: Icon(
            up ? Icons.arrow_upward : Icons.arrow_downward,
            color: up ? colours.primary : colours.error,
          ),
          title: Text(movement.label),
          subtitle: Text(
            <String>[
              Dates.format(movement.date),
              if (movement.detail != null) movement.detail!,
            ].join(', '),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                up ? '+${movement.qtyDelta}' : '${movement.qtyDelta}',
                style: text.titleMedium,
              ),
              Text('${movement.runningOnHand} left', style: text.bodySmall),
            ],
          ),
        );
      },
    );
  }
}
