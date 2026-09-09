import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/app_shell.dart';
import 'package:hisaab/main.dart';
import 'package:hisaab/providers/app_state.dart';

import 'support/harness.dart';

/// The app is pumped with a state built over the in-memory fake, never
/// through `openRepositories()`. That keeps the boot test off the storage
/// lane's path while still exercising the real widget tree.
void main() {
  testWidgets('the app boots to the shell with four destinations', (
    WidgetTester tester,
  ) async {
    await withQuietLogs(() async {
      final AppState state = await loadedState();
      await tester.pumpWidget(HisaabApp(state: state));
      await tester.pump();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.text('Dues'), findsWidgets);
      expect(find.text('Deliver'), findsOneWidget);
      for (final String label in <String>['Requests', 'Stock', 'Expenses']) {
        expect(
          find.text(label),
          findsWidgets,
          reason: '$label is a destination',
        );
      }
    });
  });

  testWidgets('the theme follows the setting the owner picked', (
    WidgetTester tester,
  ) async {
    await withQuietLogs(() async {
      final AppState state = await loadedState();
      await tester.pumpWidget(HisaabApp(state: state));
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.system,
      );

      await state.setThemeMode(ThemeMode.dark);
      await tester.pump();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
    });
  });
}
