import 'package:flutter/material.dart';

/// The surfaces that live behind the hamburger.
///
/// The bottom bar keeps the four things the book owner touches every day and
/// Deliver stays the floating button. Everything here is opened now and then,
/// which is exactly what a drawer is for.
enum DrawerDestination {
  people('People', Icons.group_outlined, Icons.group),
  products('Products', Icons.local_mall_outlined, Icons.local_mall),
  purchases('Purchases', Icons.local_shipping_outlined, Icons.local_shipping),
  categories('Categories', Icons.sell_outlined, Icons.sell),
  reports('Reports', Icons.description_outlined, Icons.description),
  settings('Settings', Icons.settings_outlined, Icons.settings);

  const DrawerDestination(this.label, this.icon, this.selectedIcon);

  /// Title Case, because these read as the names of places [per std-24].
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// One titled group of destinations.
class _DrawerGroup {
  const _DrawerGroup(this.title, this.destinations);

  /// Null where the group needs no heading, which is the lone tail entry.
  final String? title;
  final List<DrawerDestination> destinations;
}

/// The navigation drawer.
///
/// Grouped rather than flat: a list of six unrelated words is a list to read
/// every time, and three short groups are a shape to remember. The order of
/// [DrawerDestination.values] is the order the groups lay them out in, which
/// is what keeps the index Material hands back meaning what it says.
class AppDrawer extends StatelessWidget {
  const AppDrawer({required this.onSelected, super.key});

  final void Function(DrawerDestination destination) onSelected;

  static const List<_DrawerGroup> _groups = <_DrawerGroup>[
    _DrawerGroup('The book', <DrawerDestination>[
      DrawerDestination.people,
      DrawerDestination.products,
    ]),
    _DrawerGroup('Buying and spending', <DrawerDestination>[
      DrawerDestination.purchases,
      DrawerDestination.categories,
    ]),
    _DrawerGroup('Documents', <DrawerDestination>[DrawerDestination.reports]),
    _DrawerGroup(null, <DrawerDestination>[DrawerDestination.settings]),
  ];

  /// Flattened in the order the drawer paints them, so index N back from
  /// Material is this list's Nth entry.
  static List<DrawerDestination> get ordered => <DrawerDestination>[
    for (final _DrawerGroup group in _groups) ...group.destinations,
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final List<Widget> children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Hisaab',
              style: text.headlineSmall?.copyWith(color: colours.primary),
            ),
            const SizedBox(height: 4),
            Text('The rest of the book', style: text.bodySmall),
          ],
        ),
      ),
    ];

    for (int i = 0; i < _groups.length; i++) {
      final _DrawerGroup group = _groups[i];
      final String? title = group.title;
      if (i > 0) {
        children.add(const Divider(indent: 28, endIndent: 28, height: 24));
      }
      if (title != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 16, 8),
            child: Text(
              title,
              style: text.titleSmall?.copyWith(color: colours.primary),
            ),
          ),
        );
      }
      for (final DrawerDestination destination in group.destinations) {
        children.add(
          NavigationDrawerDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: Text(destination.label),
          ),
        );
      }
    }

    return NavigationDrawer(
      // Nothing here is the surface behind the drawer, so nothing is current.
      selectedIndex: null,
      onDestinationSelected: (int index) => onSelected(ordered[index]),
      children: children,
    );
  }
}
