import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/products_view.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'navigation.dart';
import 'product_edit_screen.dart';

/// Everything that gets bought and handed out.
class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const ProductEditScreen()),
            icon: const Icon(Icons.add),
            tooltip: 'Add product',
          ),
        ],
      ),
      body: ProductsView(
        products: state.products,
        onAddProduct: () => openScreen(context, const ProductEditScreen()),
        onTapProduct: (Product product) =>
            openScreen(context, ProductEditScreen(product: product)),
      ),
    );
  }
}
