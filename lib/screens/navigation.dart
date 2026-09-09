import 'dart:async';

import 'package:flutter/material.dart';

/// Pushes a screen without leaving an unawaited future behind, which the
/// analyzer treats as an error in this project.
void openScreen(BuildContext context, Widget screen) {
  unawaited(
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen)),
  );
}

/// Shows a short confirmation of something that already happened.
void say(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
