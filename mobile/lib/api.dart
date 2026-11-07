import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  const ApiException(this.message);
  @override
  String toString() => message;
}

class TrackerApi {
  final AppConfig config;
  final http.Client _client;
  TrackerApi(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Duration timeout = const Duration(seconds: 60),
    Future<void>? abortTrigger,
  }) async {
    final uri = config.apiBase.resolve(path).replace(queryParameters: query);
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abortTrigger,
    )..headers['Accept'] = 'application/json';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await (() async => http.Response.fromStream(
        await _client.send(request),
      ))().timeout(timeout);
      dynamic payload;
      try {
        payload = jsonDecode(response.body);
      } on FormatException {
        throw ApiException(
          method == 'GET'
              ? 'The server returned an unexpected response (${response.statusCode}). Please try again.'
              : 'The server returned an unexpected response. Refresh before retrying; the change may have been saved.',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode >= 500) {
          throw ApiException(
            method == 'GET'
                ? 'The server is temporarily unavailable. Please try again.'
                : 'The server could not confirm the change. Refresh before retrying; it may have been saved.',
          );
        }
        final detail = payload is Map ? payload['detail'] : null;
        throw ApiException(
          detail is String
              ? detail
              : 'Unable to complete this request (${response.statusCode}).',
        );
      }
      return payload;
    } on TimeoutException {
      throw ApiException(
        method == 'GET'
            ? 'The server is taking too long to respond. Pull down to retry.'
            : 'The request timed out. Refresh your expenses before retrying; the change may have been saved.',
      );
    } on http.ClientException {
      throw ApiException(
        method == 'GET'
            ? 'Cannot reach the server. Check your connection and try again.'
            : 'Connection interrupted. Refresh before retrying; the change may have been saved.',
      );
    }
  }

  Future<bool> health({
    Duration timeout = const Duration(seconds: 15),
    Future<void>? abortTrigger,
  }) async {
    final payload = await _request(
      'GET',
      'health',
      timeout: timeout,
      abortTrigger: abortTrigger,
    );
    return payload is Map &&
        payload['status'] == 'ok' &&
        payload['db_connected'] == true;
  }

  Future<DashboardStats> stats(DateTime period) async =>
      DashboardStats.fromJson(
        await _request(
          'GET',
          'dashboard/stats',
          query: {
            'user_id': config.userId,
            'month': '${period.month}',
            'year': '${period.year}',
          },
        ) as Map<String, dynamic>,
      );
  Future<List<Expense>> expenses() async => (await _request(
    'GET',
    'expenses',
    query: {'user_id': config.userId},
  ) as List).map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
  Future<void> save(ExpenseDraft draft, {int? id}) async {
    await _request(
      id == null ? 'POST' : 'PUT',
      id == null ? 'expenses' : 'expenses/$id',
      query: id == null ? null : {'user_id': config.userId},
      body: {...draft.toJson(), if (id == null) 'user_id': config.userId},
    );
  }

  Future<void> delete(int id) async {
    await _request('DELETE', 'expenses/$id', query: {'user_id': config.userId});
  }

  void close() => _client.close();
}
