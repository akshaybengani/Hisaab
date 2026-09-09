import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/confirm_dialog.dart';
import '../components/products_view.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

/// Adding or editing one product.
class ProductEditScreen extends StatelessWidget {
  const ProductEditScreen({this.product, super.key});

  final Product? product;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Product? product = this.product;
    final List<String> knownCategories =
        <String>{
          for (final Product p in state.products)
            if (p.category != null && p.category!.isNotEmpty) p.category!,
        }.toList(growable: false)..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(product == null ? 'Add product' : 'Edit product'),
      ),
      body: ProductEditForm(
        initial: product,
        knownCategories: knownCategories,
        onSave: (Product edited) async {
          await state.saveProduct(edited);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
        onSetArchived: ({required bool archived}) async {
          final int? id = product?.id;
          if (id == null) return;
          if (archived) {
            final bool ok = await confirm(
              context,
              title: 'Archive ${product!.name}',
              message:
                  'Archiving takes ${product.name} out of the pickers and '
                  'out of the stock list. Every delivery that used it keeps '
                  'its own price and quantity.',
              actionLabel: 'Archive product',
              destructive: false,
            );
            if (!ok) return;
          }
          await state.setProductArchived(id, archived: archived);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
