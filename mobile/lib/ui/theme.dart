import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models.dart';

const _light = {
  'bg': Color(0xFFF5F7F5),
  'surface': Color(0xFFFFFFFF),
  'surface-2': Color(0xFFEEF1EE),
  'line': Color(0xFFE3E7E3),
  'ink': Color(0xFF17201B),
  'ink-muted': Color(0xFF5C6A62),
  'ink-faint': Color(0xFF8A968F),
  'brand': Color(0xFF3F7A64),
  'brand-soft': Color(0xFFE4EFE9),
  'brand-ink': Color(0xFF30604D),
  'on-brand': Color(0xFFFFFFFF),
  'owe': Color(0xFF9A4F1C),
  'owe-soft': Color(0xFFF8EBE1),
  'danger': Color(0xFFB3261E),
  'cat-gym': Color(0xFF7C5CC4),
  'cat-food': Color(0xFFB0701A),
  'cat-shopping': Color(0xFFC2417A),
  'cat-bills': Color(0xFF3B6FD1),
  'cat-transport': Color(0xFF2F8A66),
  'cat-entertainment': Color(0xFF5B5FC7),
  'cat-health': Color(0xFF1F8585),
  'cat-travel': Color(0xFF1B7AA0),
  'cat-investment': Color(0xFF4A8429),
  'cat-education': Color(0xFF2F70AD),
  'cat-others': Color(0xFF6B7570),
};
const _dark = {
  'bg': Color(0xFF111412),
  'surface': Color(0xFF181C1A),
  'surface-2': Color(0xFF222724),
  'line': Color(0xFF2B312E),
  'ink': Color(0xFFE9EEEA),
  'ink-muted': Color(0xFF9AA7A0),
  'ink-faint': Color(0xFF6C7872),
  'brand': Color(0xFF7CC2A6),
  'brand-soft': Color(0xFF1D3128),
  'brand-ink': Color(0xFFA6DCC5),
  'on-brand': Color(0xFF0D1A14),
  'owe': Color(0xFFF0A776),
  'owe-soft': Color(0xFF33241A),
  'danger': Color(0xFFF2B8B5),
  'cat-gym': Color(0xFFB9A2F0),
  'cat-food': Color(0xFFE8B46A),
  'cat-shopping': Color(0xFFF093BB),
  'cat-bills': Color(0xFF8FB2F5),
  'cat-transport': Color(0xFF79CFA9),
  'cat-entertainment': Color(0xFFA8ABF2),
  'cat-health': Color(0xFF6FD0CF),
  'cat-travel': Color(0xFF71C3E6),
  'cat-investment': Color(0xFF9FD47E),
  'cat-education': Color(0xFF86B8EA),
  'cat-others': Color(0xFFA3ADA8),
};

Map<String, Color> _palette(Brightness brightness) =>
    brightness == Brightness.dark ? _dark : _light;

