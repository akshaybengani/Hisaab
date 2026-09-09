import 'package:flutter/material.dart';

import '../models/models.dart';
import 'empty_state.dart';

/// Everyone in the book, archived ones marked rather than hidden away.
class PeopleView extends StatelessWidget {
  const PeopleView({
    required this.people,
    required this.onTapPerson,
    required this.onAddPerson,
    super.key,
  });

  final List<Person> people;
  final ValueChanged<Person> onTapPerson;
  final VoidCallback onAddPerson;

  @override
  Widget build(BuildContext context) {
    if (people.isEmpty) {
      return EmptyState(
        icon: Icons.group_outlined,
        message:
            'People holds everyone you hand products to or lend cash to. '
            'Add the first one and their balance builds itself.',
        actionLabel: 'Add person',
        onAction: onAddPerson,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: people.length,
      itemBuilder: (BuildContext context, int index) {
        final Person person = people[index];
        final List<String> parts = <String>[
          if (person.phone != null && person.phone!.isNotEmpty) person.phone!,
          if (person.isHousehold) 'household',
          if (person.archived) 'archived',
        ];
        return ListTile(
          leading: CircleAvatar(
            child: Text(
              person.name.isEmpty ? '?' : person.name.characters.first,
            ),
          ),
          title: Text(person.name),
          subtitle: parts.isEmpty ? null : Text(parts.join(', ')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTapPerson(person),
        );
      },
    );
  }
}
