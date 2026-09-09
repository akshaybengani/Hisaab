import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/request_form.dart';
import '../models/models.dart';
import '../providers/app_state.dart';
import 'navigation.dart';
import 'person_edit_screen.dart';
import 'product_edit_screen.dart';

/// Noting what someone asked for.
class RequestEditScreen extends StatelessWidget {
  const RequestEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppState state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Add request')),
      body: RequestForm(
        people: state.people,
        products: state.activeProducts,
        onAddPerson: () => openScreen(context, const PersonEditScreen()),
        onAddProduct: () => openScreen(context, const ProductEditScreen()),
        onSave: (ProductRequest request) async {
          await state.addRequest(request);
          if (!context.mounted) return;
          say(context, 'Request noted.');
          Navigator.of(context).pop();
        },
      ),
    );
  }
}
