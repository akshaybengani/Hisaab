import 'package:flutter/material.dart';

import '../constants.dart';
import '../helpers/dates.dart';
import '../models/models.dart';
import 'empty_state.dart';
import 'money_field.dart';

/// Noting what someone asked for, before an order is placed.
class RequestForm extends StatefulWidget {
  const RequestForm({
    required this.people,
    required this.products,
    required this.onSave,
    required this.onAddPerson,
    required this.onAddProduct,
    super.key,
  });

  final List<Person> people;
  final List<Product> products;
  final ValueChanged<ProductRequest> onSave;
  final VoidCallback onAddPerson;
  final VoidCallback onAddProduct;

  @override
  State<RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<RequestForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _qty = TextEditingController(text: '1');
  final TextEditingController _forMember = TextEditingController();
  final TextEditingController _note = TextEditingController();
  int? _personId;
  int? _productId;

  @override
  void initState() {
    super.initState();
    _personId = widget.people.isNotEmpty ? widget.people.first.id : null;
    _productId = widget.products.isNotEmpty ? widget.products.first.id : null;
  }

  @override
  void dispose() {
    _qty.dispose();
    _forMember.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final int? personId = _personId;
    final int? productId = _productId;
    if (personId == null || productId == null) return;
    final String member = _forMember.text.trim();
    final String note = _note.text.trim();
    widget.onSave(
      ProductRequest(
        id: null,
        personId: personId,
        productId: productId,
        qty: int.tryParse(_qty.text.trim()) ?? 1,
        status: RequestStatus.pending,
        createdAt: Dates.today(),
        forMember: member.isEmpty ? null : member,
        note: note.isEmpty ? null : note,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.people.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        message:
            'A request belongs to somebody. Add the person first and their '
            'requests collect here.',
        actionLabel: 'Add person',
        onAction: widget.onAddPerson,
      );
    }
    if (widget.products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message:
            'A request is for a product, so add one first. Requests then '
            'collapse into a single shopping list.',
        actionLabel: 'Add product',
        onAction: widget.onAddProduct,
      );
    }
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          DropdownButtonFormField<int>(
            initialValue: _personId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Person'),
            items: <DropdownMenuItem<int>>[
              for (final Person person in widget.people)
                DropdownMenuItem<int>(
                  value: person.id,
                  child: Text(person.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (int? next) => setState(() => _personId = next),
            validator: (int? value) => value == null ? 'Pick a person' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _productId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product'),
            items: <DropdownMenuItem<int>>[
              for (final Product product in widget.products)
                DropdownMenuItem<int>(
                  value: product.id,
                  child: Text(product.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: (int? next) => setState(() => _productId = next),
            validator: (int? value) => value == null ? 'Pick a product' : null,
          ),
          const SizedBox(height: 16),
          QtyField(controller: _qty),
          const SizedBox(height: 16),
          TextFormField(
            controller: _forMember,
            decoration: const InputDecoration(
              labelText: 'For member (optional)',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save request')),
        ],
      ),
    );
  }
}
