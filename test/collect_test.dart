import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/components/collect_view.dart';
import 'package:hisaab/constants.dart';
import 'package:hisaab/providers/view_models.dart';

import 'support/harness.dart';

/// The collect screen is where a rounding rule would do the most damage, so
/// the rules it follows are asserted directly.
void main() {
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
      expect(plan.canWriteOff, isTrue);
      expect(plan.canAdjust, isFalse);
    });

    test('treats an overpayment as a round off, not a write off', () {
      const CollectPlan plan = CollectPlan(
        productDuePaise: 205000,
        cashDuePaise: 0,
        paidPaise: 210000,
        pool: SettlementPool.products,
      );
      expect(plan.remainderPaise, -5000);
      expect(plan.canWriteOff, isFalse);
      expect(plan.canAdjust, isTrue);
    });

    test('offers nothing to clear where the payment settles it exactly', () {
      const CollectPlan plan = CollectPlan(
        productDuePaise: 205000,
        cashDuePaise: 0,
        paidPaise: 205000,
        pool: SettlementPool.products,
      );
      expect(plan.hasRemainder, isFalse);
      expect(plan.canWriteOff, isFalse);
      expect(plan.canAdjust, isFalse);
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

      expect(find.text('Write off ₹50'), findsOneWidget);
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

      await tapAfterScroll(tester, find.text('Write off ₹50'));
      await tapAfterScroll(tester, find.text('Record payment'));
      expect(cleared, isTrue);
    });
  });
}
