import 'dart:async';
import 'dart:convert';

import 'package:finance_tracker/api.dart';
import 'package:finance_tracker/config.dart';
import 'package:finance_tracker/models.dart';
import 'package:finance_tracker/tracker_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> statsJson(double total) => {
  'total_expenses': total,
  'this_month': total,
  'daily_average': total / 2,
  'active_categories': 1,
  'daily_pattern': [
    {'day': 'Nov 1', 'amount': total},
  ],
  'recent_expenses': [],
  'top_categories': [],
  'total_by_category': [],
};

void main() {
  test('normalizes PUBLIC_URL without duplicating the API prefix', () {
    for (final url in [
      'https://example.com',
      'https://example.com/',
      'https://example.com/api',
      'https://example.com/api/',
    ]) {
      expect(AppConfig(url).apiBase.toString(), 'https://example.com/api/');
    }
    expect(() => AppConfig('file:///tmp/api'), throwsFormatException);
    expect(
      () => AppConfig('https://user:secret@example.com'),
      throwsFormatException,
    );
  });

  test(
    'CRUD matches FastAPI paths, ownership, and local calendar dates',
    () async {
      final requests = <http.Request>[];
      final api = TrackerApi(
        AppConfig('https://example.com/', userId: 'existing-profile'),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      addTearDown(api.close);
      final draft = ExpenseDraft(
        amount: 120.50,
        category: 'Gym',
        description: ' Membership ',
        date: DateTime(2026, 11, 4),
      );
      await api.save(draft);
      await api.save(draft, id: 17);
      await api.delete(17);
      expect(requests.map((r) => r.method), ['POST', 'PUT', 'DELETE']);
      expect(requests[0].url.path, '/api/expenses');
      expect(jsonDecode(requests[0].body), {
        'user_id': 'existing-profile',
        'amount': 120.5,
        'category': 'Gym',
        'description': 'Membership',
        'date': '2026-11-04',
      });
      expect(requests[1].url.queryParameters, {'user_id': 'existing-profile'});
      expect(requests[2].url.path, '/api/expenses/17');
      expect(requests[2].url.queryParameters, {'user_id': 'existing-profile'});
      expect(requests.any((r) => r.url.path.contains('auth')), isFalse);
    },
  );

  test('API surfaces failures instead of treating them as success', () async {
    final api = TrackerApi(
      AppConfig('https://example.com'),
      client: MockClient(
        (_) async => http.Response('{"detail":"Expense not found"}', 404),
      ),
    );
    addTearDown(api.close);
    await expectLater(
      api.delete(9),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'Expense not found',
        ),
      ),
    );
  });

  test('late responses cannot overwrite a newly selected month', () async {
    final january = Completer<http.Response>();
    final api = TrackerApi(
      AppConfig('https://example.com'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/health')) {
          return http.Response('{"status":"ok","db_connected":true}', 200);
        }
        if (request.url.path.endsWith('/expenses')) {
          return http.Response('[]', 200);
        }
        if (request.url.queryParameters['month'] == '1') return january.future;
        return http.Response(jsonEncode(statsJson(200)), 200);
      }),
    );
    final controller = TrackerController(api)..period = DateTime(2026, 1);
    addTearDown(controller.dispose);
    final old = controller.refresh();
    await controller.selectPeriod(DateTime(2026, 2));
    january.complete(http.Response(jsonEncode(statsJson(100)), 200));
    await old;
    expect(controller.period.month, 2);
    expect(controller.stats!.total, 200);
    expect(controller.loading, isFalse);
  });

  test(
    'failed refresh preserves previously loaded data and reports an error',
    () async {
      var fail = false;
      final controller = TrackerController(
        TrackerApi(
          AppConfig('https://example.com'),
          client: MockClient((request) async {
            if (request.url.path.endsWith('/health')) {
              return http.Response('{"status":"ok","db_connected":true}', 200);
            }
            if (fail) return http.Response('{}', 503);
            return http.Response(
              request.url.path.endsWith('/expenses')
                  ? '[]'
                  : jsonEncode(statsJson(150)),
              200,
            );
          }),
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      fail = true;
      await controller.refresh();
      expect(controller.stats!.total, 150);
      expect(controller.error, isNotNull);
      expect(controller.loading, isFalse);
    },
  );
}
