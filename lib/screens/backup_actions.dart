import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../components/settings_view.dart';
import '../helpers/dates.dart';
import '../providers/app_state.dart';
import '../services/backup_service.dart';
import 'navigation.dart';

/// Export and restore, the only way a book survives a new phone.
///
/// Hisaab is excluded from Android cloud backup and device transfer on
/// purpose, so this file is the mitigation for the cost that choice carries.
/// A settings screen that cannot reach these is a data-loss bug, which is
/// exactly what shipped until an end-to-end test caught it.
abstract final class BackupActions {
  /// Writes the whole book to a file and hands it to the share sheet.
  static Future<void> export(BuildContext context, AppState state) async {
    final BackupService? service = state.repositories.backup;
    if (service == null) return;
    try {
      final Directory dir = Directory.systemTemp.createTempSync('hisaab-');
      final String stamp = Dates.today().toIso8601String().substring(0, 10);
      final File file = await service.exportToFile(
        '${dir.path}/hisaab-$stamp.json',
      );
      final BackupSummary summary = BackupService.summarise(
        await file.readAsString(),
      );
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: 'Hisaab backup, $stamp',
          text: '${summary.totalRows} rows from your book.',
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      say(context, 'Could not export the book: $error');
    }
  }

  /// Replaces the whole book with a file the user picks.
  ///
  /// Nothing is written until the confirmation names what goes, and the file
  /// is validated in full first, so a bad pick costs nothing.
  static Future<void> restore(BuildContext context, AppState state) async {
    final BackupService? service = state.repositories.backup;
    if (service == null) return;

    final PlatformFile? picked = await FilePicker.pickFile(
      dialogTitle: 'Pick a Hisaab backup',
      type: FileType.custom,
      allowedExtensions: <String>['json'],
    );
    final String? path = picked?.path;
    if (path == null) return;

    final BackupSummary incoming;
    try {
      incoming = BackupService.summarise(await File(path).readAsString());
    } on Object catch (error) {
      if (!context.mounted) return;
      say(context, 'That file is not a Hisaab backup: $error');
      return;
    }

    if (!context.mounted) return;
    final bool go = await confirmRestore(
      context,
      people: state.people.length,
      deliveries: state.deliveries.length,
      expenses: state.expenses.length,
    );
    if (!go) return;

    try {
      await service.importFile(path);
      await state.load();
      if (!context.mounted) return;
      say(context, 'Restored ${incoming.totalRows} rows.');
    } on Object catch (error) {
      if (!context.mounted) return;
      say(context, 'Could not restore that file: $error');
    }
  }
}
