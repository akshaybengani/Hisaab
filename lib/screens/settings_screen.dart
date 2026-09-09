import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/settings_view.dart';
import '../providers/app_state.dart';

/// Wording, theme, backup and the build number.
///
/// Backup and restore are handed in as callbacks. They stay null until a
/// storage layer offers them, and the tiles say so rather than pretending.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({this.backup, this.restore, super.key});

  final Future<void> Function()? backup;
  final Future<void> Function()? restore;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SettingsView(
        values: state.settings,
        themeMode: state.themeMode,
        onWrite: state.writeSetting,
        onThemeModeChanged: state.setThemeMode,
        onBackup: backup == null ? null : () => unawaited(backup!()),
        onRestore: restore == null ? null : () => _restore(context, state),
      ),
    );
  }

  Future<void> _restore(BuildContext context, AppState state) async {
    final Future<void> Function()? restore = this.restore;
    if (restore == null) return;
    final bool ok = await confirmRestore(
      context,
      people: state.people.length,
      deliveries: state.deliveries.length,
      expenses: state.expenses.length,
    );
    if (!ok) return;
    await restore();
  }
}
