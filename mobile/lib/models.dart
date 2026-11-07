import 'package:intl/intl.dart';

const categories = [
  'Gym',
  'Food & Dining',
  'Shopping',
  'Bills & Utilities',
  'Transportation',
  'Entertainment',
  'Health & Fitness',
  'Travel',
  'Investment',
  'Education',
  'Others',
];

double number(dynamic value) =>
    value is num ? value.toDouble() : double.parse('$value');
String dateValue(DateTime value) => DateFormat('yyyy-MM-dd').format(value);
String money(num value, bool hidden) => hidden
    ? '••••••'
    : NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 2,
      ).format(value);

class Expense {
  final int id;
  final double amount;
  final String category;
  final String description;
  final DateTime date;
  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'category': category,
    'description': description,
    'date': dateValue(date),
  };
  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
    id: json['id'] as int,
    amount: number(json['amount']),
    category: json['category'] as String,
    description: json['description'] as String,
    date: DateTime.parse(json['date'] as String),
  );
}

class ExpenseDraft {
  final double amount;
  final String category;
  final String description;
  final DateTime date;
  const ExpenseDraft({
    required this.amount,
    required this.category,
    required this.description,
    required this.date,
  });
  Map<String, dynamic> toJson() => {
    'amount': amount,
    'category': category,
    'description': description.trim(),
    'date': dateValue(date),
  };
}

class DailyPoint {
  final String label;
  final double amount;
  const DailyPoint(this.label, this.amount);
}

class CategoryTotal {
  final String category;
  final double total;
  final int count;
  const CategoryTotal(this.category, this.total, this.count);
  factory CategoryTotal.fromJson(Map<String, dynamic> json) => CategoryTotal(
    json['category'] as String,
    number(json['total']),
    json['count'] as int,
  );
}

class DashboardStats {
  final double total;
  final double monthly;
  final double dailyAverage;
  final int activeCategories;
  final List<DailyPoint> dailyPattern;
  final List<Expense> recent;
  final List<CategoryTotal> topCategories;
  final List<CategoryTotal> yearlyCategories;
  const DashboardStats({
    required this.total,
    required this.monthly,
    required this.dailyAverage,
    required this.activeCategories,
    required this.dailyPattern,
    required this.recent,
    required this.topCategories,
    required this.yearlyCategories,
  });
  Map<String, dynamic> toJson() => {
    'total_expenses': total,
    'this_month': monthly,
    'daily_average': dailyAverage,
    'active_categories': activeCategories,
    'daily_pattern': dailyPattern
        .map((p) => {'day': p.label, 'amount': p.amount})
        .toList(),
    'recent_expenses': recent.map((e) => e.toJson()).toList(),
    'top_categories': topCategories
        .map(
          (c) => {'category': c.category, 'total': c.total, 'count': c.count},
        )
        .toList(),
    'total_by_category': yearlyCategories
        .map(
          (c) => {'category': c.category, 'total': c.total, 'count': c.count},
        )
        .toList(),
  };
  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
    total: number(json['total_expenses']),
    monthly: number(json['this_month']),
    dailyAverage: number(json['daily_average']),
    activeCategories: json['active_categories'] as int,
    dailyPattern: (json['daily_pattern'] as List)
        .map((e) => DailyPoint(e['day'] as String, number(e['amount'])))
        .toList(),
    recent: (json['recent_expenses'] as List)
        .map((e) => Expense.fromJson(e as Map<String, dynamic>))
        .toList(),
    topCategories: (json['top_categories'] as List)
        .map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>))
        .toList(),
    yearlyCategories: (json['total_by_category'] as List)
        .map((e) => CategoryTotal.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
