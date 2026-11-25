import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'config.dart';
import 'tracker_controller.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = await AppConfig.load();
    final controller = TrackerController(TrackerApi(config));
    runApp(FinanceTrackerApp(controller: controller));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: trackerTheme(),
        darkTheme: trackerTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Mobile configuration is missing or invalid. Run dart tool/configure.dart from the mobile folder, then rebuild.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinanceTrackerApp extends StatefulWidget {
  final TrackerController controller;
  const FinanceTrackerApp({super.key, required this.controller});

  @override
  State<FinanceTrackerApp> createState() => _FinanceTrackerAppState();
}

class _FinanceTrackerAppState extends State<FinanceTrackerApp> {
  static const _preferenceKey = 'tracker_dark_theme';
  ThemeMode _themeMode = ThemeMode.system;
  Future<void> _themeWrites = Future.value();

  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dark = prefs.getBool(_preferenceKey);
      if (mounted && dark != null && _themeMode == ThemeMode.system) {
        setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
      }
    } catch (_) {
      // The system theme is available even if preferences cannot be read.
    }
  }

  void _setDarkTheme(bool dark) {
    setState(() => _themeMode = dark ? ThemeMode.dark : ThemeMode.light);
    _themeWrites = _themeWrites.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_preferenceKey, dark);
      } catch (_) {
        // Keep the selected theme active for this session.
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Finance Tracker',
    debugShowCheckedModeBanner: false,
    theme: trackerTheme(),
    darkTheme: trackerTheme(Brightness.dark),
    themeMode: _themeMode,
    home: TrackerHome(
      controller: widget.controller,
      onThemeChanged: _setDarkTheme,
    ),
  );
}
