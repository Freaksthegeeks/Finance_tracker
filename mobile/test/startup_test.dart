import 'dart:async';
import 'dart:convert';

import 'package:finance_tracker/api.dart';
import 'package:finance_tracker/cache.dart';
import 'package:finance_tracker/config.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/models.dart';
import 'package:finance_tracker/tracker_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_test.dart' show statsJson;

final config = AppConfig('https://example.com', userId: 'profile');
final draft = ExpenseDraft(
  amount: 10,
  category: 'Gym',
  description: 'Test expense',
  date: DateTime(2026, 11, 4),
);
http.Response ready() =>
    http.Response('{"status":"ok","db_connected":true}', 200);
http.Response data(http.Request request, [double total = 120]) => http.Response(
  jsonEncode(
    request.url.path.endsWith('/expenses')
        ? [
            {
              'id': 1,
              'amount': total,
              'category': 'Gym',
              'description': 'Cached membership',
              'date': '2026-11-02',
            },
          ]
        : statsJson(total),
  ),
  200,
);

class DelayedCache extends TrackerCache {
  final value = Completer<Map<String, dynamic>?>();
  DelayedCache() : super(config);
  @override
  Future<Map<String, dynamic>?> load() => value.future;
}

class FailingCache extends TrackerCache {
  FailingCache() : super(config);
  @override
  Future<void> store(Map<String, dynamic> snapshot) async {
    throw StateError('Storage full');
  }
}

