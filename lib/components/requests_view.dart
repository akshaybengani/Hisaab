import 'package:flutter/material.dart';

import '../constants.dart';
import '../helpers/dates.dart';
import '../models/models.dart';
import '../providers/view_models.dart';
import 'empty_state.dart';
import 'search_field.dart';
import 'section_header.dart';

/// The request, order, deliver pipeline.
///
/// Pending sits oldest first with an age on every row, so a request nobody
/// acted on stays uncomfortable rather than scrolling away. Ticking rows
/// builds the consolidated shopping list.
///
/// The shopping list itself is built by [buildShoppingList], injected so this
/// widget renders without the stock arithmetic behind it.
class RequestsView extends StatefulWidget {
  const RequestsView({
    required this.pending,
    required this.ordered,
    required this.productsById,
    required this.peopleById,
    required this.buildShoppingList,
    required this.onMarkOrdered,
    required this.onConvert,
    required this.onCancel,
    required this.onAddRequest,
    this.now,
    super.key,
  });

  final List<ProductRequest> pending;
  final List<ProductRequest> ordered;
  final Map<int, Product> productsById;
  final Map<int, Person> peopleById;

  /// Collapses the ticked requests into one line per product.
  final List<ShoppingListLine>? Function(List<ProductRequest> selected)
  buildShoppingList;

  final ValueChanged<List<ProductRequest>> onMarkOrdered;
  final ValueChanged<ProductRequest> onConvert;
  final ValueChanged<ProductRequest> onCancel;
  final VoidCallback onAddRequest;

  /// Fixed in tests so an age label does not depend on the clock.
  final DateTime? now;

  @override
  State<RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends State<RequestsView> {
  final Set<int> _ticked = <int>{};

  /// Oldest first, sorted here rather than trusted from the caller, so a
  /// stale request cannot scroll out of sight. See spec-27 dec-8.
  List<ProductRequest> get _pending => <ProductRequest>[...widget.pending]
    ..sort(
      (ProductRequest a, ProductRequest b) =>
          a.createdAt.compareTo(b.createdAt),
    );

  List<ProductRequest> get _ordered => <ProductRequest>[...widget.ordered]
    ..sort(
      (ProductRequest a, ProductRequest b) =>
          a.createdAt.compareTo(b.createdAt),
    );

  List<ProductRequest> get _selected => _pending
      .where((ProductRequest r) => _ticked.contains(r.id))
      .toList(growable: false);

  String _label(ProductRequest request) {
    final Product? product = widget.productsById[request.productId];
    final String unit = product == null
        ? countLabel(request.qty, 'unit')
        : countLabel(request.qty, product.unitLabel);
    return '${product?.name ?? 'Unknown product'}, $unit';
  }

  String _who(ProductRequest request) {
    final Person? person = widget.peopleById[request.personId];
    final String name = person?.name ?? 'Unknown person';
    final String? member = request.forMember;
    return member == null ? name : '$name, for $member';
  }

  Future<void> _showShoppingList() async {
    final List<ShoppingListLine>? lines = widget.buildShoppingList(_selected);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => ShoppingListSheet(lines: lines),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pending.isEmpty && widget.ordered.isEmpty) {
      return EmptyState(
        icon: Icons.playlist_add_outlined,
        message:
            'Requests is where you note what someone asked for before you '
            'order. Ticking them later builds one shopping list.',
        actionLabel: 'Add request',
        onAction: widget.onAddRequest,
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: SearchScope<ProductRequest>(
            hint: 'Search requests',
            items: <ProductRequest>[..._pending, ..._ordered],
            fieldsOf: _fieldsOf,
            builder: (BuildContext context, List<ProductRequest> rows) =>
                _list(rows),
          ),
        ),
        if (_ticked.isNotEmpty)
          _SelectionBar(
            count: _ticked.length,
            onShowList: _showShoppingList,
            onMarkOrdered: () {
              widget.onMarkOrdered(_selected);
              setState(_ticked.clear);
            },
          ),
      ],
    );
  }

  /// Everything a person might type looking for one request.
  List<String?> _fieldsOf(ProductRequest request) => <String?>[
    widget.productsById[request.productId]?.name,
    widget.productsById[request.productId]?.unitLabel,
    widget.peopleById[request.personId]?.name,
    request.forMember,
    request.note,
  ];

  /// The two sections, rebuilt from whatever survived the search. Each keeps
  /// the oldest first order it was given.
  Widget _list(List<ProductRequest> rows) {
    final List<ProductRequest> pending = rows
        .where((ProductRequest r) => widget.pending.contains(r))
        .toList(growable: false);
    final List<ProductRequest> ordered = rows
        .where((ProductRequest r) => widget.ordered.contains(r))
        .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        if (pending.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: 'Pending',
            trailing: countLabel(pending.length, 'request'),
          ),
          for (final ProductRequest request in pending)
            CheckboxListTile(
              value: _ticked.contains(request.id),
              onChanged: (bool? on) => setState(() {
                final int? id = request.id;
                if (id == null) return;
                if (on ?? false) {
                  _ticked.add(id);
                } else {
                  _ticked.remove(id);
                }
              }),
              title: Text(_label(request)),
              subtitle: Text(
                '${_who(request)}, asked '
                '${Dates.ageLabel(request.createdAt, now: widget.now)} ago',
              ),
              secondary: _RequestMenu(
                request: request,
                onMarkOrdered: () =>
                    widget.onMarkOrdered(<ProductRequest>[request]),
                onCancel: () => widget.onCancel(request),
              ),
            ),
        ],
        if (ordered.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: 'Ordered',
            trailing: countLabel(ordered.length, 'request'),
          ),
          for (final ProductRequest request in ordered)
            ListTile(
              title: Text(_label(request)),
              subtitle: Text(
                '${_who(request)}, asked '
                '${Dates.ageLabel(request.createdAt, now: widget.now)} ago',
              ),
              trailing: _RequestMenu(
                request: request,
                onConvert: () => widget.onConvert(request),
                onCancel: () => widget.onCancel(request),
              ),
            ),
        ],
      ],
    );
  }
}

