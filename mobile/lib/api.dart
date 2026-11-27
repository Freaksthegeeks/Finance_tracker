import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
    Uint8List? audio,
    Duration timeout = const Duration(seconds: 60),
    Future<void>? abortTrigger,
  }) async {
    final uri = config.apiBase.resolve(path).replace(queryParameters: query);
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abortTrigger,
    )..headers['Accept'] = 'application/json';
    final readOnly = method == 'GET' || audio != null;
    if (audio != null) {
      request.headers['Content-Type'] = 'application/octet-stream';
      request.bodyBytes = audio;
    } else if (body != null) {
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
          readOnly
              ? 'The server returned an unexpected response (${response.statusCode}). Please try again.'
              : 'The server returned an unexpected response. Refresh before retrying; the change may have been saved.',
        );
      }
      if (audio != null &&
          response.statusCode == 503 &&
          payload is Map &&
          payload['detail'] is String) {
        throw ApiException(payload['detail'] as String);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode >= 500) {
          throw ApiException(
            readOnly
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
        readOnly
            ? 'The server is taking too long to respond. Pull down to retry.'
            : 'The request timed out. Refresh your expenses before retrying; the change may have been saved.',
      );
    } on http.ClientException {
      throw ApiException(
        readOnly
            ? 'Cannot reach the server. Check your connection and try again.'
            : 'Connection interrupted. Refresh before retrying; the change may have been saved.',
      );
    }
  }

  Future<String> transcribe(
    Uint8List audio, {
    required Future<void> abortTrigger,
  }) async {
    final payload = await _request(
      'POST',
      'voice/transcribe',
      audio: audio,
      timeout: const Duration(seconds: 30),
      abortTrigger: abortTrigger,
    );
    if (payload is Map && payload['transcript'] is String) {
      return payload['transcript'] as String;
    }
    throw const ApiException(
      'Voice transcription returned an unexpected response.',
    );
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

  Future<void> updateExpenseFields(int id, Map<String, Object> fields) async {
    await _request(
      'PUT',
      'expenses/$id',
      query: {'user_id': config.userId},
      body: fields,
    );
  }

  void close() => _client.close();

  Future<List<Loan>> loans() async => (await _request(
    'GET',
    'loans',
    query: {'user_id': config.userId},
  ) as List).map((e) => Loan.fromJson(e as Map<String, dynamic>)).toList();

  Future<Loan> addLoan({
    required String person,
    required String direction,
    required double amount,
    required DateTime date,
    String note = '',
    int? id,
  }) async => Loan.fromJson(
    await _request(
      id == null ? 'POST' : 'PUT',
      id == null ? 'loans' : 'loans/$id',
      query: id == null ? null : {'user_id': config.userId},
      body: {
        if (id == null) 'user_id': config.userId,
        'person': person.trim(),
        'direction': direction,
        'amount': amount,
        'date': dateValue(date),
        'note': note.trim(),
      },
    ) as Map<String, dynamic>,
  );

  Future<Loan> refundLoan(int id, bool refunded) async => Loan.fromJson(
    await _request(
      'PATCH',
      'loans/$id',
      query: {'user_id': config.userId},
      body: {'refunded': refunded},
    ) as Map<String, dynamic>,
  );

  Future<void> deleteLoan(int id) async {
    await _request('DELETE', 'loans/$id', query: {'user_id': config.userId});
  }
}
