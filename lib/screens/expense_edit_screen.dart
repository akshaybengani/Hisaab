import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/confirm_dialog.dart';
import '../components/expenses_view.dart';
import '../helpers/money.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'navigation.dart';

/// Adding or editing one expense.
class ExpenseEditScreen extends StatelessWidget {
  const ExpenseEditScreen({this.expense, super.key});

  final Expense? expense;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Expense? expense = this.expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(expense == null ? 'Add expense' : 'Edit expense'),
      ),
      body: ExpenseForm(
        initial: expense,
        categories: state.categories,
        onCreateCategory: state.ensureCategory,
        onSave: (Expense edited) async {
          await state.saveExpense(edited);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
        onDelete: expense?.id == null
            ? null
            : () => _delete(context, state, expense!),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    AppState state,
    Expense expense,
  ) async {
    final int? id = expense.id;
    if (id == null) return;
    final bool ok = await confirm(
      context,
      title: 'Delete this expense',
      message:
          'This removes ${Money.formatWithSymbol(expense.amountPaise)} from '
          'your monthly total for good. Nothing else changes.',
      actionLabel: 'Delete expense',
    );
    if (!ok || !context.mounted) return;
    await state.deleteExpense(id);
    if (!context.mounted) return;
    say(context, 'Expense deleted.');
    Navigator.of(context).pop();
  }
}
