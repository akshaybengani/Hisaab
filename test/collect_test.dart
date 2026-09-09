import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/components/collect_view.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/models/models.dart';
import 'package:hisaab/providers/app_state.dart';
import 'package:hisaab/providers/view_models.dart';
import 'package:hisaab/screens/collect_screen.dart';

import 'support/fake_repositories.dart';
import 'support/harness.dart';
import 'support/memex_ac.dart';

/// The collect screen is where a rounding rule would do the most damage, so
/// the rules it follows are asserted directly.
///
/// The words matter as much as the arithmetic. A remainder the person did not
/// hand over is a discount given, and money handed over above the balance is
/// change kept. Neither is a debt written off. See dec-13.
void main() {
  useAcEmission('test/collect_test.dart');

  group('CollectPlan', () {
    test('asks about the pool only where both carry a balance', () {
      const CollectPlan both = CollectPlan(
        productDuePaise: 210000,
        cashDuePaise: 150000,
        paidPaise: 0,
        pool: SettlementPool.products,
      );
      expect(both.needsPoolChoice, isTrue);

      const CollectPlan productsOnly = CollectPlan(
        productDuePaise: 210000,
        cashDuePaise: 0,
        paidPaise: 0,
        pool: SettlementPool.products,
      );
      expect(productsOnly.needsPoolChoice, isFalse);
      expect(productsOnly.effectivePool, SettlementPool.products);
      expect(productsOnly.kind, MoneyKind.paymentReceived);

      const CollectPlan cashOnly = CollectPlan(
        productDuePaise: 0,
        cashDuePaise: 150000,
        paidPaise: 0,
        pool: SettlementPool.products,
      );
      expect(cashOnly.needsPoolChoice, isFalse);
      expect(
        cashOnly.effectivePool,
        SettlementPool.cash,
        reason: 'with only a loan outstanding there is nothing to ask',
      );
      expect(cashOnly.kind, MoneyKind.repayment);
    });

    test('leaves a remainder rather than rounding it away', () {
      const CollectPlan plan = CollectPlan(
        productDuePaise: 205000,
        cashDuePaise: 0,
        paidPaise: 200000,
        pool: SettlementPool.products,
      );
      expect(plan.remainderPaise, 5000);
      expect(plan.canGiveDiscount, isTrue);
      expect(plan.canKeepChange, isFalse);
    });

    test('treats an overpayment as change kept, not a discount given', () {
      const CollectPlan plan = CollectPlan(
        productDuePaise: 205000,
        cashDuePaise: 0,
        paidPaise: 210000,
        pool: SettlementPool.products,
      );
      expect(plan.remainderPaise, -5000);
      expect(plan.canGiveDiscount, isFalse);
      expect(plan.canKeepChange, isTrue);
    });

    test('offers nothing to clear where the payment settles it exactly', () {
      const CollectPlan plan = CollectPlan(
        productDuePaise: 205000,
        cashDuePaise: 0,
        paidPaise: 205000,
        pool: SettlementPool.products,
      );
      expect(plan.hasRemainder, isFalse);
      expect(plan.canGiveDiscount, isFalse);
      expect(plan.canKeepChange, isFalse);
    });
  });

  group('CollectView', () {
    testWidgets('hides the pool question where only one pool has a balance', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: CollectView(
            person: kMeera,
            productDuePaise: 205000,
            cashDuePaise: 0,
            onRecord: (CollectPlan plan, {required bool clearRemainder}) {},
          ),
        ),
        brightness: Brightness.light,
      );
      expect(find.text('What does this settle?'), findsNothing);
    });

    testWidgets('asks the pool question where both pools have a balance', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: CollectView(
            person: kMeera,
            productDuePaise: 205000,
            cashDuePaise: 150000,
            onRecord: (CollectPlan plan, {required bool clearRemainder}) {},
          ),
        ),
        brightness: Brightness.light,
      );
      expect(find.text('What does this settle?'), findsOneWidget);
      expect(find.text('Product dues'), findsOneWidget);
      expect(find.text('Cash loan'), findsOneWidget);
    });

    testWidgets('names the real figure on the clear action', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: CollectView(
            person: kMeera,
            productDuePaise: 205000,
            cashDuePaise: 0,
            onRecord: (CollectPlan plan, {required bool clearRemainder}) {},
          ),
        ),
        brightness: Brightness.light,
      );

      expect(
        find.text('₹2,050'),
        findsWidgets,
        reason: 'the exact balance shows before anything is typed',
      );

      await tester.enterText(find.byType(TextFormField).first, '2000');
      await tester.pump();

      expect(find.text('Give ₹50 discount'), findsOneWidget);
      expect(find.text('₹50 still owed after this.'), findsOneWidget);
    });

    testWidgets('does not clear the remainder unless it is ticked', (
      WidgetTester tester,
    ) async {
      CollectPlan? recorded;
      bool? cleared;
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: CollectView(
            person: kMeera,
            productDuePaise: 205000,
            cashDuePaise: 0,
            onRecord: (CollectPlan plan, {required bool clearRemainder}) {
              recorded = plan;
              cleared = clearRemainder;
            },
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.enterText(find.byType(TextFormField).first, '2000');
      await tester.pump();
      await tapAfterScroll(tester, find.text('Record payment'));

      expect(recorded?.paidPaise, 200000);
      expect(recorded?.remainderPaise, 5000);
      expect(cleared, isFalse, reason: 'nothing is rounded on its own');

      await tapAfterScroll(tester, find.text('Give ₹50 discount'));
      await tapAfterScroll(tester, find.text('Record payment'));
      expect(cleared, isTrue);
    });

    testWidgets('an overpayment offers to keep the change, not a discount', (
      WidgetTester tester,
    ) async {
      await pumpOnSmallPhone(
        tester,
        Scaffold(
          body: CollectView(
            person: kMeera,
            productDuePaise: 205000,
            cashDuePaise: 0,
            onRecord: (CollectPlan plan, {required bool clearRemainder}) {},
          ),
        ),
        brightness: Brightness.light,
      );

      await tester.enterText(find.byType(TextFormField).first, '2100');
      await tester.pump();

      expect(find.text('Keep ₹50 change'), findsOneWidget);
      expect(find.text('Give ₹50 discount'), findsNothing);
    });
  });

  group('CollectScreen', () {
    /// Verifies ac-37: the concession is its own entry for exactly the
    /// remainder, and the payment keeps the figure the user typed.
    acTestWidgets(
      'a discount given writes an adjustment for exactly the remainder',
      <String>['ac-37'],
      (WidgetTester tester) async {
        final FakeRepositories repos = FakeRepositories.seeded();
        final AppState state = AppState(repos);
        await state.load();

        // Meera carries one delivery of 4,100 against a payment of 2,000.
        expect(state.productDueFor(1), 210000);

        await pumpOnSmallPhone(
          tester,
          const CollectScreen(person: kMeera),
          brightness: Brightness.light,
          state: state,
        );

        await tester.enterText(find.byType(TextFormField).first, '2000');
        await tester.pump();
        await tapAfterScroll(tester, find.text('Give ₹100 discount'));
        await tapAfterScroll(tester, find.text('Record payment'));
        await tester.pumpAndSettle();

        final List<MoneyEntry> added = repos.money.rows
            .where((MoneyEntry e) => (e.id ?? 0) > 1)
            .toList();
        expect(added.length, 2, reason: 'the payment and the discount');

        final MoneyEntry payment = added.first;
        expect(payment.kind, MoneyKind.paymentReceived);
        expect(
          payment.amountPaise,
          200000,
          reason: 'the payment stays equal to the cash that was handed over',
        );

        final MoneyEntry discount = added.last;
        expect(
          discount.kind,
          MoneyKind.adjustment,
          reason: 'a concession at the point of collection is not a write off',
        );
        expect(discount.amountPaise, 10000);
        expect(discount.direction, MoneyDirection.incoming);
        expect(discount.note, 'Discount given on collection');

        expect(state.productDueFor(1), 0);
      },
    );
  });
}
