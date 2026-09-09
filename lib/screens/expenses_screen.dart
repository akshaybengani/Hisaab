import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/expenses_view.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'categories_screen.dart';
import 'expense_edit_screen.dart';
import 'navigation.dart';

/// The owner's own spending.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return ExpensesView(
      expenses: state.expenses,
      categoriesById: state.categoriesById,
      onAddExpense: () => openScreen(context, const ExpenseEditScreen()),
      onTapExpense: (Expense expense) =>
          openScreen(context, ExpenseEditScreen(expense: expense)),
      onManageCategories: () => openScreen(context, const CategoriesScreen()),
    );
  }
}
