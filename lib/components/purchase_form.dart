import 'package:flutter/material.dart';

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/view_models.dart';
import 'empty_state.dart';
import 'money_field.dart';

/// Adding a purchase.
///
/// The total paid is its own field, never the sum of the lines, because
/// shipping and offers make the two legitimately differ. The gap reads both
/// ways: paying over the lines is money the owner absorbed, and paying under
/// them is a discount she received. Only the first is offered to expenses,
/// because a saving is not a cost. See spec-27 dec-7.
class PurchaseForm extends StatefulWidget {
  const PurchaseForm({
    required this.products,
    required this.categories,
    required this.onSave,
    required this.onAddProduct,
    super.key,
  });

  final List<Product> products;
  final List<ExpenseCategory> categories;

  /// [absorbedExpense] is only ever non-null where the user ticked the offer,
  /// which is offered only where the total paid ran over the lines.
  final void Function(
    Purchase purchase,
    List<PurchaseItem> items, {
    Expense? absorbedExpense,
  })
  onSave;
  final VoidCallback onAddProduct;

  @override
  State<PurchaseForm> createState() => _PurchaseFormState();
}

class _CostDraft {
  _CostDraft({required this.productId, required int unitCostPaise})
    : qtyText = TextEditingController(text: '1'),
      costText = TextEditingController(text: Money.format(unitCostPaise));

  int productId;
  final TextEditingController qtyText;
  final TextEditingController costText;

  int get qty => int.tryParse(qtyText.text.trim()) ?? 0;
  int get unitCostPaise => Money.parse(costText.text) ?? 0;
  int get totalPaise => qty * unitCostPaise;

  void dispose() {
    qtyText.dispose();
    costText.dispose();
  }
}

class _PurchaseFormState extends State<PurchaseForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _vendor = TextEditingController();
  final TextEditingController _total = TextEditingController();
  final List<_CostDraft> _lines = <_CostDraft>[];
  DateTime _date = Dates.today();
  bool _writeGapToExpenses = false;
  int? _gapCategoryId;

  @override
  void initState() {
    super.initState();
    if (widget.products.isNotEmpty) _addLine();
  }

  @override
  void dispose() {
    for (final _CostDraft line in _lines) {
      line.dispose();
    }
    _vendor.dispose();
    _total.dispose();
    super.dispose();
  }

  void _addLine() {
    final Product product = widget.products.first;
    _lines.add(
      _CostDraft(
        productId: product.id ?? -1,
        unitCostPaise: product.currentPricePaise,
      ),
    );
  }

  Product? _productById(int id) {
    for (final Product product in widget.products) {
      if (product.id == id) return product;
    }
    return null;
  }

  PurchaseGap get _gap => PurchaseGap(
    lineTotalPaise: _lines.fold(
      0,
      (int sum, _CostDraft l) => sum + l.totalPaise,
    ),
    totalPaidPaise: Money.parse(_total.text) ?? 0,
  );

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final PurchaseGap gap = _gap;
    final String vendor = _vendor.text.trim();
    widget.onSave(
      Purchase(
        id: null,
        date: _date,
        totalPaidPaise: gap.totalPaidPaise,
        vendor: vendor.isEmpty ? null : vendor,
      ),
      <PurchaseItem>[
        for (final _CostDraft line in _lines)
          PurchaseItem(
            id: null,
            purchaseId: null,
            productId: line.productId,
            qty: line.qty,
            unitCostPaise: line.unitCostPaise,
          ),
      ],
      absorbedExpense: _writeGapToExpenses && gap.isAbsorbed
          ? Expense(
              id: null,
              date: _date,
              amountPaise: gap.absorbedPaise,
              categoryId: _gapCategoryId,
              note: vendor.isEmpty
                  ? 'Absorbed on an order'
                  : 'Absorbed on the $vendor order',
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.products.isEmpty) {
      return EmptyState(
        icon: Icons.inventory_2_outlined,
        message:
            'A purchase is made of product lines, so there has to be a '
            'product first. Add one and it becomes available here.',
        actionLabel: 'Add product',
        onAction: widget.onAddProduct,
      );
    }

    final TextTheme text = Theme.of(context).textTheme;
    final PurchaseGap gap = _gap;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          TextFormField(
            controller: _vendor,
            decoration: const InputDecoration(labelText: 'Vendor (optional)'),
          ),
          const SizedBox(height: 8),
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
            Card(
              key: ValueKey<_CostDraft>(_lines[index]),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _lines[index].productId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Product',
                            ),
                            items: <DropdownMenuItem<int>>[
                              for (final Product product in widget.products)
                                DropdownMenuItem<int>(
                                  value: product.id,
                                  child: Text(
                                    product.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (int? next) {
                              if (next == null) return;
                              final Product? product = _productById(next);
                              setState(() {
                                _lines[index].productId = next;
                                if (product != null) {
                                  _lines[index].costText.text = Money.format(
                                    product.currentPricePaise,
                                  );
                                }
                              });
                            },
                          ),
                        ),
                        if (_lines.length > 1)
                          IconButton(
                            onPressed: () => setState(
                              () => _lines.removeAt(index).dispose(),
                            ),
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
                            controller: _lines[index].qtyText,
                            onChanged: (String _) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MoneyField(
                            controller: _lines[index].costText,
                            label: 'Unit cost',
                            onChanged: (String _) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => setState(_addLine),
              icon: const Icon(Icons.add),
              label: const Text('Add line'),
            ),
          ),
          const SizedBox(height: 20),
          MoneyField(
            controller: _total,
            label: 'Total paid',
            helper: 'What actually left your account, shipping included.',
            onChanged: (String _) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('Lines add up to', style: text.bodyMedium),
                      ),
                      Text(
                        Money.formatWithSymbol(gap.lineTotalPaise),
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('Total paid', style: text.bodyMedium),
                      ),
                      Text(
                        Money.formatWithSymbol(gap.totalPaidPaise),
                        style: text.bodyMedium,
                      ),
                    ],
                  ),
                  if (gap.hasGap) ...<Widget>[
                    const Divider(),
                    Text(
                      gap.isAbsorbed
                          ? 'You absorbed ${Money.formatWithSymbol(gap.absorbedPaise)} '
                                'over the lines, so no unit price changes.'
                          : 'Discount received ${Money.formatWithSymbol(gap.absorbedPaise.abs())} '
                                'on this order, so no unit price changes.',
                      style: text.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Offered only where the gap cost her money. Writing a discount she
          // received into expenses would record a saving as a cost.
          if (gap.isAbsorbed) ...<Widget>[
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _writeGapToExpenses,
              onChanged: (bool? on) =>
                  setState(() => _writeGapToExpenses = on ?? false),
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Also record ${Money.formatWithSymbol(gap.absorbedPaise)} as an expense',
              ),
              subtitle: const Text(
                'Off by default, because a purchase and an expense are two '
                'different records.',
              ),
            ),
            if (_writeGapToExpenses && widget.categories.isNotEmpty)
              DropdownButtonFormField<int>(
                initialValue: _gapCategoryId,
                decoration: const InputDecoration(
                  labelText: 'Expense category (optional)',
                ),
                items: <DropdownMenuItem<int>>[
                  for (final ExpenseCategory category in widget.categories)
                    DropdownMenuItem<int>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (int? next) => setState(() => _gapCategoryId = next),
              ),
          ],
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save purchase')),
        ],
      ),
    );
  }
}
