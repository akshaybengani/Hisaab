import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'components/app_drawer.dart';
import 'providers/app_state.dart';
import 'screens/backup_actions.dart';
import 'screens/categories_screen.dart';
import 'screens/deliver_screen.dart';
import 'screens/dues_screen.dart';
import 'screens/expense_edit_screen.dart';
import 'screens/expenses_screen.dart';
import 'screens/navigation.dart';
import 'screens/people_screen.dart';
import 'screens/products_screen.dart';
import 'screens/purchases_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/request_edit_screen.dart';
import 'screens/requests_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';

/// The navigation skeleton.
///
/// Four destinations plus a FAB. Recording a handover is the highest frequency
/// action by a wide margin, so it is the FAB rather than a tab, and it is
/// reachable from every destination. See spec-27 s-2.
///
/// The shell owns the app bar and the destinations are bodies, so a tab switch
/// cannot leave a stale title behind.
///
/// Everything opened now and then rather than every day sits behind the
/// hamburger, in [AppDrawer]. That used to be a three dot menu, which fits
/// five flat entries and stops fitting the moment there are six.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

enum _Destination {
  dues(
    'Dues',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
  ),
  requests('Requests', Icons.playlist_add_outlined, Icons.playlist_add),
  stock('Stock', Icons.inventory_2_outlined, Icons.inventory_2),
  expenses('Expenses', Icons.receipt_long_outlined, Icons.receipt_long);

  const _Destination(this.label, this.icon, this.selectedIcon);

  /// Title Case, because these are tab labels [per std-24].
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _AppShellState extends State<AppShell> {
  _Destination _current = _Destination.dues;

  static const List<Widget> _bodies = <Widget>[
    DuesScreen(),
    RequestsScreen(),
    StockScreen(),
    ExpensesScreen(),
  ];

  List<Widget> _actionsFor(_Destination destination) {
    switch (destination) {
      case _Destination.dues:
        return <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const PeopleScreen()),
            icon: const Icon(Icons.group_outlined),
            tooltip: 'People',
          ),
        ];
      case _Destination.requests:
        return <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const RequestEditScreen()),
            icon: const Icon(Icons.add),
            tooltip: 'Add request',
          ),
        ];
      case _Destination.stock:
        return <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const PurchasesScreen()),
            icon: const Icon(Icons.local_shipping_outlined),
            tooltip: 'Purchases',
          ),
        ];
      case _Destination.expenses:
        return <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const ExpenseEditScreen()),
            icon: const Icon(Icons.add),
            tooltip: 'Add expense',
          ),
        ];
    }
  }

  /// Opens a drawer destination.
  ///
  /// The pop closes the drawer, which the framework holds as a local history
  /// entry on this route rather than as a route of its own, so it never takes
  /// the shell with it.
  void _open(BuildContext context, DrawerDestination destination) {
    Navigator.of(context).pop();
    switch (destination) {
      case DrawerDestination.people:
        openScreen(context, const PeopleScreen());
      case DrawerDestination.products:
        openScreen(context, const ProductsScreen());
      case DrawerDestination.purchases:
        openScreen(context, const PurchasesScreen());
      case DrawerDestination.categories:
        openScreen(context, const CategoriesScreen());
      case DrawerDestination.reports:
        openScreen(context, const ReportsScreen());
      case DrawerDestination.settings:
        final AppState state = context.read<AppState>();
        openScreen(
          context,
          SettingsScreen(
            backup: () => BackupActions.export(context, state),
            restore: () => BackupActions.restore(context, state),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_current.label),
        actions: _actionsFor(_current),
      ),
      drawer: AppDrawer(onSelected: (DrawerDestination d) => _open(context, d)),
      body: IndexedStack(index: _current.index, children: _bodies),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openScreen(context, const DeliverScreen()),
        icon: const Icon(Icons.add_shopping_cart_outlined),
        label: const Text('Deliver'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _current.index,
        onDestinationSelected: (int i) =>
            setState(() => _current = _Destination.values[i]),
        destinations: <NavigationDestination>[
          for (final _Destination destination in _Destination.values)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
