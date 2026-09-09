import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/app_shell.dart';
import 'package:hisaab/main.dart';

void main() {
  testWidgets('the app boots to the shell with four destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const HisaabApp());
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.text('Dues'), findsWidgets);
    expect(find.text('Deliver'), findsOneWidget);
  });
}
