import 'dart:async';

import 'package:flutter/material.dart';

import '../constants.dart';
import '../providers/build_info.dart';
import '../providers/view_models.dart';
import 'confirm_dialog.dart';
import 'section_header.dart';

/// Asks before a restore, naming exactly what goes.
///
/// A restore is the one action in Hisaab that can lose real records, so the
/// dialog says so in figures rather than asking whether the user is sure.
Future<bool> confirmRestore(
  BuildContext context, {
  required int people,
  required int deliveries,
  required int expenses,
}) => confirm(
  context,
  title: 'Restore from a file',
  message:
      'Restoring replaces everything on this phone with the file you pick. '
      'The ${countLabel(people, 'person', plural: 'people')}, '
      '${countLabel(deliveries, 'delivery', plural: 'deliveries')} and '
      '${countLabel(expenses, 'expense')} recorded here now are gone, and '
      'they cannot be brought back.',
  actionLabel: 'Replace everything',
);

/// One setting the screen edits as free text.
class SettingField {
  const SettingField({
    required this.key,
    required this.label,
    required this.helper,
    this.lines = 3,
  });

  final String key;
  final String label;
  final String helper;
  final int lines;
}

/// Everything the owner can change.
///
/// The PDF header and footer and the message templates are plain text fields,
/// because the wording belongs to her and not to whoever wrote the app.
class SettingsView extends StatefulWidget {
  const SettingsView({
    required this.values,
    required this.themeMode,
    required this.onWrite,
    required this.onThemeModeChanged,
    required this.onBackup,
    required this.onRestore,
    super.key,
  });

  final Map<String, String> values;
  final ThemeMode themeMode;
  final Future<void> Function(String key, String value) onWrite;
  final Future<void> Function(ThemeMode mode) onThemeModeChanged;

  /// Null until the storage layer offers a backup, in which case the tiles say
  /// so rather than pretending to work.
  final VoidCallback? onBackup;
  final VoidCallback? onRestore;

  static const List<SettingField> pdfFields = <SettingField>[
    SettingField(
      key: SettingKeys.pdfHeader,
      label: 'PDF header',
      helper: 'Sits at the top of every statement you export.',
    ),
    SettingField(
      key: SettingKeys.pdfFooter,
      label: 'PDF footer',
      helper: 'Sits at the bottom, for a UPI line or a thank you.',
    ),
  ];

  static const List<SettingField> templateFields = <SettingField>[
    SettingField(
      key: SettingKeys.templateStatement,
      label: 'Statement message',
      helper: 'Sent with a full statement.',
    ),
    SettingField(
      key: SettingKeys.templateReminder,
      label: 'Reminder message',
      helper: 'Sent when a balance has been sitting a while.',
    ),
    SettingField(
      key: SettingKeys.templateReceipt,
      label: 'Receipt message',
      helper: 'Sent after you take a payment.',
    ),
    SettingField(
      key: SettingKeys.templateShoppingList,
      label: 'Shopping list message',
      helper: 'Sent when you place an order.',
    ),
    SettingField(
      key: SettingKeys.templateInStock,
      label: 'In stock message',
      helper: 'Sent when something someone asked for arrives.',
    ),
  ];

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};

  @override
  void initState() {
    super.initState();
    for (final SettingField field in <SettingField>[
      ...SettingsView.pdfFields,
      ...SettingsView.templateFields,
      const SettingField(
        key: SettingKeys.upiHandle,
        label: 'UPI handle',
        helper: '',
        lines: 1,
      ),
    ]) {
      _controllers[field.key] = TextEditingController(
        text: widget.values[field.key] ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(SettingField field) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: TextField(
      controller: _controllers[field.key],
      minLines: field.lines,
      maxLines: field.lines + 4,
      decoration: InputDecoration(
        labelText: field.label,
        helperText: field.helper.isEmpty ? null : field.helper,
        helperMaxLines: 2,
      ),
      onChanged: (String value) =>
          unawaited(widget.onWrite(field.key, value)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final VoidCallback? onBackup = widget.onBackup;
    final VoidCallback? onRestore = widget.onRestore;
    const String pending = 'Available once the storage layer is wired in.';

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        const SectionHeader(title: 'Statement PDF'),
        for (final SettingField field in SettingsView.pdfFields)
          _field(field),
        const SectionHeader(title: 'Messages'),
        for (final SettingField field in SettingsView.templateFields)
          _field(field),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _controllers[SettingKeys.upiHandle],
            decoration: const InputDecoration(
              labelText: 'UPI handle',
              helperText: 'Added to a payment request where you use one.',
            ),
            onChanged: (String value) =>
                unawaited(widget.onWrite(SettingKeys.upiHandle, value)),
          ),
        ),
        const SectionHeader(title: 'Theme'),
        RadioGroup<ThemeMode>(
          groupValue: widget.themeMode,
          onChanged: (ThemeMode? next) {
            if (next != null) unawaited(widget.onThemeModeChanged(next));
          },
          child: const Column(
            children: <Widget>[
              RadioListTile<ThemeMode>(
                value: ThemeMode.system,
                title: Text('Match device'),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                title: Text('Light'),
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                title: Text('Dark'),
              ),
            ],
          ),
        ),
        const SectionHeader(title: 'Backup'),
        ListTile(
          leading: const Icon(Icons.save_alt_outlined),
          title: const Text('Back up to a file'),
          subtitle: Text(
            onBackup == null
                ? pending
                : 'Writes one file you can copy off the phone yourself.',
          ),
          enabled: onBackup != null,
          onTap: onBackup,
        ),
        ListTile(
          leading: const Icon(Icons.restore_outlined),
          title: const Text('Restore from a file'),
          subtitle: Text(
            onRestore == null
                ? pending
                : 'Replaces everything on this phone with the file you pick.',
          ),
          enabled: onRestore != null,
          onTap: onRestore,
        ),
        const SectionHeader(title: 'About'),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Build'),
          subtitle: Text(BuildInfo.label),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Text(
            'Hisaab holds everything on this phone. It has no network code, '
            'so nothing leaves unless you share it yourself.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}
