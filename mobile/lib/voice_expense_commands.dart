import 'package:intl/intl.dart';

import 'expense_speech.dart';
import 'models.dart';

enum VoiceField { amount, category, date, description }

const _aliases = {
  'food': 'Food & Dining',
  'dining': 'Food & Dining',
  'food and dining': 'Food & Dining',
  'bills': 'Bills & Utilities',
  'utilities': 'Bills & Utilities',
  'bills and utilities': 'Bills & Utilities',
  'transport': 'Transportation',
  'health': 'Health & Fitness',
  'fitness': 'Health & Fitness',
  'health and fitness': 'Health & Fitness',
  'other': 'Others',
};

String? voiceCategory(String text, {bool within = false}) {
  final query = text.toLowerCase().replaceAll('&', 'and').trim();
  final names = {
    ..._aliases,
    for (final category in categories)
      category.toLowerCase().replaceAll('&', 'and'): category,
  };
  if (!within) return names[query];
  final keys = names.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in keys) {
    if (RegExp('\\b${RegExp.escape(key)}\\b').hasMatch(query)) {
      return names[key];
    }
  }
  return null;
}

double? voiceAmount(String text) {
  final parsed =
      parseExpenseSpeech(text).amount ??
      spokenNumber(text.replaceFirst(RegExp(r'\s+rupees?$'), ''));
  final value = double.tryParse(parsed ?? '');
  return value != null && value > 0 && value <= 9999999999.99 ? value : null;
}

int? voiceExpenseId(String text) {
  final value = text
      .replaceFirst(
        RegExp(
          r'^(?:edit\s+)?(?:the\s+)?(?:expense\s+)?(?:(?:i d|id|number)\s+)?',
        ),
        '',
      )
      .trim();
  final digits = value.split(RegExp(r'\s+')).map(spokenNumber).toList();
  if (digits.length > 1 && digits.every((part) => part?.length == 1)) {
    return int.tryParse(digits.join());
  }
  return int.tryParse(spokenNumber(value) ?? '');
}

DateTime? voiceDate(String text, DateTime today) {
  final value = text.trim().toLowerCase();
  if (value == 'today') return DateTime(today.year, today.month, today.day);
  if (value == 'yesterday') {
    return DateTime(today.year, today.month, today.day - 1);
  }
  final relative = RegExp(r'^(.+) days? ago$').firstMatch(value);
  if (relative != null) {
    final days = int.tryParse(spokenNumber(relative.group(1)!) ?? '');
    if (days != null && days <= 36500) {
      return DateTime(today.year, today.month, today.day - days);
    }
  }
  final plain = value.replaceAllMapped(
    RegExp(r'\b(\d+)(?:st|nd|rd|th)\b'),
    (match) => match[1]!,
  );
  const ordinals = {
    'first': 'one',
    'second': 'two',
    'third': 'three',
    'fourth': 'four',
    'fifth': 'five',
    'sixth': 'six',
    'seventh': 'seven',
    'eighth': 'eight',
    'ninth': 'nine',
    'tenth': 'ten',
    'eleventh': 'eleven',
    'twelfth': 'twelve',
    'thirteenth': 'thirteen',
    'fourteenth': 'fourteen',
    'fifteenth': 'fifteen',
    'sixteenth': 'sixteen',
    'seventeenth': 'seventeen',
    'eighteenth': 'eighteen',
    'nineteenth': 'nineteen',
    'twentieth': 'twenty',
    'thirtieth': 'thirty',
  };
  final monthDate = RegExp(
    r'^(?:(?:the )?(.+?) (?:of )?)?(january|february|march|april|may|june|july|august|september|october|november|december)(?: (.+))?$',
  ).firstMatch(plain);
  if (monthDate != null) {
    final before = monthDate[1];
    final after = monthDate[3];
    final monthName = monthDate[2]!;
    final month =
        DateFormat.MMMM('en_US').dateSymbols.MONTHS
            .indexWhere((name) => name.toLowerCase() == monthName) +
        1;

    DateTime? parseParts(String dayText, int? year) {
      final dayWords = dayText
          .replaceAll('-', ' ')
          .split(' ')
          .map((word) => ordinals[word] ?? word)
          .join(' ');
      final day = int.tryParse(spokenNumber(dayWords) ?? '');
      if (day == null ||
          day < 1 ||
          day > 31 ||
          year == null ||
          year < 1900 ||
          year > 2200) {
        return null;
      }
      final date = DateTime(year, month, day);
      return date.month == month ? date : null;
    }

    if (before != null) {
      return parseParts(
        before,
        after == null ? today.year : _spokenYear(after),
      );
    }
    if (after != null) {
      final date = parseParts(after, today.year);
      if (date != null) return date;
      final words = after.split(' ');
      for (var split = 1; split < words.length; split++) {
        final date = parseParts(
          words.take(split).join(' '),
          _spokenYear(words.skip(split).join(' ')),
        );
        if (date != null) return date;
      }
    }
  }
  final formatted = plain.replaceAllMapped(
    RegExp(r'\b[a-z]'),
    (match) => match[0]!.toUpperCase(),
  );
  for (final pattern in [
    'yyyy-MM-dd',
    'd/M/yyyy',
    'd MMM yyyy',
    'MMM d yyyy',
    'MMMM d yyyy',
  ]) {
    final date = DateFormat(pattern, 'en_US').tryParseStrict(formatted);
    if (date != null && date.year >= 1900 && date.year <= 2200) return date;
  }
  return null;
}

