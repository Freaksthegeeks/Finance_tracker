import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:finance_tracker/api.dart';
import 'package:finance_tracker/config.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/tracker_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestBackend {
  final requests = <http.Request>[];
  final expenses = <Map<String, dynamic>>[
    {
      'id': 1,
      'amount': 1250.0,
      'category': 'Gym',
      'description': 'Monthly membership',
      'date': '2026-11-02',
    },
    {
      'id': 2,
      'amount': 380.0,
      'category': 'Food & Dining',
      'description': 'Lunch with friends',
      'date': '2026-11-03',
    },
  ];
  late final controller = TrackerController(
    TrackerApi(
      AppConfig('https://example.com'),
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"status":"ok","db_connected":true}', 200);
        }
        if (request.method == 'POST') {
          expenses.add({
            ...jsonDecode(request.body) as Map<String, dynamic>,
            'id': 3,
          });
          return http.Response(jsonEncode(expenses.last), 200);
        }
        if (request.method == 'PUT') {
          final id = int.parse(request.url.pathSegments.last);
          expenses[expenses.indexWhere((e) => e['id'] == id)].addAll(
            jsonDecode(request.body) as Map<String, dynamic>,
          );
          return http.Response('{}', 200);
        }
        if (request.method == 'DELETE') {
          expenses.removeWhere(
            (e) => '${e['id']}' == request.url.pathSegments.last,
          );
          return http.Response('{"success":true}', 200);
        }
        if (request.url.path.endsWith('/expenses')) {
          return http.Response(jsonEncode(expenses), 200);
        }
        return http.Response(
          jsonEncode({
            'total_expenses': 1630,
            'this_month': 1630,
            'daily_average': 407.5,
            'active_categories': 2,
            'daily_pattern': List.generate(
              30,
              (i) => {
                'day': 'Nov ${i + 1}',
                'amount': i == 1
                    ? 1250
                    : i == 2
                    ? 380
                    : 0,
              },
            ),
            'recent_expenses': expenses,
            'top_categories': [
              {'category': 'Gym', 'total': 1250, 'count': 1},
              {'category': 'Food & Dining', 'total': 380, 'count': 1},
            ],
            'total_by_category': [
              {'category': 'Gym', 'total': 1250, 'count': 1},
              {'category': 'Food & Dining', 'total': 380, 'count': 1},
            ],
          }),
          200,
        );
      }),
    ),
  )..period = DateTime(2026, 11);
}

Future<void> start(
  WidgetTester tester,
  TestBackend backend, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('capture'),
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: FinanceTrackerApp(controller: backend.controller),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_SCREENSHOTS')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'opens dashboard without authentication and supports privacy and navigation',
    (tester) async {
      final backend = TestBackend();
      await start(tester, backend);
      expect(find.text('Total Expenses'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
      expect(
        backend.requests.any((r) => r.url.path.contains('/auth')),
        isFalse,
      );
      await capture(tester, 'dashboard');
      await tester.tap(find.byTooltip('Hide amounts'));
      await tester.pumpAndSettle();
      expect(find.text('Spending chart hidden'), findsOneWidget);
      expect(find.text('••••••'), findsWidgets);
      await tester.tap(find.text('All Expenses').last);
      await tester.pumpAndSettle();
      await capture(tester, 'history');
      await tester.enterText(
        find.widgetWithText(TextField, 'Search expenses'),
        'Lunch',
      );
      await tester.pumpAndSettle();
      expect(find.text('Lunch with friends'), findsOneWidget);
      expect(find.text('Monthly membership'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('validates and saves a new expense exactly once', (tester) async {
    final backend = TestBackend();
    await start(tester, backend);
    await tester.tap(find.text('Add Expense').last);
    await tester.pumpAndSettle();
    await capture(tester, 'add_expense');
    final save = find.widgetWithText(FilledButton, 'Add Expense');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    expect(find.text('Enter a description'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '250.50');
    await tester.enterText(fields.at(1), 'New expense');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final writes = backend.requests.where((r) => r.method == 'POST');
    expect(writes.length, 1);
    expect(jsonDecode(writes.single.body)['amount'], 250.5);
    expect(find.text('Expense added successfully'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('edits expense and requires confirmation before deletion', (
    tester,
  ) async {
    final backend = TestBackend();
    await start(tester, backend);
    await tester.tap(find.text('All Expenses').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Expense actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '1500');
    final save = find.widgetWithText(FilledButton, 'Save Changes');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.method == 'PUT').length, 1);
    await tester.tap(find.byTooltip('Expense actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.method == 'DELETE'), isEmpty);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(backend.expenses.length, 2);
    await tester.tap(find.byTooltip('Expense actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.method == 'DELETE').length, 1);
    expect(backend.expenses.length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dashboard fits a narrow mobile screen', (tester) async {
    await start(tester, TestBackend(), size: const Size(320, 740));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
