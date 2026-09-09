import 'package:flutter/material.dart';

import '../helpers/dates.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import 'empty_state.dart';
import 'money_field.dart';
import 'section_header.dart';

/// The owner's own spending, with this month's total on top.
class ExpensesView extends StatelessWidget {
  const ExpensesView({
    required this.expenses,
    required this.categoriesById,
    required this.onAddExpense,
    required this.onTapExpense,
    required this.onManageCategories,
    this.month,
    super.key,
  });

  final List<Expense> expenses;
  final Map<int, ExpenseCategory> categoriesById;
  final VoidCallback onAddExpense;
  final ValueChanged<Expense> onTapExpense;
  final VoidCallback onManageCategories;

  /// The month the total covers. Defaults to the month showing on the clock,
  /// and is fixed in tests.
  final DateTime? month;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        message:
            'Expenses is your own spending, kept apart from what people owe '
            'you. Add the first one and a monthly total appears.',
        actionLabel: 'Add expense',
        onAction: onAddExpense,
        secondaryLabel: 'Manage categories',
        onSecondary: onManageCategories,
      );
    }

    final DateTime month = this.month ?? DateTime.now();
    final List<Expense> sorted = <Expense>[...expenses]
      ..sort((Expense a, Expense b) => b.date.compareTo(a.date));
    final int monthTotal = sorted
        .where(
          (Expense e) => e.date.year == month.year && e.date.month == month.month,
        )
        .fold(0, (int sum, Expense e) => sum + e.amountPaise);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        _MonthCard(monthTotalPaise: monthTotal, month: month),
        SectionHeader(
          title: 'All expenses',
          trailing: Money.formatWithSymbol(
            sorted.fold(0, (int sum, Expense e) => sum + e.amountPaise),
          ),
        ),
        for (final Expense expense in sorted)
          ListTile(
            title: Text(
              expense.note ??
                  categoriesById[expense.categoryId]?.name ??
                  'Expense',
            ),
            subtitle: Text(
              <String>[
                Dates.format(expense.date),
                if (categoriesById[expense.categoryId] != null)
                  categoriesById[expense.categoryId]!.name,
                if (expense.isFromPersonalUse) 'from stock used at home',
              ].join(', '),
            ),
            trailing: Text(Money.formatWithSymbol(expense.amountPaise)),
            onTap: () => onTapExpense(expense),
          ),
      ],
    );
  }
}

class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.monthTotalPaise, required this.month});

  final int monthTotalPaise;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      color: colours.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Spent this month',
              style: text.labelLarge?.copyWith(
                color: colours.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Money.formatWithSymbol(monthTotalPaise),
                style: text.displaySmall?.copyWith(
                  color: colours.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              'Up to ${Dates.format(month)}.',
              style: text.bodySmall?.copyWith(
                color: colours.onSecondaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adding or editing one expense, with a category picker that can create a
/// category without leaving the form. See spec-27 dec-14.
class ExpenseForm extends StatefulWidget {
  const ExpenseForm({
    required this.categories,
    required this.onSave,
    required this.onCreateCategory,
    this.initial,
    this.onDelete,
    super.key,
  });

  final List<ExpenseCategory> categories;
  final ValueChanged<Expense> onSave;

  /// Returns the id of the category, existing or new.
  final Future<int?> Function(String name) onCreateCategory;

  final Expense? initial;
  final VoidCallback? onDelete;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late DateTime _date;
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    final Expense? initial = widget.initial;
    _amount = TextEditingController(
      text: initial == null ? '' : Money.format(initial.amountPaise),
    );
    _note = TextEditingController(text: initial?.note ?? '');
    _date = initial?.date ?? Dates.today();
    _categoryId = initial?.categoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _createCategory() async {
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _NameDialog(
        title: 'New category',
        label: 'Category name',
        actionLabel: 'Create category',
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final int? id = await widget.onCreateCategory(name.trim());
    if (!mounted || id == null) return;
    setState(() => _categoryId = id);
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final String note = _note.text.trim();
    widget.onSave(
      Expense(
        id: widget.initial?.id,
        date: _date,
        amountPaise: Money.parse(_amount.text) ?? 0,
        categoryId: _categoryId,
        note: note.isEmpty ? null : note,
        stockAdjustmentId: widget.initial?.stockAdjustmentId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onDelete = widget.onDelete;
    final List<ExpenseCategory> pickable = widget.categories
        .where(
          (ExpenseCategory c) => !c.archived || c.id == _categoryId,
        )
        .toList(growable: false);
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          MoneyField(controller: _amount, label: 'Amount', autofocus: true),
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
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: <DropdownMenuItem<int>>[
                    for (final ExpenseCategory category in pickable)
                      DropdownMenuItem<int>(
                        value: category.id,
                        child: Text(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (int? next) => setState(() => _categoryId = next),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _createCategory,
                icon: const Icon(Icons.add),
                tooltip: 'New category',
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save expense')),
          if (onDelete != null) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onDelete,
              child: const Text('Delete expense'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A one-field dialog, used wherever a name is all that is needed.
class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
  });

  final String title;
  final String label;
  final String actionLabel;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _name,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (String value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

/// Asks for a name. Exposed so the categories screen can reuse the dialog.
Future<String?> askForName(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) =>
      _NameDialog(title: title, label: label, actionLabel: actionLabel),
);
