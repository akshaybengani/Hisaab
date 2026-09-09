import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../components/amount_dialog.dart';
import '../components/notice.dart';
import '../components/person_detail_view.dart';
import '../constants.dart';
import '../helpers/dates.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/share_service.dart';
import '../services/statement_csv_service.dart';
import '../services/statement_pdf_service.dart';
import '../services/statement_text_service.dart';
import 'collect_screen.dart';
import 'navigation.dart';
import 'person_edit_screen.dart';

/// What the app bar menu can produce for one person.
enum _PersonAction { reminder, receipt, spreadsheet }

/// One person's statement, ledger and actions.
class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({
    required this.person,
    this.share = const ShareService(),
    super.key,
  });

  final Person person;

  /// The one way out of the app, injected so a test can read the message that
  /// would have been sent instead of standing up a method channel.
  final ShareService share;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Statement? statement = state.statementFor(person);

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: <Widget>[
          if (statement != null)
            PopupMenuButton<_PersonAction>(
              tooltip: 'Send and share',
              icon: const Icon(Icons.send_outlined),
              onSelected: (_PersonAction choice) =>
                  unawaited(_send(state, statement, choice)),
              itemBuilder: (BuildContext context) =>
                  <PopupMenuEntry<_PersonAction>>[
                    // A nudge only makes sense to someone who is behind.
                    // Sending one to a person who owes nothing, or who is in
                    // credit, is the kind of message that ends a favour.
                    if (statement.netPaise > 0)
                      const PopupMenuItem<_PersonAction>(
                        value: _PersonAction.reminder,
                        child: Text('Send a reminder'),
                      ),
                    const PopupMenuItem<_PersonAction>(
                      value: _PersonAction.receipt,
                      child: Text('Send a receipt'),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem<_PersonAction>(
                      value: _PersonAction.spreadsheet,
                      child: Text('Share as spreadsheet'),
                    ),
                  ],
            ),
          IconButton(
            onPressed: () =>
                openScreen(context, PersonEditScreen(person: person)),
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit person',
          ),
        ],
      ),
      body: statement == null
          ? const Notice(
              message:
                  'This statement could not be worked out from the records '
                  'on this phone. Nothing has been changed.',
            )
          : PersonDetailView(
              statement: statement,
              onCollect: () =>
                  openScreen(context, CollectScreen(person: person)),
              onLendCash: () => _lendCash(context, state),
              onShareText: () => _shareText(state, statement),
              onSharePdf: () => _sharePdf(state, statement),
            ),
    );
  }

  Future<void> _lendCash(BuildContext context, AppState state) async {
    final int? id = person.id;
    if (id == null) return;
    final ({int paise, String? note})? answer = await askForAmount(
      context,
      title: 'Lend cash to ${person.name}',
      label: 'Amount',
      actionLabel: 'Record loan',
      helper:
          'Kept apart from product dues, so a product payment can never pay '
          'it down.',
    );
    if (answer == null || !context.mounted) return;
    await state.recordMoney(
      MoneyEntry(
        id: null,
        personId: id,
        date: Dates.today(),
        amountPaise: answer.paise,
        direction: MoneyDirection.outgoing,
        kind: MoneyKind.cashLent,
        note: answer.note,
      ),
    );
    if (!context.mounted) return;
    say(context, 'Cash loan recorded.');
  }

  /// The two messages and the spreadsheet.
  ///
  /// A message carries the user's own wording out of `app_settings` and goes
  /// straight into a WhatsApp chat where a number is saved. The CSV is a file,
  /// so it can only go to the share sheet.
  Future<void> _send(
    AppState state,
    Statement statement,
    _PersonAction choice,
  ) async {
    switch (choice) {
      case _PersonAction.reminder:
        await share.sendText(
          person,
          await StatementTextService(
            state.repositories.settings,
          ).reminder(statement),
        );
      case _PersonAction.receipt:
        await share.sendText(
          person,
          await StatementTextService(
            state.repositories.settings,
          ).receipt(statement),
        );
      case _PersonAction.spreadsheet:
        final Directory folder = Directory.systemTemp.createTempSync('hisaab-');
        final File file = await StatementCsvService.toFile(
          '${folder.path}/statement-${person.name.toLowerCase()}.csv',
          StatementCsvService.statement(statement),
        );
        await share.sendFile(file, subject: 'Statement for ${person.name}');
    }
  }

  Future<void> _shareText(AppState state, Statement statement) async {
    final String body = await StatementTextService(
      state.repositories.settings,
    ).statement(statement);
    await SharePlus.instance.share(
      ShareParams(text: body, subject: 'Statement for ${person.name}'),
    );
  }

  Future<void> _sharePdf(AppState state, Statement statement) async {
    final StatementPdfService pdf = await StatementPdfService.load(
      settings: state.repositories.settings,
    );
    final Uint8List bytes = await pdf.render(
      StatementPdfService.statementReport(
        statement,
        upi: state.setting(SettingKeys.upiHandle),
      ),
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'statement-${person.name.toLowerCase()}.pdf',
    );
  }
}
