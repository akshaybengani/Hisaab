import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/purchase_form.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'navigation.dart';
import 'product_edit_screen.dart';

/// Adding a purchase, with the absorbed gap shown rather than hidden.
class PurchaseEditScreen extends StatelessWidget {
  const PurchaseEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Add purchase')),
      body: PurchaseForm(
        products: state.activeProducts,
        categories: state.categories
            .where((ExpenseCategory c) => !c.archived)
            .toList(growable: false),
        onAddProduct: () => openScreen(context, const ProductEditScreen()),
        onSave:
            (
              Purchase purchase,
              List<PurchaseItem> items, {
              Expense? absorbedExpense,
            }) async {
              await state.savePurchase(
                purchase,
                items,
                absorbedExpense: absorbedExpense,
              );
              if (!context.mounted) return;
              say(context, 'Purchase saved.');
              Navigator.of(context).pop();
            },
      ),
    );
  }
}
