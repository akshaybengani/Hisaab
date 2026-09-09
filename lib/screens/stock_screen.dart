import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/amount_dialog.dart';
import '../components/notice.dart';
import '../components/stock_view.dart';
import '../constants.dart';
import '../helpers/dates.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../providers/view_models.dart';
import 'navigation.dart';
import 'product_edit_screen.dart';
import 'stock_history_screen.dart';

/// What is on hand, worked out rather than counted in a column.
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<StockLevel>? levels = state.stockLevels;
    if (levels == null) {
      return const Notice(
        message:
            'Stock could not be worked out from the records on this phone. '
            'Nothing has been changed.',
      );
    }
    return StockView(
      levels: levels,
      onAddProduct: () => openScreen(context, const ProductEditScreen()),
      onOpenHistory: (StockLevel level) =>
          openScreen(context, StockHistoryScreen(product: level.product)),
      onStep: (StockLevel level, int delta) => _step(state, level, delta),
      onPersonalUse: (StockLevel level) => _personalUse(context, state, level),
      onRecount: (StockLevel level) => _recount(context, state, level),
    );
  }

  Future<void> _step(AppState state, StockLevel level, int delta) =>
      state.adjustStock(
        StockAdjustment(
          id: null,
          productId: level.product.id ?? -1,
          qtyDelta: delta,
          reason: StockReason.manual,
          date: Dates.today(),
        ),
      );

  Future<void> _personalUse(
    BuildContext context,
    AppState state,
    StockLevel level,
  ) async {
    final int? qty = await askForCount(
      context,
      title: 'Used it myself',
      label: 'How many ${level.product.unitLabel}',
      actionLabel: 'Record use',
      helper:
          'Takes them out of stock and writes an expense for what they were '
          'worth.',
      initial: 1,
    );
    if (qty == null || qty <= 0 || !context.mounted) return;
    await state.recordPersonalUse(product: level.product, qty: qty);
    if (!context.mounted) return;
    say(
      context,
      '${countLabel(qty, level.product.unitLabel)} out, expense written.',
    );
  }

  Future<void> _recount(
    BuildContext context,
    AppState state,
    StockLevel level,
  ) async {
    final int? counted = await askForCount(
      context,
      title: 'Recount ${level.product.name}',
      label: 'Counted on the shelf',
      actionLabel: 'Save count',
      helper:
          'Records the difference needed to reach your figure, so the '
          'movement history still adds up.',
      initial: level.onHand,
    );
    if (counted == null || !context.mounted) return;
    final int? delta = state.recountDelta(
      currentOnHand: level.onHand,
      countedOnHand: counted,
    );
    if (delta == null) {
      say(context, 'The difference could not be worked out, so nothing was written.');
      return;
    }
    if (delta == 0) {
      say(context, 'Count already matched, nothing written.');
      return;
    }
    await state.adjustStock(
      StockAdjustment(
        id: null,
        productId: level.product.id ?? -1,
        qtyDelta: delta,
        reason: StockReason.recount,
        date: Dates.today(),
        note: 'Counted ${countLabel(counted, level.product.unitLabel)}',
      ),
    );
    if (!context.mounted) return;
    say(context, 'Recount saved as a difference of $delta.');
  }
}
