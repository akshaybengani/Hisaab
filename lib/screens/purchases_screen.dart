import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/purchases_view.dart';
import '../providers/app_state.dart';
import 'navigation.dart';
import 'purchase_edit_screen.dart';

/// The orders the owner paid for.
class PurchasesScreen extends StatelessWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const PurchaseEditScreen()),
            icon: const Icon(Icons.add),
            tooltip: 'Add purchase',
          ),
        ],
      ),
      body: PurchasesView(
        purchases: state.purchases,
        productsById: state.productsById,
        onAddPurchase: () => openScreen(context, const PurchaseEditScreen()),
        onTapPurchase: (_) => openScreen(context, const PurchaseEditScreen()),
      ),
    );
  }
}
