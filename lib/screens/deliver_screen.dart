import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/deliver_form.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'navigation.dart';
import 'person_edit_screen.dart';
import 'product_edit_screen.dart';

/// Recording a handover, the highest frequency action in the app.
class DeliverScreen extends StatelessWidget {
  const DeliverScreen({this.personId, super.key});

  final int? personId;

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Deliver')),
      body: DeliverForm(
        people: state.people,
        products: state.activeProducts,
        initialPersonId: personId,
        onAddPerson: () => openScreen(context, const PersonEditScreen()),
        onAddProduct: () => openScreen(context, const ProductEditScreen()),
        onSave: (Delivery delivery, List<DeliveryItem> items) async {
          await state.saveDelivery(delivery, items);
          if (!context.mounted) return;
          say(context, 'Delivery saved.');
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
