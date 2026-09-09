import 'package:flutter/material.dart';

/// A short standing message, for the case where a figure could not be worked
/// out. Never used to say "nothing here": that is [EmptyState]'s job.
class Notice extends StatelessWidget {
  const Notice({required this.message, this.icon = Icons.error_outline, super.key});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        color: colours.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: colours.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colours.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
