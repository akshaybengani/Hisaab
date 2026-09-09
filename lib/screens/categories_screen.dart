import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/categories_view.dart';
import '../components/confirm_dialog.dart';
import '../components/expenses_view.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

/// Managing and archiving expense categories.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: <Widget>[
          IconButton(
            onPressed: () => _add(context, state),
            icon: const Icon(Icons.add),
            tooltip: 'Add category',
          ),
        ],
      ),
      body: CategoriesView(
        categories: state.categories,
        onAddCategory: () => _add(context, state),
        onSetArchived: (ExpenseCategory category, {required bool archived}) =>
            _setArchived(context, state, category, archived: archived),
      ),
    );
  }

  Future<void> _add(BuildContext context, AppState state) async {
    final String? name = await askForName(
      context,
      title: 'New category',
      label: 'Category name',
      actionLabel: 'Create category',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await state.ensureCategory(name.trim());
  }

  Future<void> _setArchived(
    BuildContext context,
    AppState state,
    ExpenseCategory category, {
    required bool archived,
  }) async {
    final int? id = category.id;
    if (id == null) return;
    if (archived) {
      final bool ok = await confirm(
        context,
        title: 'Archive ${category.name}',
        message:
            'Archiving takes ${category.name} out of the expense form. Every '
            'expense already filed under it keeps showing it.',
        actionLabel: 'Archive category',
        destructive: false,
      );
      if (!ok || !context.mounted) return;
    }
    await state.setCategoryArchived(id, archived: archived);
  }
}
