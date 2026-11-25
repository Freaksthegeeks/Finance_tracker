import 'package:flutter/material.dart';

const sage = Color(0xFF5C9C84);
const ink = Color(0xFF1E293B);
const muted = Color(0xFF64748B);
const canvas = Color(0xFFF6F8FA);

ThemeData trackerTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'TrackerSans',
  colorScheme: ColorScheme.fromSeed(
    seedColor: sage,
    primary: sage,
    surface: Colors.white,
  ),
  scaffoldBackgroundColor: canvas,
  appBarTheme: const AppBarTheme(
    backgroundColor: canvas,
    foregroundColor: ink,
    centerTitle: false,
    scrolledUnderElevation: 0,
  ),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      color: ink,
      letterSpacing: -0.8,
    ),
    titleLarge: TextStyle(
      fontSize: 21,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: ink),
    bodySmall: TextStyle(fontSize: 12, color: muted),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    contentPadding: const EdgeInsets.all(16),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      textStyle: const TextStyle(
        fontFamily: 'TrackerSans',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: sage.withValues(alpha: 0.16),
    labelTextStyle: WidgetStateProperty.all(
      const TextStyle(
        fontFamily: 'TrackerSans',
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
);

Color categoryColor(String category) => switch (category) {
  'Gym' => const Color(0xFF8B5CF6),
  'Food & Dining' => const Color(0xFFF59E0B),
  'Shopping' => const Color(0xFFEC4899),
  'Bills & Utilities' => const Color(0xFF3B82F6),
  'Transportation' => const Color(0xFF10B981),
  'Entertainment' => const Color(0xFF6366F1),
  'Health & Fitness' => const Color(0xFF14B8A6),
  'Travel' => const Color(0xFF06B6D4),
  'Investment' => const Color(0xFF22C55E),
  'Education' => const Color(0xFF0EA5E9),
  _ => muted,
};

IconData categoryIcon(String category) => switch (category) {
  'Gym' => Icons.fitness_center_rounded,
  'Food & Dining' => Icons.restaurant_rounded,
  'Shopping' => Icons.shopping_bag_outlined,
  'Bills & Utilities' => Icons.receipt_long_outlined,
  'Transportation' => Icons.directions_car_outlined,
  'Entertainment' => Icons.movie_outlined,
  'Health & Fitness' => Icons.favorite_border_rounded,
  'Travel' => Icons.flight_takeoff_rounded,
  'Investment' => Icons.trending_up_rounded,
  'Education' => Icons.school_outlined,
  _ => Icons.category_outlined,
};

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE6E9EE)),
    ),
    child: child,
  );
}

class EmptyMessage extends StatelessWidget {
  final String title;
  final String message;
  final Widget? action;
  const EmptyMessage({
    super.key,
    required this.title,
    required this.message,
    this.action,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
    child: Column(
      children: [
        const Icon(Icons.receipt_long_outlined, size: 40, color: sage),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: const TextStyle(color: muted),
          textAlign: TextAlign.center,
        ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: action),
      ],
    ),
  );
}
