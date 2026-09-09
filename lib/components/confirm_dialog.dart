import 'package:flutter/material.dart';

/// Asks before something the user cannot undo.
///
/// The message names the action and its real consequence, never "Are you
/// sure?", and the buttons say the action rather than "Yes" and "No"
/// [per std-24].
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String actionLabel,
  String cancelLabel = 'Keep it',
  bool destructive = true,
}) async {
  final bool? answer = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      final ColorScheme colours = Theme.of(context).colorScheme;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: colours.error,
                    foregroundColor: colours.onError,
                  )
                : null,
            child: Text(actionLabel),
          ),
        ],
      );
    },
  );
  return answer ?? false;
}
