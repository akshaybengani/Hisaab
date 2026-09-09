import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/notice.dart';
import '../components/stock_view.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

/// Every movement behind one product's figure on hand.
class StockHistoryScreen extends StatelessWidget {
  const StockHistoryScreen({required this.product, super.key});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<StockMovement>? movements = state.historyFor(product);
    return Scaffold(
      appBar: AppBar(title: Text(product.name)),
      body: movements == null
          ? const Notice(
              message:
                  'This movement history could not be worked out from the '
                  'records on this phone. Nothing has been changed.',
            )
          : StockHistoryView(product: product, movements: movements),
    );
  }
}
