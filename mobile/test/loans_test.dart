import 'package:finance_tracker/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show TestBackend, start;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'records a loan, strikes refunded names, and restores outstanding on undo',
    (tester) async {
      final backend = TestBackend();
      await start(tester, backend, size: const Size(390, 1000));
      await tester.tap(find.text('Borrow & Lend'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save entry');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('Enter a name'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Person’s name'),
        'Alex',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Loan amount'),
        '500.25',
      );
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(backend.controller.outstanding('lent'), 500.25);
      expect(backend.controller.stats!.total, 1630);
      expect(backend.expenses.length, 2);
      final refund = find.text('Mark refunded');
      await tester.drag(find.byType(ListView).last, const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(refund);
      await tester.pumpAndSettle();
      await tester.tap(refund);
      await tester.pumpAndSettle();
      expect(backend.controller.outstanding('lent'), 0);
      expect(find.text('Refunded'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Alex')).style!.decoration,
        TextDecoration.lineThrough,
      );
      await tester.ensureVisible(find.text('Undo refund'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo refund'));
      await tester.pumpAndSettle();
      expect(backend.controller.outstanding('lent'), 500.25);
      expect(tester.widget<Text>(find.text('Alex')).style!.decoration, isNull);
      expect(backend.requests.where((r) => r.method == 'POST').length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'borrowed and lent balances stay separate, respect privacy and fit narrow screens',
    (tester) async {
      final backend = TestBackend();
      backend.loans.addAll([
        Loan(
          id: 1,
          person: 'Alex',
          direction: 'lent',
          amount: 500,
          date: DateTime(2026, 1, 1),
        ).toJson(),
        Loan(
          id: 2,
          person: 'Sam',
          direction: 'borrowed',
          amount: 200,
          date: DateTime(2025, 1, 1),
        ).toJson(),
        Loan(
          id: 3,
          person: 'Refunded person',
          direction: 'lent',
          amount: 1000,
          date: DateTime(2026, 1, 1),
          refunded: true,
        ).toJson(),
      ]);
      await start(tester, backend, size: const Size(320, 740));
      expect(backend.controller.outstanding('lent'), 500);
      expect(backend.controller.outstanding('borrowed'), 200);
      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.tap(find.text('Borrow & Lend'));
      await tester.pumpAndSettle();
      expect(find.text('₹500.00'), findsNothing);
      expect(find.text('••••••'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