class HoldingClient extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  http.BaseRequest? request;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    this.request = request;
    return response.future;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('wake request begins before disk cache restoration finishes', () async {
    var probes = 0;
    final cache = DelayedCache();
    final controller = TrackerController(
      TrackerApi(
        config,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/health')) {
            probes++;
            return ready();
          }
          return data(r);
        }),
      ),
      cache: cache,
    );
    addTearDown(controller.dispose);
    final opening = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(probes, 1);
    cache.value.complete(null);
    await opening;
    expect(controller.stats!.total, 120);
  });

  test(
    'snapshot survives a new controller and is isolated by URL and user',
    () async {
      final first = TrackerController(
        TrackerApi(
          config,
          client: MockClient(
            (r) async => r.url.path.endsWith('/health') ? ready() : data(r),
          ),
        ),
      )..period = DateTime(2026, 11);
      await first.refresh();
      first.dispose();
      await (await SharedPreferences.getInstance()).setBool(
        'hide_amounts',
        true,
      );
      final second = TrackerController(TrackerApi(config))
        ..period = DateTime(2026, 11);
      addTearDown(second.dispose);
      await second.restoreCache();
      expect(second.stats!.total, 120);
      expect(second.hidden, isTrue);
      expect(second.expenses.single.description, 'Cached membership');
      expect(second.stale, isTrue);
      expect(second.updatedAt, isNotNull);
      expect(
        await TrackerCache(AppConfig('https://example.com', userId: 'other'))
            .load(),
        isNull,
      );
      expect(
        await TrackerCache(
          AppConfig('https://other.example.com', userId: 'profile'),
        ).load(),
        isNull,
      );
    },
  );

  test('corrupt cache is ignored and server data still loads', () async {
    SharedPreferences.setMockInitialValues({
      TrackerCache(config).key: '{broken',
    });
    final controller = TrackerController(
      TrackerApi(
        config,
        client: MockClient(
          (r) async => r.url.path.endsWith('/health') ? ready() : data(r),
        ),
      ),
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    expect(controller.stats!.total, 120);
    expect(controller.error, isNull);
  });

  test(
    'cached data stays visible while connecting then fresh data replaces it',
    () async {
      final first = TrackerController(
        TrackerApi(
          config,
          client: MockClient(
            (r) async => r.url.path.endsWith('/health') ? ready() : data(r),
          ),
        ),
      )..period = DateTime(2026, 11);
      await first.refresh();
      first.dispose();
      final health = Completer<http.Response>();
      final second = TrackerController(
        TrackerApi(
          config,
          client: MockClient(
            (r) async =>
                r.url.path.endsWith('/health') ? health.future : data(r, 250),
          ),
        ),
      )..period = DateTime(2026, 11);
      addTearDown(second.dispose);
      final opening = second.start();
      await second.restoreCache();
      expect(second.stats!.total, 120);
      expect(second.backendState, BackendState.connecting);
      health.complete(ready());
      await opening;
      expect(second.stats!.total, 250);
      expect(second.stale, isFalse);
    },
  );

  test(
    'startup and save share health, and no write occurs before readiness',
    () async {
      final health = Completer<http.Response>();
      var probes = 0;
      var writes = 0;
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/health')) {
              probes++;
              return health.future;
            }
            if (r.method == 'POST') {
              writes++;
              return http.Response('{}', 200);
            }
            return data(r);
          }),
        ),
      );
      addTearDown(controller.dispose);
      final opening = controller.start();
      final saving = controller.save(draft);
      await Future<void>.delayed(Duration.zero);
      expect(probes, 1);
      expect(writes, 0);
      expect(controller.saveProgress, SaveProgress.connecting);
      health.complete(ready());
      await Future.wait([opening, saving]);
      expect(writes, 1);
      expect(controller.saveProgress, SaveProgress.idle);
    },
  );

  test(
    'startup HTML and degraded health retry without replaying writes',
    () async {
      var probes = 0;
      var writes = 0;
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/health')) {
              probes++;
              if (probes == 1) {
                return http.Response('<html>Starting</html>', 200);
              }
              if (probes == 2) {
                return http.Response(
                  '{"status":"degraded","db_connected":false}',
                  200,
                );
              }
              return ready();
            }
            if (r.method == 'POST') {
              writes++;
              return http.Response('{}', 200);
            }
            return data(r);
          }),
        ),
        retryDelays: const [Duration(milliseconds: 1)],
      );
      addTearDown(controller.dispose);
      await controller.save(draft);
      expect(probes, 3);
      expect(writes, 1);
    },
  );

  test(
    'connection budget expiry prevents writes and allows manual retry',
    () async {
      var writes = 0;
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient((r) async {
            if (r.method == 'POST') writes++;
            return ready();
          }),
        ),
        connectionBudget: Duration.zero,
      );
      addTearDown(controller.dispose);
      await expectLater(controller.save(draft), throwsA(isA<ApiException>()));
      expect(writes, 0);
      expect(controller.backendState, BackendState.unavailable);
      expect(controller.saveProgress, SaveProgress.idle);
    },
  );

  test(
    'confirmed write remains successful when subsequent read fails',
    () async {
      var writes = 0;
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/health')) return ready();
            if (r.method == 'POST') {
              writes++;
              return http.Response('{}', 200);
            }
            return http.Response('{}', 503);
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.save(draft);
      expect(writes, 1);
      expect(controller.error, startsWith('Expense saved; refresh failed.'));
      expect(controller.stale, isTrue);
    },
  );

  test('ambiguous mutation timeout is never retried automatically', () async {
    var writes = 0;
    final controller = TrackerController(
      TrackerApi(
        config,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/health')) return ready();
          writes++;
          throw TimeoutException('connection dropped');
        }),
      ),
    );
    addTearDown(controller.dispose);
    await expectLater(
      controller.save(draft),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('may have been saved'),
        ),
      ),
    );
    expect(writes, 1);
  });

  test('pause cancels retry delay, resume checks health again', () async {
    var probes = 0;
    final controller = TrackerController(
      TrackerApi(
        config,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/health')) {
            probes++;
            return probes == 1 ? http.Response('{}', 503) : ready();
          }
          return data(r);
        }),
      ),
      retryDelays: const [Duration(seconds: 30)],
    );
    addTearDown(controller.dispose);
    final opening = controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await controller.setActive(false);
    await opening;
    expect(probes, 1);
    await controller.setActive(true);
    expect(probes, 2);
    expect(controller.stats!.total, 120);
  });

  test(
    'cache storage failure does not fail reads or confirmed writes',
    () async {
      var writes = 0;
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/health')) return ready();
            if (r.method == 'POST') {
              writes++;
              return http.Response('{}', 200);
            }
            return data(r);
          }),
        ),
        cache: FailingCache(),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.stats!.total, 120);
      expect(controller.error, isNull);
      await controller.save(draft);
      expect(writes, 1);
      expect(controller.error, isNull);
    },
  );

  test(
    'cache keeps only twelve periods and restores the selected period',
    () async {
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient(
            (r) async => r.url.path.endsWith('/health') ? ready() : data(r),
          ),
        ),
      );
      addTearDown(controller.dispose);
      for (var month = 1; month <= 13; month++) {
        await controller.selectPeriod(DateTime(2026, month));
      }
      final snapshot = (await TrackerCache(config).load())!;
      final periods = snapshot['periods'] as Map;
      expect(periods.length, 12);
      expect(periods.containsKey('2026-1'), isFalse);
      expect(periods.containsKey('2027-1'), isTrue);
      final restored = TrackerController(TrackerApi(config))
        ..period = DateTime(2027, 1);
      addTearDown(restored.dispose);
      await restored.restoreCache();
      expect(restored.stats!.total, 120);
    },
  );

  test(
    'dispose aborts an active health probe without updating the screen',
    () async {
      final client = HoldingClient();
      final controller = TrackerController(TrackerApi(config, client: client));
      var notifications = 0;
      controller.addListener(() => notifications++);
      final opening = controller.start();
      final request = client.request! as http.AbortableRequest;
      controller.dispose();
      final before = notifications;
      await request.abortTrigger;
      client.response.complete(
        http.StreamedResponse(
          Stream.value(utf8.encode('{"status":"ok","db_connected":true}')),
          200,
        ),
      );
      await opening;
      expect(notifications, before);
      expect(controller.stats, isNull);
    },
  );

  testWidgets(
    'form keeps details while connecting and until a confirmed write',
    (tester) async {
      final health = Completer<http.Response>();
      final written = Completer<http.Response>();
      var writes = 0;
      final controller = TrackerController(
        TrackerApi(
          config,
          client: MockClient((r) async {
            if (r.url.path.endsWith('/health')) return health.future;
            if (r.method == 'POST') {
              writes++;
              return written.future;
            }
            return data(r);
          }),
        ),
      );
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(FinanceTrackerApp(controller: controller));
      await tester.pump();
      await tester.tap(find.byTooltip('Add expense'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '42');
      await tester.enterText(fields.at(1), 'Keep this draft');
      final save = find.widgetWithText(FilledButton, 'Save expense');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(find.text('Connecting… Saving expense.'), findsOneWidget);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(writes, 0);
      health.complete(ready());
      await tester.pump();
      await tester.pump();
      expect(writes, 1);
      expect(find.text('Saving expense…'), findsOneWidget);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(find.text('Expense added'), findsNothing);
      written.complete(http.Response('{}', 200));
      await tester.pumpAndSettle();
      expect(find.text('Expense added'), findsOneWidget);
      expect(find.text('Keep this draft'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed save preserves entered details and enables retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    final controller = TrackerController(
      TrackerApi(
        config,
        client: MockClient((r) async {
          if (r.url.path.endsWith('/health')) return ready();
          if (r.method == 'POST') {
            writes++;
            return http.Response('{"detail":"Rejected"}', 400);
          }
          return data(r);
        }),
      ),
    );
    await tester.pumpWidget(FinanceTrackerApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add expense'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), '42');
    await tester.enterText(fields.at(1), 'Keep on failure');
    final save = find.widgetWithText(FilledButton, 'Save expense');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Rejected'), findsOneWidget);
    expect(find.text('Keep on failure'), findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
    expect(writes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
