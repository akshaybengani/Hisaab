import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/dues_view.dart';
import '../components/notice.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'collect_screen.dart';
import 'navigation.dart';
import 'people_screen.dart';
import 'person_edit_screen.dart';

/// The home destination. Reads the balances and hands them to [DuesView],
/// which is where all the layout lives.
class DuesScreen extends StatelessWidget {
  const DuesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    final List<PersonBalance>? balances = state.balances;
    if (balances == null) {
      return const Notice(
        message:
            'The balances could not be worked out from the records on this '
            'phone. Nothing has been changed.',
      );
    }
    return DuesView(
      balances: balances,
      onTapPerson: (PersonBalance balance) =>
          openScreen(context, CollectScreen(person: balance.person)),
      onAddPerson: () => openScreen(context, const PersonEditScreen()),
      onSeePeople: () => openScreen(context, const PeopleScreen()),
    );
  }
}
