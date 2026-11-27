import 'package:finance_tracker/expense_speech.dart';
import 'package:finance_tracker/models.dart';
import 'package:finance_tracker/voice_expense_commands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes spoken IDs and calendar dates', () {
    final now = DateTime(2026, 11, 26);
    expect(voiceExpenseId('edit the expense i d four three'), 43);
    expect(
      voiceDate('november twenty first twenty twenty six', now),
      DateTime(2026, 11, 21),
    );
    expect(voiceDate('first of december', now), DateTime(2026, 12, 1));
    expect(voiceDate('february thirtieth', now), isNull);
  });

  test('filters spending by calendar period and suppresses hidden amounts', () {
    final now = DateTime(2026, 11, 26);
    final expenses = [
      Expense(
        id: 1,
        amount: 40,
        category: 'Shopping',
        description: '',
        date: DateTime(2026, 10, 18),
      ),
      Expense(
        id: 2,
        amount: 369,
        category: 'Shopping',
        description: '',
        date: now,
      ),
    ];
    expect(
      spendingAnswer('shopping last month', expenses, now, hidden: false),
      contains('₹40.00'),
    );
    expect(
      spendingAnswer('shopping this month', expenses, now, hidden: true),
      isNot(contains('369')),
    );
  });
  test('parses a rupee amount and a note from a spoken expense', () {
    expect(
      parseExpenseSpeech('paid two hundred and fifty rupees for groceries'),
      (amount: '250', note: 'groceries'),
    );
    expect(parseExpenseSpeech('one thousand two hundred rupees for travel'), (
      amount: '1200',
      note: 'travel',
    ));
  });

  test('preserves decimal amounts and rejects ambiguous amounts', () {
    expect(parseExpenseSpeech('twenty point five zero rupees for tea'), (
      amount: '20.50',
      note: 'tea',
    ));
    expect(parseExpenseSpeech('20.50 rupees'), (amount: '20.50', note: ''));
    expect(parseExpenseSpeech('twenty or thirty rupees for tea'), (
      amount: null,
      note: 'twenty or thirty rupees for tea',
    ));
  });
}
