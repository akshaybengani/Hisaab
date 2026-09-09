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
import '../services/statement_pdf_service.dart';
import '../services/statement_text_service.dart';
import 'collect_screen.dart';
import 'navigation.dart';
import 'person_edit_screen.dart';

/// One person's statement, ledger and actions.
class PersonDetailScreen extends StatelessWidget {
  const PersonDetailScreen({required this.person, super.key});

  final Person person;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final Statement? statement = state.statementFor(person);

    return Scaffold(
      appBar: AppBar(
        title: Text(person.name),
        actions: <Widget>[
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
