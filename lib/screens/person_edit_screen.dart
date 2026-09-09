import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/confirm_dialog.dart';
import '../components/person_edit_form.dart';
import '../models/models.dart';
import '../providers/app_state.dart';

/// Adding or editing one person.
class PersonEditScreen extends StatelessWidget {
  const PersonEditScreen({this.person, super.key});

  final Person? person;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.read<AppState>();
    final Person? person = this.person;
    return Scaffold(
      appBar: AppBar(
        title: Text(person == null ? 'Add person' : 'Edit person'),
      ),
      body: PersonEditForm(
        initial: person,
        onSave: (Person edited) async {
          await state.savePerson(edited);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
        onSetArchived: ({required bool archived}) async {
          final int? id = person?.id;
          if (id == null) return;
          if (archived) {
            final bool ok = await confirm(
              context,
              title: 'Archive ${person!.name}',
              message:
                  'Archiving hides ${person.name} from the pickers. Their '
                  'deliveries, payments and balance all stay exactly as they '
                  'are, and you can bring them back later.',
              actionLabel: 'Archive person',
              destructive: false,
            );
            if (!ok) return;
          }
          await state.setPersonArchived(id, archived: archived);
          if (!context.mounted) return;
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