int? _spokenYear(String value) {
  final year = int.tryParse(spokenNumber(value) ?? '');
  if (year != null && year >= 1900 && year <= 2200) return year;
  final match = RegExp(r'^(nineteen|twenty one|twenty) (.+)$')
      .firstMatch(value);
  if (match == null) return null;
  final century = int.parse(spokenNumber(match[1]!)!);
  final suffix = int.tryParse(spokenNumber(match[2]!) ?? '');
  return suffix != null && suffix < 100 ? century * 100 + suffix : null;
}

bool isSpendingQuestion(String text) => RegExp(
  r'\b(total|spent|spend|spending|anal[yi][sz]e|analysis|breakdown|highest|most expensive|largest expense|how much|average|how many|count)\b',
).hasMatch(text);

String spendingAnswer(
  String question,
  List<Expense> expenses,
  DateTime now, {
  required bool hidden,
}) {
  if (hidden) {
    return 'Amounts are hidden. Turn off amount privacy to hear spending answers.';
  }
  final month = DateTime(now.year, now.month);
  final day = DateTime(now.year, now.month, now.day);
  final (start, end, period) = switch (question) {
    String q when q.contains('all time') || q.contains('all-time') => (
      null,
      null,
      'all time',
    ),
    String q when q.contains('last month') => (
      DateTime(now.year, now.month - 1),
      month,
      'last month',
    ),
    String q when q.contains('last year') => (
      DateTime(now.year - 1),
      DateTime(now.year),
      'last year',
    ),
    String q when q.contains('this year') => (
      DateTime(now.year),
      DateTime(now.year + 1),
      'this year',
    ),
    String q when q.contains('yesterday') => (
      DateTime(now.year, now.month, now.day - 1),
      day,
      'yesterday',
    ),
    String q when q.contains('today') => (
      day,
      DateTime(now.year, now.month, now.day + 1),
      'today',
    ),
    String q when q.contains('this week') => (
      DateTime(now.year, now.month, now.day - now.weekday + 1),
      DateTime(now.year, now.month, now.day - now.weekday + 8),
      'this week',
    ),
    String q when q.contains('last week') => (
      DateTime(now.year, now.month, now.day - now.weekday - 6),
      DateTime(now.year, now.month, now.day - now.weekday + 1),
      'last week',
    ),
    _ => (month, DateTime(now.year, now.month + 1), 'this month'),
  };
  final category = voiceCategory(question, within: true);
  final selected = expenses
      .where(
        (e) =>
            (start == null || !e.date.isBefore(start)) &&
            (end == null || e.date.isBefore(end)) &&
            (category == null ||
                e.category.toLowerCase() == category.toLowerCase()),
      )
      .toList();
  final subject = category == null ? period : 'in $category $period';
  if (selected.isEmpty) return 'No expenses $subject.';
  final total = selected.fold(0.0, (sum, expense) => sum + expense.amount);
  if (RegExp(r'\b(how many|count)\b').hasMatch(question)) {
    return '${selected.length} expenses $subject.';
  }
  if (question.contains('average')) {
    return 'Average expense $subject is ${money(total / selected.length, false)}.';
  }
  if (question.contains('most expensive') ||
      question.contains('largest expense')) {
    final largest = selected.reduce((a, b) => a.amount >= b.amount ? a : b);
    return 'Largest expense $subject was ID ${largest.id}, ${money(largest.amount, false)}.';
  }
  if (category == null &&
      RegExp(
        r'\b(anal[yi][sz]e|analysis|breakdown|highest|category|categories)\b',
      ).hasMatch(question)) {
    final totals = <String, double>{};
    for (final expense in selected) {
      totals.update(
        expense.category,
        (sum) => sum + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final breakdown = ranked
        .take(3)
        .map((e) => '${e.key} ${money(e.value, false)}')
        .join(', ');
    return 'Total $period was ${money(total, false)} across ${selected.length} expenses. Top categories: $breakdown.';
  }
  return 'You spent ${money(total, false)} $subject.';
}
