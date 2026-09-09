/// Search for every list surface in the app.
///
/// The app ships empty and grows. At fifty people and thirty products a list
/// stops being scannable, so every list gets the same field, the same
/// matching, and the same no match state. One widget, because two would drift.
///
/// The query lives in [SearchScope]'s own state. It is deliberately not in
/// `AppState` and not in a provider: it is throwaway view state, and a book
/// this size filters inside a build without anyone noticing.
library;

import 'package:flutter/material.dart';

final RegExp _whitespace = RegExp(r'\s+');
final RegExp _digitsOnly = RegExp(r'^[0-9]+$');
final RegExp _notDigits = RegExp(r'[^0-9]');

/// Splits what was typed into terms, lower case, with the whitespace dropped.
List<String> searchTerms(String query) => query
    .toLowerCase()
    .trim()
    .split(_whitespace)
    .where((String term) => term.isNotEmpty)
    .toList(growable: false);

/// True where every term appears somewhere in [fields].
///
/// The terms are ANDed, never ORed. Typing a second word narrows the list, so
/// "mom dytor" keeps only the rows carrying both. ORing would widen it, which
/// makes search useless the moment anyone types two words.
///
/// A term may land in a different field from its neighbour, so "meera tea"
/// finds Meera's tea request. A term of digits alone is also tried against the
/// digits of the fields, so a phone stored as "98765 00001" is found by typing
/// it unbroken.
bool matchesSearch(String query, List<String?> fields) {
  final List<String> terms = searchTerms(query);
  if (terms.isEmpty) return true;
  final String haystack = fields
      .whereType<String>()
      .join(' ')
      .toLowerCase()
      .trim();
  final String digits = haystack.replaceAll(_notDigits, '');
  for (final String term in terms) {
    if (haystack.contains(term)) continue;
    if (_digitsOnly.hasMatch(term) && digits.contains(term)) continue;
    return false;
  }
  return true;
}

/// The fields of one row that search reads.
typedef SearchFields<T> = List<String?> Function(T item);

/// Builds the list from whatever survived the search.
typedef SearchResults<T> = Widget Function(BuildContext context, List<T> rows);

/// A search field above a list, with the filtering and the no match state.
///
/// Wrap the list part of a surface, never its empty state: a list with nothing
/// in it yet keeps the empty state it already had, which says something a no
/// match panel must not ("add your first person" is wrong when the answer is
/// "no results for xyz").
class SearchScope<T> extends StatefulWidget {
  const SearchScope({
    required this.items,
    required this.fieldsOf,
    required this.hint,
    required this.builder,
    super.key,
  });

  /// Every row the surface would show with no search running, in the order it
  /// would show them. Search is additive: it removes rows and reorders nothing.
  final List<T> items;

  final SearchFields<T> fieldsOf;

  /// What the empty field says, such as "Search people".
  final String hint;

  final SearchResults<T> builder;

  @override
  State<SearchScope<T>> createState() => _SearchScopeState<T>();
}

class _SearchScopeState<T> extends State<SearchScope<T>> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final bool searching = searchTerms(_query).isNotEmpty;
    final List<T> rows = searching
        ? widget.items
              .where((T item) => matchesSearch(_query, widget.fieldsOf(item)))
              .toList(growable: false)
        : widget.items;
    return Column(
      children: <Widget>[
        SearchField(
          controller: _controller,
          hint: widget.hint,
          onChanged: (String value) => setState(() => _query = value),
          onClear: _clear,
        ),
        Expanded(
          child: searching && rows.isEmpty
              ? NoSearchMatch(query: _query.trim(), onClear: _clear)
              : widget.builder(context, rows),
        ),
      ],
    );
  }
}

/// The field itself. Presentational, so the look cannot differ by surface.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 20),
          prefixIconConstraints: const BoxConstraints(minWidth: 40),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Clear search',
                  onPressed: onClear,
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 40),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// What a search that found nothing shows.
///
/// It names what was searched and offers the way out. A blank area would leave
/// someone thinking their records had gone.
class NoSearchMatch extends StatelessWidget {
  const NoSearchMatch({required this.query, required this.onClear, super.key});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off, size: 40, color: colours.primary),
            const SizedBox(height: 12),
            Text(
              '0 results for "$query"',
              textAlign: TextAlign.center,
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Every word has to match. Drop a word, or clear the search to '
              'see the whole list again.',
              textAlign: TextAlign.center,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: onClear, child: const Text('Clear search')),
          ],
        ),
      ),
    );
  }
}
