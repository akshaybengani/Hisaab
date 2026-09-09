import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_shell.dart';
import 'providers/app_state.dart';
import 'repositories/factory.dart';
import 'theme/app_theme.dart';

/// Hisaab holds no network code of any kind, and the release manifest declares
/// no INTERNET permission. See spec-27 dec-10.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final AppState state = AppState(await openRepositories());
  await state.load();
  runApp(HisaabApp(state: state));
}

/// The app, taking its state from outside so a test can pump it against an
/// in-memory fake without opening a database.
class HisaabApp extends StatelessWidget {
  const HisaabApp({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: Consumer<AppState>(
        builder: (BuildContext context, AppState state, Widget? child) {
          return MaterialApp(
            title: 'Hisaab',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: state.themeMode,
            debugShowCheckedModeBanner: false,
            home: const AppShell(),
          );
        },
      ),
    );
  }
}
