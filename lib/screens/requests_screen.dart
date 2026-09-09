import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/confirm_dialog.dart';
import '../components/requests_view.dart';
import '../constants.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import '../providers/view_models.dart';
import 'navigation.dart';
import 'request_edit_screen.dart';

/// The request, order, deliver pipeline.
class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return RequestsView(
      pending: state.pendingRequests,
      ordered: state.orderedRequests,
      productsById: state.productsById,
      peopleById: state.peopleById,
      buildShoppingList: state.shoppingListFor,
      onAddRequest: () => openScreen(context, const RequestEditScreen()),
      onMarkOrdered: (List<ProductRequest> requests) async {
        await state.markRequestsOrdered(
          <int>[
            for (final ProductRequest request in requests)
              if (request.id != null) request.id!,
          ],
        );
        if (!context.mounted) return;
        say(context, '${countLabel(requests.length, 'request')} marked ordered.');
      },
      onConvert: (ProductRequest request) => _convert(context, state, request),
      onCancel: (ProductRequest request) => _cancel(context, state, request),
    );
  }

  Future<void> _convert(
    BuildContext context,
    AppState state,
    ProductRequest request,
  ) async {
    final int? id = request.id;
    final Product? product = state.productsById[request.productId];
    if (id == null || product == null) return;
    await state.convertRequestToDelivery(
      id,
      DeliveryItem(
        id: null,
        deliveryId: null,
        productId: request.productId,
        qty: request.qty,
        unitPricePaise: product.currentPricePaise,
      ),
    );
    if (!context.mounted) return;
    say(context, 'Turned into a delivery.');
  }

  Future<void> _cancel(
    BuildContext context,
    AppState state,
    ProductRequest request,
  ) async {
    final int? id = request.id;
    if (id == null) return;
    final Product? product = state.productsById[request.productId];
    final bool ok = await confirm(
      context,
      title: 'Cancel this request',
      message:
          'Cancelling drops ${product?.name ?? 'this product'} off the '
          'shopping list. The row stays in the history as cancelled.',
      actionLabel: 'Cancel request',
    );
    if (!ok || !context.mounted) return;
    await state.setRequestStatus(id, RequestStatus.cancelled);
  }
}
