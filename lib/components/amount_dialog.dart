import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/money.dart';

/// Asks for a rupee amount and an optional note.
Future<({int paise, String? note})?> askForAmount(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String? helper,
  String noteLabel = 'Note (optional)',
}) => showDialog<({int paise, String? note})>(
  context: context,
  builder: (BuildContext context) => _AmountDialog(
    title: title,
    label: label,
    actionLabel: actionLabel,
    helper: helper,
    noteLabel: noteLabel,
  ),
);

class _AmountDialog extends StatefulWidget {
  const _AmountDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
    required this.noteLabel,
    this.helper,
  });

  final String title;
  final String label;
  final String actionLabel;
  final String noteLabel;
  final String? helper;

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final int? paise = Money.parse(_amount.text);
    if (paise == null || paise <= 0) {
      setState(() => _error = 'Enter an amount above zero');
      return;
    }
    final String note = _note.text.trim();
    Navigator.of(context).pop((paise: paise, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: widget.label,
              prefixText: '₹ ',
              helperText: widget.helper,
              helperMaxLines: 3,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: widget.noteLabel),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}

/// Asks for a whole number, for a quantity or a physical count.
Future<int?> askForCount(
  BuildContext context, {
  required String title,
  required String label,
  required String actionLabel,
  String? helper,
  int? initial,
}) => showDialog<int>(
  context: context,
  builder: (BuildContext context) => _CountDialog(
    title: title,
    label: label,
    actionLabel: actionLabel,
    helper: helper,
    initial: initial,
  ),
);

class _CountDialog extends StatefulWidget {
  const _CountDialog({
    required this.title,
    required this.label,
    required this.actionLabel,
    this.helper,
    this.initial,
  });

  final String title;
  final String label;
  final String actionLabel;
  final String? helper;
  final int? initial;

  @override
  State<_CountDialog> createState() => _CountDialogState();
}

class _CountDialogState extends State<_CountDialog> {
  late final TextEditingController _count = TextEditingController(
    text: widget.initial == null ? '' : '${widget.initial}',
  );
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  void _submit() {
    final int? value = int.tryParse(_count.text.trim());
    if (value == null || value < 0) {
      setState(() => _error = 'Enter a whole number');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _count,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
        ],
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helper,
          helperMaxLines: 3,
          errorText: _error,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
