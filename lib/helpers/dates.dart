import 'package:intl/intl.dart';

/// Date handling for Hisaab. Every stored date is an ISO 8601 string, and
/// day-granularity dates are normalised to local midnight so two entries made
/// on the same day always compare equal.
abstract final class Dates {
  static final DateFormat _display = DateFormat('d MMM yyyy');
  static final DateFormat _displayShort = DateFormat('d MMM');

  /// Strips the time part, keeping the local calendar day.
  static DateTime dayOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime today() => dayOnly(DateTime.now());

  /// The display format the whole app uses [per std-24 cl-26]: "9 Sep 2026",
  /// no leading zero, no comma, no ordinal.
  static String format(DateTime value) => _display.format(value);

  /// Drops the year, for lists where every row is obviously recent.
  static String formatShort(DateTime value) => _displayShort.format(value);

  static String toStorage(DateTime value) => value.toIso8601String();

  static DateTime fromStorage(String value) => DateTime.parse(value);

  /// Whole days between two dates, ignoring any time part.
  static int daysBetween(DateTime from, DateTime to) =>
      dayOnly(to).difference(dayOnly(from)).inDays;

  /// A person-readable age, for the requests list where staleness matters.
  static String ageLabel(DateTime since, {DateTime? now}) {
    final int days = daysBetween(since, now ?? DateTime.now());
    if (days <= 0) return 'today';
    if (days == 1) return '1 day';
    return '$days days';
  }
}
