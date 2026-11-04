import 'package:flutter/material.dart';

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
    await controller.restorePrivacy();
    runApp(FinanceTrackerApp(controller: controller));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: trackerTheme(),
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

class FinanceTrackerApp extends StatelessWidget {
  final TrackerController controller;
  const FinanceTrackerApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Finance Tracker',
    debugShowCheckedModeBanner: false,
    theme: trackerTheme(),
    home: TrackerHome(controller: controller),
  );
}
