import 'package:flutter/material.dart';

import '../models/models.dart';
import 'empty_state.dart';
import 'section_header.dart';

/// Managing expense categories. Archiving keeps old expenses readable, which
/// deleting would not.
class CategoriesView extends StatelessWidget {
  const CategoriesView({
    required this.categories,
    required this.onAddCategory,
    required this.onSetArchived,
    super.key,
  });

  final List<ExpenseCategory> categories;
  final VoidCallback onAddCategory;
  final void Function(ExpenseCategory category, {required bool archived})
  onSetArchived;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return EmptyState(
        icon: Icons.label_outline,
        message:
            'Categories group your expenses. Nothing is set up for you, so '
            'add the ones you actually use.',
        actionLabel: 'Add category',
        onAction: onAddCategory,
      );
    }

    final List<ExpenseCategory> active = categories
        .where((ExpenseCategory c) => !c.archived)
        .toList(growable: false);
    final List<ExpenseCategory> archived = categories
        .where((ExpenseCategory c) => c.archived)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        if (active.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'In use'),
          for (final ExpenseCategory category in active)
            ListTile(
              title: Text(category.name),
              trailing: _CategoryMenu(
                category: category,
                onSetArchived: onSetArchived,
              ),
            ),
        ],
        if (archived.isNotEmpty) ...<Widget>[
          const SectionHeader(title: 'Archived'),
          for (final ExpenseCategory category in archived)
            ListTile(
              title: Text(category.name),
              subtitle: const Text('Hidden from the expense form'),
              trailing: _CategoryMenu(
                category: category,
                onSetArchived: onSetArchived,
              ),
            ),
        ],
      ],
    );
  }
}

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({required this.category, required this.onSetArchived});

  final ExpenseCategory category;
  final void Function(ExpenseCategory category, {required bool archived})
  onSetArchived;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => onSetArchived(category, archived: !category.archived),
      child: Text(category.archived ? 'Bring back' : 'Archive'),
    );
  }
}
