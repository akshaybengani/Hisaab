import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/people_view.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'navigation.dart';
import 'person_detail_screen.dart';
import 'person_edit_screen.dart';

/// Everyone in the book.
class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('People'),
        actions: <Widget>[
          IconButton(
            onPressed: () => openScreen(context, const PersonEditScreen()),
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add person',
          ),
        ],
      ),
      body: PeopleView(
        people: state.people,
        onTapPerson: (Person person) =>
            openScreen(context, PersonDetailScreen(person: person)),
        onAddPerson: () => openScreen(context, const PersonEditScreen()),
      ),
    );
  }
}
