import 'package:finance_tracker/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' show TestBackend, capture, start;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('edits a loan and persists settlement and reopening', (
    tester,
  ) async {
    final backend = TestBackend();
    backend.loans.add(
      Loan(
        id: 1,
        person: 'Alex',
        direction: 'lent',
        amount: 500,
        date: DateTime(2026, 11, 1),
      ).toJson(),
    );
    await start(tester, backend, size: const Size(390, 1000));
    await tester.tap(find.text('Loans').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Amount'), '750');
    final save = find.widgetWithText(FilledButton, 'Save loan');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(backend.controller.outstanding('lent'), 750);
    expect(backend.requests.where((r) => r.method == 'PUT').length, 1);
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mark settled'));
    await tester.tap(find.text('Mark settled'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(backend.controller.outstanding('lent'), 0);
    await tester.tap(find.text('Settled'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    await capture(tester, 'loans-settled');
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reopen loan'));
    await tester.tap(find.text('Reopen loan'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(backend.controller.outstanding('lent'), 750);
    expect(backend.requests.where((r) => r.method == 'PATCH').length, 2);
    expect(backend.controller.stats!.total, 1630);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('records a loan and cancels a pending settlement', (
    tester,
  ) async {
    final backend = TestBackend();
    await start(tester, backend, size: const Size(390, 1000));
    await tester.tap(find.text('Loans'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('New loan entry'));
    await tester.pumpAndSettle();
    await capture(tester, 'loan-sheet');
    final save = find.widgetWithText(FilledButton, 'Save loan');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter a name'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Person'),
      'Alex',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Amount'),
      '500.25',
    );
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    await capture(tester, 'loans');
    expect(backend.controller.outstanding('lent'), 500.25);
    expect(backend.controller.stats!.total, 1630);
    expect(backend.expenses.length, 2);
    await tester.tap(find.text('Alex'));
    await tester.pumpAndSettle();
    final settle = find.text('Mark settled');
    await tester.ensureVisible(settle);
    await tester.tap(settle);
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Alex'), findsOneWidget);
    expect(backend.controller.outstanding('lent'), 500.25);
    expect(backend.requests.where((r) => r.method == 'PATCH'), isEmpty);
    expect(backend.requests.where((r) => r.method == 'POST').length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

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
      await tester.tap(find.text('Loans'));
      await tester.pumpAndSettle();
      expect(find.text('₹500.00'), findsNothing);
      expect(find.text('••••••'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
