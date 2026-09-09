import 'package:flutter/material.dart';

import '../helpers/money.dart';
import '../models/models.dart';
import 'empty_state.dart';
import 'money_field.dart';
import 'section_header.dart';

/// Everything that gets bought and handed out.
class ProductsView extends StatelessWidget {
  const ProductsView({
    required this.products,
    required this.onAddProduct,
    required this.onTapProduct,
    super.key,
  });

  final List<Product> products;
  final VoidCallback onAddProduct;
  final ValueChanged<Product> onTapProduct;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return EmptyState(
        icon: Icons.category_outlined,
        message:
            'Products holds what you hand out and what one unit costs. That '
            'price prefills every delivery line, so add the first one here.',
        actionLabel: 'Add product',
        onAction: onAddProduct,
      );
    }

    final List<Product> active = products
        .where((Product p) => !p.archived)
        .toList(growable: false);
    final List<Product> archived = products
        .where((Product p) => p.archived)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        if (active.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'In use'),
          for (final Product product in active)
            _ProductRow(product: product, onTap: onTapProduct),
        ],
        if (archived.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Archived'),
          for (final Product product in archived)
            _ProductRow(product: product, onTap: onTapProduct),
        ],
      ],
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.product, required this.onTap});

  final Product product;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(product.name),
      subtitle: Text(
        <String>[
          'per ${product.unitLabel}',
          if (product.category != null) product.category!,
        ].join(', '),
      ),
      trailing: Text(Money.formatWithSymbol(product.currentPricePaise)),
      onTap: () => onTap(product),
    );
  }
}

/// Adding or editing one product.
///
/// Editing the price changes what the next delivery prefills with. It never
/// touches a delivery already recorded. See spec-27 dec-2.
class ProductEditForm extends StatefulWidget {
  const ProductEditForm({
    required this.onSave,
    required this.onSetArchived,
    this.initial,
    this.knownCategories = const <String>[],
    super.key,
  });

  final ValueChanged<Product> onSave;
  final void Function({required bool archived}) onSetArchived;
  final Product? initial;
  final List<String> knownCategories;

  @override
  State<ProductEditForm> createState() => _ProductEditFormState();
}

class _ProductEditFormState extends State<ProductEditForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _unitLabel;
  late final TextEditingController _price;
  late final TextEditingController _category;

  @override
  void initState() {
    super.initState();
    final Product? initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _unitLabel = TextEditingController(text: initial?.unitLabel ?? '');
    _price = TextEditingController(
      text: initial == null ? '' : Money.format(initial.currentPricePaise),
    );
    _category = TextEditingController(text: initial?.category ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _unitLabel.dispose();
    _price.dispose();
    _category.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final String category = _category.text.trim();
    widget.onSave(
      Product(
        id: widget.initial?.id,
        name: _name.text.trim(),
        unitLabel: _unitLabel.text.trim(),
        currentPricePaise: Money.parse(_price.text) ?? 0,
        category: category.isEmpty ? null : category,
        archived: widget.initial?.archived ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Product? initial = widget.initial;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          TextFormField(
            controller: _name,
            autofocus: initial == null,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (String? value) =>
                (value ?? '').trim().isEmpty ? 'Give it a name' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _unitLabel,
            decoration: const InputDecoration(
              labelText: 'Unit label',
              helperText: 'What one of them is called: bottle, pack, tub.',
            ),
            validator: (String? value) =>
                (value ?? '').trim().isEmpty ? 'Name the unit' : null,
          ),
          const SizedBox(height: 16),
          MoneyField(
            controller: _price,
            label: 'Current price',
            helper: 'Prefills new delivery lines. Past ones keep their price.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _category,
            decoration: const InputDecoration(
              labelText: 'Category (optional)',
            ),
          ),
          if (widget.knownCategories.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String name in widget.knownCategories)
                  ActionChip(
                    label: Text(name),
                    onPressed: () => setState(() => _category.text = name),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save product')),
          if (initial != null) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  widget.onSetArchived(archived: !initial.archived),
              child: Text(
                initial.archived ? 'Bring product back' : 'Archive product',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