ThemeData trackerTheme([Brightness brightness = Brightness.light]) {
  final palette = _palette(brightness);
  Color token(String key) => palette[key]!;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: token('brand'),
    onPrimary: token('on-brand'),
    primaryContainer: token('brand-soft'),
    onPrimaryContainer: token('brand-ink'),
    secondary: token('owe'),
    onSecondary: token('surface'),
    secondaryContainer: token('owe-soft'),
    onSecondaryContainer: token('owe'),
    error: token('danger'),
    onError: token('surface'),
    errorContainer: token('owe-soft'),
    surface: token('surface'),
    onSurface: token('ink'),
    surfaceContainerHighest: token('surface-2'),
    onSurfaceVariant: token('ink-muted'),
    outline: token('ink-faint'),
    outlineVariant: token('line'),
    scrim: brightness == Brightness.dark
        ? const Color(0x99000000)
        : const Color(0x66101613),
  );
  TextStyle type(
    double size,
    double line, {
    bool bold = false,
    bool muted = false,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: 'TrackerSans',
    fontSize: size,
    height: line / size,
    letterSpacing: spacing,
    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
    color: muted ? scheme.onSurfaceVariant : scheme.onSurface,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: token('bg'),
    fontFamily: 'TrackerSans',
    appBarTheme: AppBarTheme(
      backgroundColor: token('bg'),
      foregroundColor: scheme.onSurface,
      titleTextStyle: type(
        22,
        28,
        bold: true,
        spacing: -.3,
      ).copyWith(fontFamily: 'TrackerSans'),
      scrolledUnderElevation: 0,
    ),
    textTheme: TextTheme(
      headlineLarge: type(36, 40, bold: true, spacing: -.8),
      headlineSmall: type(20, 26, bold: true, spacing: -.3),
      titleLarge: type(22, 28, bold: true, spacing: -.3),
      titleMedium: type(16, 22, bold: true),
      bodyMedium: type(15, 22),
      bodySmall: type(12, 16, muted: true),
      labelLarge: type(13, 18, bold: true),
      labelSmall: type(11, 14, bold: true, spacing: .8),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: .2),
      selectionHandleColor: scheme.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: border,
      enabledBorder: border,
      contentPadding: const EdgeInsets.all(12),
      hintStyle: type(15, 22, muted: true),
      errorStyle: type(12, 16).copyWith(color: scheme.error),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHighest,
      selectedColor: scheme.primaryContainer,
      labelStyle: type(13, 18, bold: true, muted: true),
      secondaryLabelStyle: type(
        13,
        18,
        bold: true,
      ).copyWith(color: scheme.onPrimaryContainer),
      checkmarkColor: scheme.onPrimaryContainer,
      side: BorderSide.none,
      shape: const StadiumBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 80,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => type(
          12,
          16,
          bold: states.contains(WidgetState.selected),
          muted: !states.contains(WidgetState.selected),
        ).copyWith(fontFamily: 'TrackerSans'),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
        ),
        textStyle: WidgetStatePropertyAll(type(13, 18, bold: true)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: const CircleBorder(),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      modalElevation: 8,
      dragHandleColor: scheme.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.onSurface,
      contentTextStyle: type(15, 22).copyWith(color: token('bg')),
      actionTextColor: brightness == Brightness.dark
          ? scheme.onPrimaryContainer
          : scheme.primaryContainer,
    ),
  );
}

Color categoryColor(BuildContext context, String category) {
  const names = [
    'gym',
    'food',
    'shopping',
    'bills',
    'transport',
    'entertainment',
    'health',
    'travel',
    'investment',
    'education',
    'others',
  ];
  final index = categories.indexOf(category);
  return _palette(
    Theme.of(context).brightness,
  )['cat-${names[index < 0 ? names.length - 1 : index]}']!;
}

class CategoryIcon extends StatelessWidget {
  final String category;
  const CategoryIcon({super.key, required this.category});

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(
      categoryIcon(category),
      color: categoryColor(context, category),
      size: 20,
    ),
  );
}

IconData categoryIcon(String category) => switch (category) {
  'Gym' => LucideIcons.dumbbell,
  'Food & Dining' => LucideIcons.utensils,
  'Shopping' => LucideIcons.shoppingBag,
  'Bills & Utilities' => LucideIcons.receipt,
  'Transportation' => LucideIcons.car,
  'Entertainment' => LucideIcons.clapperboard,
  'Health & Fitness' => LucideIcons.heartPulse,
  'Travel' => LucideIcons.plane,
  'Investment' => LucideIcons.trendingUp,
  'Education' => LucideIcons.graduationCap,
  _ => LucideIcons.layoutGrid,
};

class Panel extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color ?? Theme.of(context).colorScheme.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: double.infinity,
      child: Padding(padding: padding, child: child),
    ),
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
        CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            LucideIcons.receipt,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          message,
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (action != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: action),
      ],
    ),
  );
}
