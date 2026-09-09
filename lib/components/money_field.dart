import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../helpers/money.dart';

/// A rupee amount field. Parsing goes through [Money.parse], so no screen
/// invents its own rounding rule.
class MoneyField extends StatelessWidget {
  const MoneyField({
    required this.controller,
    required this.label,
    this.autofocus = false,
    this.helper,
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final String? helper;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        prefixText: '₹ ',
      ),
      onChanged: onChanged,
      validator: (String? value) {
        if (value == null || value.trim().isEmpty) return 'Enter an amount';
        return Money.parse(value) == null ? 'That is not an amount' : null;
      },
    );
  }
}

/// A whole-number quantity field.
class QtyField extends StatelessWidget {
  const QtyField({
    required this.controller,
    this.label = 'Qty',
    this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
      ],
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
      validator: (String? value) {
        final int qty = int.tryParse((value ?? '').trim()) ?? 0;
        return qty > 0 ? null : 'At least 1';
      },
    );
  }
}
