import 'package:flutter/material.dart';

/// A titled band above a group of rows, with an optional figure on the right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String? trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 20, bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              style: text.titleSmall?.copyWith(color: colours.primary),
            ),
          ),
          if (trailing != null)
            Text(
              trailing,
              style: text.titleSmall?.copyWith(color: colours.primary),
            ),
        ],
      ),
    );
  }
}