class _RequestMenu extends StatelessWidget {
  const _RequestMenu({
    required this.request,
    required this.onCancel,
    this.onMarkOrdered,
    this.onConvert,
  });

  final ProductRequest request;
  final VoidCallback onCancel;
  final VoidCallback? onMarkOrdered;
  final VoidCallback? onConvert;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onMarkOrdered = this.onMarkOrdered;
    final VoidCallback? onConvert = this.onConvert;
    return PopupMenuButton<VoidCallback>(
      tooltip: 'Request actions',
      onSelected: (VoidCallback action) => action(),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<VoidCallback>>[
        if (onMarkOrdered != null &&
            request.status.canMoveTo(RequestStatus.ordered))
          PopupMenuItem<VoidCallback>(
            value: onMarkOrdered,
            child: const Text('Mark ordered'),
          ),
        if (onConvert != null &&
            request.status.canMoveTo(RequestStatus.delivered))
          PopupMenuItem<VoidCallback>(
            value: onConvert,
            child: const Text('Convert to a delivery'),
          ),
        PopupMenuItem<VoidCallback>(
          value: onCancel,
          child: const Text('Cancel request'),
        ),
      ],
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.onShowList,
    required this.onMarkOrdered,
  });

  final int count;
  final VoidCallback onShowList;
  final VoidCallback onMarkOrdered;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Material(
      color: colours.secondaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          // The count sits above the buttons rather than beside them: two
          // buttons and a line of text do not fit across a small phone.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${countLabel(count, 'request')} ticked',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colours.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextButton(
                      onPressed: onShowList,
                      child: const Text(
                        'Shopping list',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onMarkOrdered,
                      child: const Text(
                        'Mark ordered',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The consolidated shopping list, one line per product.
class ShoppingListSheet extends StatelessWidget {
  const ShoppingListSheet({required this.lines, super.key});

  final List<ShoppingListLine>? lines;

  @override
  Widget build(BuildContext context) {
    final List<ShoppingListLine>? lines = this.lines;
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Shopping list', style: text.titleLarge),
          const SizedBox(height: 8),
          if (lines == null)
            Text(
              'The shopping list could not be worked out.',
              style: text.bodyMedium,
            )
          else if (lines.isEmpty)
            Text('Nothing ticked yet.', style: text.bodyMedium)
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  for (final ShoppingListLine line in lines)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(line.productName),
                      subtitle: Text(
                        '${countLabel(line.requestCount, 'person', plural: 'people')} asked',
                      ),
                      trailing: Text(countLabel(line.qty, line.unitLabel)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
