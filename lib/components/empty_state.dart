import 'package:flutter/material.dart';

/// What a list surface shows before anything exists.
///
/// Nothing in Hisaab is seeded, so every list is empty the first time it is
/// opened. That is the moment an app gets abandoned, so an empty state names
/// what the surface is for and offers the next action inline. A bare "no
/// items" is never enough.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    super.key,
  });

  final IconData icon;

  /// A full sentence naming what this surface is for.
  final String message;

  /// The action itself, with no trailing full stop [per std-24].
  final String actionLabel;
  final VoidCallback onAction;

  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String? secondaryLabel = this.secondaryLabel;
    final VoidCallback? onSecondary = this.onSecondary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 48, color: colours.primary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
            if (secondaryLabel != null && onSecondary != null) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            ],
          ],
        ),
      ),
    );
  }
}
