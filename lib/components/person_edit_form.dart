import 'package:flutter/material.dart';

import '../models/models.dart';

/// Adding or editing one person. A household is one record, because there is
/// only ever one payer. See spec-27 dec-5.
class PersonEditForm extends StatefulWidget {
  const PersonEditForm({
    required this.onSave,
    required this.onSetArchived,
    this.initial,
    super.key,
  });

  final ValueChanged<Person> onSave;
  final void Function({required bool archived}) onSetArchived;
  final Person? initial;

  @override
  State<PersonEditForm> createState() => _PersonEditFormState();
}

class _PersonEditFormState extends State<PersonEditForm> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _note;
  late bool _isHousehold;

  @override
  void initState() {
    super.initState();
    final Person? initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _phone = TextEditingController(text: initial?.phone ?? '');
    _note = TextEditingController(text: initial?.note ?? '');
    _isHousehold = initial?.isHousehold ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final String phone = _phone.text.trim();
    final String note = _note.text.trim();
    widget.onSave(
      Person(
        id: widget.initial?.id,
        name: _name.text.trim(),
        phone: phone.isEmpty ? null : phone,
        note: note.isEmpty ? null : note,
        isHousehold: _isHousehold,
        archived: widget.initial?.archived ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Person? initial = widget.initial;
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          TextFormField(
            controller: _name,
            autofocus: initial == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (String? value) =>
                (value ?? '').trim().isEmpty ? 'Give them a name' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (optional)',
              helperText: 'Lets a statement open straight in WhatsApp.',
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _isHousehold,
            onChanged: (bool on) => setState(() => _isHousehold = on),
            contentPadding: EdgeInsets.zero,
            title: const Text('One balance for the household'),
            subtitle: const Text(
              'Keeps a family on a single balance, with who took what noted '
              'on the delivery.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _save, child: const Text('Save person')),
          if (initial != null) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () =>
                  widget.onSetArchived(archived: !initial.archived),
              child: Text(
                initial.archived ? 'Bring person back' : 'Archive person',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
