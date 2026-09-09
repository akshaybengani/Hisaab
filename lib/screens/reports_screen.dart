import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../components/notice.dart';
import '../components/reports_view.dart';
import '../helpers/dates.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../services/share_service.dart';
import '../services/statement_csv_service.dart';
import '../services/statement_pdf_service.dart';
import '../services/statement_text_service.dart';
import 'navigation.dart';

/// Every document the book can produce, on one screen.
///
/// Each renderer under `lib/services/` used to be reachable from nowhere,
/// which is how a working PDF and a working CSV sat in the app for weeks
/// without a way to open either. `test/reports_test.dart` guards that with a
/// reachability test, so a document that stops being wired here fails a test
/// rather than quietly disappearing.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({this.now, this.share = const ShareService(), super.key});

  /// Fixed in tests, so which month a report opens on and what date it is
  /// stamped with do not depend on the clock.
  final DateTime? now;

  /// The one way out of the app, injected so a test can read the file or the
  /// message that would have gone out instead of standing up a method channel.
  final ShareService share;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  /// Which month the expense report covers. The current one to start with,
  /// since that is the one being asked about nine times out of ten.
  late DateTime _month = DateTime(_now().year, _now().month);

  DateTime _now() => widget.now ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<PersonBalance>? balances = state.balances;
    final List<StockLevel>? levels = state.stockLevels;

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: balances == null || levels == null
          ? const Notice(
              message:
                  'The figures behind these documents could not be worked out '
                  'from the records on this phone, so nothing can be produced '
                  'yet.',
            )
          : ReportsView(
              files: _files(state, balances, levels),
              messages: _messages(state, levels),
            ),
    );
  }

  // ------------------------------------------------------------------ rows

  List<ReportEntry> _files(
    AppState state,
    List<PersonBalance> balances,
    List<StockLevel> levels,
  ) {
    final bool anythingOpen = balances.any(
      (PersonBalance balance) => balance.netPaise != 0,
    );
    final List<Expense> expenses = _expensesInMonth(state);
    final List<PurchaseWithItems> purchases = _purchasesInMonth(state);

    return <ReportEntry>[
      ReportEntry(
        title: 'Dues summary',
        summary:
            'Everyone who owes you and everyone you owe, on one page. The '
            'sheet to carry on a collection round.',
        icon: Icons.picture_as_pdf_outlined,
        actionLabel: 'Share PDF',
        emptyReason: anythingOpen
            ? null
            : 'Every balance is settled, so the page would be empty',
        onProduce: () => _sharePdf(
          state,
          StatementPdfService.duesReport(balances, generatedAt: DateTime.now()),
          'dues-${_stamp()}.pdf',
        ),
      ),
      ReportEntry(
        title: 'Stock report',
        summary:
            'What is on hand, product by product, valued at what it would '
            'sell for today. The sheet to check a shelf against.',
        icon: Icons.picture_as_pdf_outlined,
        actionLabel: 'Share PDF',
        emptyReason: levels.isEmpty
            ? 'No products in the catalogue yet, so there is nothing to count'
            : null,
        onProduce: () => _sharePdf(
          state,
          StatementPdfService.stockReport(levels, generatedAt: _now()),
          'stock-${_stamp()}.pdf',
        ),
      ),
      ReportEntry(
        title: 'Monthly expenses',
        summary:
            'One month of spending by category, with the orders placed in the '
            'same month underneath. For working out where the money went.',
        icon: Icons.picture_as_pdf_outlined,
        actionLabel: 'Share PDF',
        choiceLabel: monthLabel(_month),
        onChoose: () => unawaited(_chooseMonth()),
        emptyReason: expenses.isEmpty && purchases.isEmpty
            ? 'Nothing was recorded in ${monthLabel(_month)}'
            : null,
        onProduce: () => _sharePdf(
          state,
          StatementPdfService.monthlyExpenseReport(
            year: _month.year,
            month: _month.month,
            expenses: expenses,
            categoryNames: <int, String>{
              for (final ExpenseCategory category in state.categories)
                if (category.id != null) category.id!: category.name,
            },
            purchases: purchases,
          ),
          'expenses-${_month.year}-${_two(_month.month)}.pdf',
        ),
      ),
      ReportEntry(
        title: 'Dues list',
        summary:
            'Every balance as a spreadsheet, paise column included, for '
            'adding a column up yourself.',
        icon: Icons.table_chart_outlined,
        actionLabel: 'Share CSV',
        emptyReason: balances.isEmpty
            ? 'Nobody is in the book yet, so the file would hold only headings'
            : null,
        onProduce: () => _shareCsv(
          StatementCsvService.dues(balances),
          'dues-${_stamp()}.csv',
        ),
      ),
    ];
  }

  List<ReportEntry> _messages(AppState state, List<StockLevel> levels) {
    final List<ShoppingListLine>? shopping = state.shoppingListFor(
      state.pendingRequests,
    );

    return <ReportEntry>[
      ReportEntry(
        title: 'Shopping list',
        summary:
            'Every pending request collapsed to one line per product, which '
            'is what actually gets typed into an order.',
        icon: Icons.shopping_basket_outlined,
        actionLabel: 'Share as text',
        emptyReason: switch (shopping) {
          null =>
            'The list could not be worked out from the records on this phone',
          final List<ShoppingListLine> lines when lines.isEmpty =>
            'No requests are pending, so the list would be empty',
          _ => null,
        },
        onProduce: () =>
            _shareShoppingList(state, shopping ?? const <ShoppingListLine>[]),
      ),
      ReportEntry(
        title: 'What is in stock now',
        summary:
            'The current stock list as a message, for the question that gets '
            'asked most over WhatsApp.',
        icon: Icons.inventory_2_outlined,
        actionLabel: 'Share as text',
        emptyReason: levels.isEmpty
            ? 'No products in the catalogue yet, so there is nothing to list'
            : null,
        onProduce: () => _shareInStock(state, levels),
      ),
    ];
  }

  // -------------------------------------------------------------- producing

  Future<void> _sharePdf(
    AppState state,
    PdfReport report,
    String filename,
  ) async {
    try {
      final StatementPdfService pdf = await StatementPdfService.load(
        settings: state.repositories.settings,
      );
      final Uint8List bytes = await pdf.render(report);
      await Printing.sharePdf(bytes: bytes, filename: filename);
    } on Object catch (error) {
      _blame('produce that PDF', error);
    }
  }

  Future<void> _shareCsv(String content, String filename) async {
    try {
      final Directory folder = Directory.systemTemp.createTempSync('hisaab-');
      final File file = await StatementCsvService.toFile(
        '${folder.path}/$filename',
        content,
      );
      await widget.share.sendFile(file, subject: 'Dues from Hisaab');
    } on Object catch (error) {
      _blame('write that file', error);
    }
  }

  Future<void> _shareShoppingList(
    AppState state,
    List<ShoppingListLine> lines,
  ) async {
    try {
      int estimate = 0;
      for (final ShoppingListLine line in lines) {
        final Product? product = state.productsById[line.productId];
        if (product != null) estimate += line.qty * product.currentPricePaise;
      }
      final String message = await StatementTextService(
        state.repositories.settings,
      ).shoppingList(lines, estimatedTotalPaise: estimate);
      await widget.share.sendBroadcast(message);
    } on Object catch (error) {
      _blame('build that list', error);
    }
  }

  Future<void> _shareInStock(AppState state, List<StockLevel> levels) async {
    try {
      final String message = await StatementTextService(
        state.repositories.settings,
      ).inStock(levels);
      await widget.share.sendBroadcast(message);
    } on Object catch (error) {
      _blame('build that list', error);
    }
  }

  Future<void> _chooseMonth() async {
    final DateTime? picked = await pickMonth(
      context,
      current: _month,
      now: _now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _month = picked);
  }

  void _blame(String what, Object error) {
    if (!mounted) return;
    say(context, 'Could not $what: $error');
  }

  // ------------------------------------------------------------------ data

  List<Expense> _expensesInMonth(AppState state) => <Expense>[
    for (final Expense expense in state.expenses)
      if (expense.date.year == _month.year &&
          expense.date.month == _month.month)
        expense,
  ];

  List<PurchaseWithItems> _purchasesInMonth(AppState state) =>
      <PurchaseWithItems>[
        for (final PurchaseWithItems purchase in state.purchases)
          if (purchase.purchase.date.year == _month.year &&
              purchase.purchase.date.month == _month.month)
            purchase,
      ];

  String _stamp() => Dates.dayOnly(_now()).toIso8601String().substring(0, 10);

  static String _two(int value) => value.toString().padLeft(2, '0');
}
