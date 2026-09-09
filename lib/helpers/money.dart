import 'package:intl/intl.dart';

/// Money in Hisaab is an `int` count of paise. These helpers are the only
/// place that converts between that and something a person reads, so a
/// rounding rule can never differ between two screens.
abstract final class Money {
  static final NumberFormat _grouped = NumberFormat('#,##0', 'en_IN');
  static final NumberFormat _groupedWithPaise = NumberFormat('#,##0.00', 'en_IN');

  /// Formats paise for display, grouping thousands [per std-24 cl-22] and
  /// hiding a zero paise part, so 205000 reads "2,050" and 205050 reads
  /// "2,050.50".
  static String format(int paise) {
    final bool negative = paise < 0;
    final int abs = paise.abs();
    final String body = abs % 100 == 0
        ? _grouped.format(abs ~/ 100)
        : _groupedWithPaise.format(abs / 100);
    return negative ? '-$body' : body;
  }

  /// Formats paise with the rupee sign, for anywhere the unit is not already
  /// obvious from context.
  static String formatWithSymbol(int paise) {
    final String body = format(paise);
    return body.startsWith('-') ? '-₹${body.substring(1)}' : '₹$body';
  }

  /// Parses what a person typed into paise. Accepts grouping separators and an
  /// optional decimal part, and returns null rather than guessing on anything
  /// it cannot read.
  static int? parse(String input) {
    final String cleaned = input.replaceAll(',', '').replaceAll('₹', '').trim();
    if (cleaned.isEmpty) return null;
    final double? value = double.tryParse(cleaned);
    if (value == null) return null;
    return (value * 100).round();
  }
}
