import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/components/statement_share.dart';
import 'package:hisaab/models/models.dart';

import 'support/harness.dart';

/// The text and the PDF read the same [Statement], so their figures agree by
/// construction. These tests hold that in place.
void main() {
  test('the message carries both subtotals and one net figure', () {
    final Statement statement = sampleStatement();
    final String message = StatementShare.message(
      statement,
      template: 'Here is your statement.',
    );

    expect(message, startsWith('Here is your statement.'));
    expect(message, contains('Meera Joshi, as of 9 Sep 2026'));
    expect(message, contains('Product dues'));
    expect(message, contains('Cash'));
    expect(
      message,
      contains('Subtotal ₹2,100'),
      reason: 'products are 4,100 less the 2,000 payment',
    );
    expect(message, contains('Subtotal ₹1,500'));
    expect(message, contains('Balance due ₹3,600'));
  });

  test('the message names a credit rather than a negative balance', () {
    final Statement statement = Statement(
      person: kSunita,
      products: const StatementGroup(
        title: 'Product dues',
        lines: <StatementLine>[],
      ),
      cash: StatementGroup(
        title: 'Cash',
        lines: <StatementLine>[
          StatementLine(
            date: DateTime(2026, 9, 1),
            description: 'Cash borrowed',
            amountPaise: -50000,
          ),
        ],
      ),
      generatedAt: DateTime(2026, 9, 9),
    );
    expect(StatementShare.message(statement), contains('In your credit ₹500'));
  });

  test('the PDF renders to real bytes with no font left missing', () async {
    final Uint8List bytes = await StatementShare.pdf(
      sampleStatement(),
      header: 'Hisaab statement',
      footer: 'Pay by UPI to meera@bank',
    );
    expect(bytes.length, greaterThan(1000));
    expect(
      String.fromCharCodes(bytes.take(4)),
      '%PDF',
      reason: 'a PDF starts with its own magic bytes',
    );
  });
}
