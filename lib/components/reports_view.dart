import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'section_header.dart';

/// A month, in words.
///
/// Deliberately not [Dates.format]: that formats a day, and a report covering
/// September is not a report dated the first of it. The month picker and the
/// row that opens it are the only two places this is used.
final DateFormat _month = DateFormat('MMMM yyyy');

String monthLabel(DateTime month) => _month.format(month);

/// One document the app can produce.
///
/// [emptyReason] is what makes an empty book say so rather than hand someone a
/// PDF with nothing on it. Where it is set the row is disabled and the reason
/// is on screen, so the answer to "why is this greyed out" never needs asking.
class ReportEntry {
  const ReportEntry({
    required this.title,
    required this.summary,
    required this.icon,
    required this.actionLabel,
    required this.onProduce,
    this.emptyReason,
    this.choiceLabel,
    this.onChoose,
  });

  final String title;

  /// One line: what is in the document and when it is worth having.
  final String summary;

  final IconData icon;

  /// Names what happens, so a button never just says "go".
  final String actionLabel;

  final Future<void> Function() onProduce;

  /// Why there is nothing to report, or null where there is something.
  final String? emptyReason;

  /// A choice the document depends on, such as which month. Shown beside the
  /// action where both it and [onChoose] are set.
  final String? choiceLabel;
  final VoidCallback? onChoose;

  bool get hasSomethingToReport => emptyReason == null;
}

/// Every document Hisaab can produce, in one place.
///
/// Split by how it leaves the phone rather than by what it is about, because
/// that is the choice the owner is actually making: a file to keep or open
/// later, or a message to send someone now.
class ReportsView extends StatelessWidget {
  const ReportsView({required this.files, required this.messages, super.key});

  /// The PDFs and the CSV, which go out of the share sheet as attachments.
  final List<ReportEntry> files;

  /// The two that go out as text.
  final List<ReportEntry> messages;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Everything the book can print or send. Nothing leaves the phone '
            'until you pick where it goes.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SectionHeader(title: 'Files'),
        for (final ReportEntry entry in files) _ReportCard(entry: entry),
        const SectionHeader(title: 'Messages'),
        for (final ReportEntry entry in messages) _ReportCard(entry: entry),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.entry});

  final ReportEntry entry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool ready = entry.hasSomethingToReport;
    final String? reason = entry.emptyReason;
    final String? choiceLabel = entry.choiceLabel;
    final VoidCallback? onChoose = entry.onChoose;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  entry.icon,
                  color: ready ? colours.primary : colours.outline,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(entry.title, style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 8),
            Text(entry.summary, style: text.bodySmall),
            if (reason != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                reason,
                style: text.bodySmall?.copyWith(color: colours.error),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (choiceLabel != null && onChoose != null)
                  TextButton.icon(
                    onPressed: onChoose,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(choiceLabel),
                  ),
                FilledButton.tonalIcon(
                  onPressed: ready ? () => unawaited(entry.onProduce()) : null,
                  icon: const Icon(Icons.ios_share),
                  label: Text(entry.actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks which month a report covers, offering the last twelve.
///
/// A year of months is as far back as anyone reaches for a spending report,
/// and a list is quicker to hit than a calendar grid when the day never
/// matters. Returns null where the sheet was dismissed.
Future<DateTime?> pickMonth(
  BuildContext context, {
  required DateTime current,
  DateTime? now,
}) {
  final DateTime from = now ?? DateTime.now();
  final List<DateTime> months = <DateTime>[
    for (int back = 0; back < 12; back++)
      DateTime(from.year, from.month - back),
  ];
  return showDialog<DateTime>(
    context: context,
    builder: (BuildContext context) => SimpleDialog(
      title: const Text('Which month'),
      children: <Widget>[
        for (final DateTime month in months)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(month),
            child: Row(
              children: <Widget>[
                Expanded(child: Text(monthLabel(month))),
                if (month.year == current.year && month.month == current.month)
                  Icon(
                    Icons.check,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
