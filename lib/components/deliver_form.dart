import 'package:flutter/material.dart';

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import 'empty_state.dart';
import 'money_field.dart';

/// Recording a handover.
///
/// Each line's price is prefilled from the product's current price and stays
/// editable, because the price that matters is the one agreed on the day. It
/// is snapshotted onto the line, so a later price edit never rewrites this
/// delivery. See spec-27 dec-2.
class DeliverForm extends StatefulWidget {
  const DeliverForm({
    required this.people,
    required this.products,
    required this.onSave,
    required this.onAddPerson,
    required this.onAddProduct,
    this.initialPersonId,
    super.key,
  });

  final List<Person> people;
  final List<Product> products;
  final void Function(Delivery delivery, List<DeliveryItem> items) onSave;
  final VoidCallback onAddPerson;
  final VoidCallback onAddProduct;
  final int? initialPersonId;

  @override
  State<DeliverForm> createState() => _DeliverFormState();
}

class _LineDraft {
  _LineDraft({required this.productId, required int pricePaise, this.qty = 1})
    : qtyText = TextEditingController(text: '$qty'),
      priceText = TextEditingController(text: Money.format(pricePaise));

  int productId;
  int qty;
  final TextEditingController qtyText;
  final TextEditingController priceText;

  int get unitPricePaise => Money.parse(priceText.text) ?? 0;
  int get quantity => int.tryParse(qtyText.text.trim()) ?? 0;
  int get totalPaise => quantity * unitPricePaise;

  void dispose() {
    qtyText.dispose();
    priceText.dispose();
  }
}

class _DeliverFormState extends State<DeliverForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _forMember = TextEditingController();
  final TextEditingController _note = TextEditingController();
  final List<_LineDraft> _lines = <_LineDraft>[];
  int? _personId;
  DateTime _date = Dates.today();

  @override
  void initState() {
    super.initState();
    _personId = widget.initialPersonId ??
        (widget.people.isNotEmpty ? widget.people.first.id : null);
    if (widget.products.isNotEmpty) _addLine();
  }

  @override
  void dispose() {
    for (final _LineDraft line in _lines) {
      line.dispose();
    }
    _forMember.dispose();
    _note.dispose();
    super.dispose();
  }

  void _addLine() {
    final Product product = widget.products.first;
    _lines.add(
      _LineDraft(
        productId: product.id ?? -1,
        pricePaise: product.currentPricePaise,
      ),
    );
  }

  Product? _productById(int id) {
    for (final Product product in widget.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  int get _totalPaise =>
      _lines.fold(0, (int sum, _LineDraft l) => sum + l.totalPaise);

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final int? personId = _personId;
    if (personId == null) return;
    final String member = _forMember.text.trim();
    final String note = _note.text.trim();
    widget.onSave(
      Delivery(
        id: null,
        personId: personId,
        date: _date,
        forMember: member.isEmpty ? null : member,
        note: note.isEmpty ? null : note,
      ),
      <DeliveryItem>[
        for (final _LineDraft line in _lines)
          DeliveryItem(
            id: null,
            deliveryId: null,
            productId: line.productId,
            qty: line.quantity,
            unitPricePaise: line.unitPricePaise,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.people.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        message:
            'A handover needs someone to hand it to. Add the person first '
            'and their balance starts from this delivery.',
        actionLabel: 'Add person',
        onAction: widget.onAddPerson,
      );
    }
    if (widget.products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message:
            'A handover needs a product with a price. Add one and its price '
            'prefills every delivery line from then on.',
        actionLabel: 'Add product',
        onAction: widget.onAddProduct,
      );
    }

    final TextTheme text = Theme.of(context).textTheme;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          DropdownButtonFormField<int>(
            initialValue: _personId,
            decoration: const InputDecoration(labelText: 'Person'),
            items: <DropdownMenuItem<int>>[
              for (final Person person in widget.people)
                DropdownMenuItem<int>(
                  value: person.id,
                  child: Text(person.name),
                ),
            ],
            onChanged: (int? next) => setState(() => _personId = next),
            validator: (int? value) => value == null ? 'Pick a person' : null,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text(Dates.format(_date)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: () async {
              final DateTime? picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _date = Dates.dayOnly(picked));
            },
          ),
          const SizedBox(height: 8),
          Text('Lines', style: text.titleSmall),
          const SizedBox(height: 8),
          for (int index = 0; index < _lines.length; index++)
            _LineCard(
              key: ValueKey<_LineDraft>(_lines[index]),
              // Every line reads the same product name until it is changed,
              // so the picker carries the only handle that names one line
              // rather than another.
              productKey: ValueKey<String>('delivery-line-product-$index'),
              line: _lines[index],
              products: widget.products,
              onProductChanged: (int productId) {
                final Product? product = _productById(productId);
                setState(() {
                  _lines[index].productId = productId;
                  if (product != null) {
                    _lines[index].priceText.text = Money.format(
                      product.currentPricePaise,
                    );
                  }
                });
              },
              onChanged: () => setState(() {}),
              onRemove: _lines.length == 1
                  ? null
                  : () => setState(() => _lines.removeAt(index).dispose()),
              unitLabel: _productById(_lines[index].productId)?.unitLabel ?? '',
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(_addLine),
              icon: const Icon(Icons.add),
              label: const Text('Add line'),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _forMember,
            decoration: const InputDecoration(
              labelText: 'For member (optional)',
              helperText:
                  'Who in the household actually took these, if it helps.',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text('Total', style: text.titleMedium)),
                  Text(
                    Money.formatWithSymbol(_totalPaise),
                    style: text.titleMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('Save delivery')),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.products,
    required this.unitLabel,
    required this.productKey,
    required this.onProductChanged,
    required this.onChanged,
    required this.onRemove,
    super.key,
  });

  final _LineDraft line;

  /// Names this line's product picker, which is otherwise indistinguishable
  /// from every other line's.
  final Key productKey;
  final List<Product> products;
  final String unitLabel;
  final ValueChanged<int> onProductChanged;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onRemove = this.onRemove;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: productKey,
                    initialValue: line.productId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: <DropdownMenuItem<int>>[
                      for (final Product product in products)
                        DropdownMenuItem<int>(
                          value: product.id,
                          child: Text(
                            product.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (int? next) {
                      if (next != null) onProductChanged(next);
                    },
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove line',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: QtyField(
                    controller: line.qtyText,
                    label: unitLabel.isEmpty ? 'Qty' : 'Qty ($unitLabel)',
                    onChanged: (String _) => onChanged(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MoneyField(
                    controller: line.priceText,
                    label: 'Unit price',
                    onChanged: (String _) => onChanged(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Line total ${Money.formatWithSymbol(line.totalPaise)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
