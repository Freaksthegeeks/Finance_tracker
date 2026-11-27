import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'cache.dart';
import 'models.dart';
import 'voice_recording.dart';

enum BackendState { connecting, ready, unavailable }

enum SaveProgress { idle, connecting, saving }

class TrackerController extends ChangeNotifier {
  final TrackerApi api;
  final VoiceRecording Function() createVoiceRecording;
  final TrackerCache cache;
  final Duration connectionBudget;
  final Duration healthTimeout;
  final List<Duration> retryDelays;
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  DashboardStats? stats;
  List<Expense> expenses = [];
  List<Loan> loans = [];
  bool loansLoaded = false;
  String? loansError;
  double outstanding(String direction) => loans
      .where((loan) => loan.direction == direction && !loan.refunded)
      .fold(0.0, (sum, loan) => sum + loan.amount);
  bool loading = false;
  bool hidden = false;
  bool stale = true;
  String? error;
  DateTime? updatedAt;
  BackendState backendState = BackendState.unavailable;
  SaveProgress saveProgress = SaveProgress.idle;
  final _periods = <String, Map<String, dynamic>>{};
  DateTime? _expensesUpdatedAt;
  int _generation = 0;
  bool _disposed = false;
  bool _active = true;
  bool _writing = false;
  Future<void>? _connection;
  Future<void>? _restoration;
  Future<void>? _privacyRestoration;
  Completer<void>? _abortConnection;
  Timer? _retryTimer;
  Completer<void>? _retryWait;
  TrackerController(
    this.api, {
    TrackerCache? cache,
    this.createVoiceRecording = VoiceRecording.new,
    this.connectionBudget = const Duration(minutes: 2),
    this.healthTimeout = const Duration(seconds: 15),
    this.retryDelays = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 10),
    ],
  }) : cache = cache ?? TrackerCache(api.config);
  String get _periodKey => '${period.year}-${period.month}';
  String get savingLabel => saveProgress == SaveProgress.connecting
      ? 'Connecting… Saving expense.'
      : 'Saving expense…';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    unawaited(restorePrivacy());
    await refresh();
  }

  Future<void> restorePrivacy() => _privacyRestoration ??= _restorePrivacy();

  Future<void> _restorePrivacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      hidden = prefs.getBool('hide_amounts') ?? false;
      _notify();
    } catch (_) {
      /* Optional preferences. */
    }
  }

  Future<void> togglePrivacy() async {
    hidden = !hidden;
    _notify();
    try {
      await (await SharedPreferences.getInstance()).setBool(
        'hide_amounts',
        hidden,
      );
    } catch (_) {
      /* Session privacy remains active. */
    }
  }

  Future<void> restoreCache() => _restoration ??= _restoreCache();
  Future<void> _restoreCache() async {
    final data = await cache.load();
    await restorePrivacy(); // Apply privacy before exposing any cached amounts.
    if (_disposed || data == null) return;
    try {
      final restoredExpenses = (data['expenses'] as List)
          .map((e) => Expense.fromJson(e as Map<String, dynamic>))
          .toList();
      final restoredAt = DateTime.parse(data['updated_at'] as String);
      final restoredPeriods = <String, Map<String, dynamic>>{};
      for (final entry in (data['periods'] as Map<String, dynamic>).entries) {
        final value = entry.value as Map<String, dynamic>;
        DashboardStats.fromJson(value['stats'] as Map<String, dynamic>);
        DateTime.parse(value['updated_at'] as String);
        restoredPeriods[entry.key] = value;
      }
      expenses = restoredExpenses;
      loans = (data['loans'] as List? ?? [])
          .map((e) => Loan.fromJson(e as Map<String, dynamic>))
          .toList();
      loansLoaded = data['loans_loaded'] == true;
      _expensesUpdatedAt = restoredAt;
      _periods.addAll(restoredPeriods);
      _showPeriodCache();
      stale = true;
      _notify();
    } catch (_) {
      /* Ignore an invalid snapshot as a whole. */
    }
  }

  void _showPeriodCache() {
    final entry = _periods[_periodKey];
    stats = entry == null
        ? null
        : DashboardStats.fromJson(entry['stats'] as Map<String, dynamic>);
    updatedAt = entry == null
        ? _expensesUpdatedAt
        : DateTime.parse(entry['updated_at'] as String);
  }

  Future<void> _persist() async {
    if (_expensesUpdatedAt == null) return;
    try {
      await cache.store({
        'version': 1,
        'updated_at': _expensesUpdatedAt!.toIso8601String(),
        'expenses': expenses.map((e) => e.toJson()).toList(),
        'loans': loans.map((e) => e.toJson()).toList(),
        'loans_loaded': loansLoaded,
        'periods': _periods,
      });
    } catch (_) {
      // Local storage must never turn a server success into a failed operation.
    }
  }

  Future<void> selectPeriod(DateTime value) async {
    period = DateTime(value.year, value.month);
    _showPeriodCache();
    stale = true;
    await refresh();
  }

  /// All readers and writers share one bounded wake-up attempt.
  Future<void> ensureReady({bool force = false}) {
    if (_disposed || !_active) {
      return Future.error(
        const ApiException(
          'Connection paused. Please try again when the app is open.',
        ),
      );
    }
    if (_connection != null) return _connection!;
    if (!force && backendState == BackendState.ready) return Future.value();
    final abort = Completer<void>();
    _abortConnection = abort;
    final attempt = _connect(abort);
    late final Future<void> tracked;
    tracked = attempt.whenComplete(() {
      if (identical(_connection, tracked)) {
        _connection = null;
        _abortConnection = null;
      }
    });
    _connection = tracked;
    return tracked;
  }

  Future<void> _connect(Completer<void> abort) async {
    backendState = BackendState.connecting;
    _notify();
    final watch = Stopwatch()..start();
    var failures = 0;
    while (!_disposed &&
        _active &&
        !abort.isCompleted &&
        watch.elapsed < connectionBudget) {
      final remaining = connectionBudget - watch.elapsed;
      final probeAbort = Completer<void>();
      unawaited(
        abort.future.then((_) {
          if (!probeAbort.isCompleted) probeAbort.complete();
        }),
      );
      try {
        final ready = await api.health(
          timeout: Duration(
            microseconds: math.min(
              remaining.inMicroseconds,
              healthTimeout.inMicroseconds,
            ),
          ),
          abortTrigger: probeAbort.future,
        );
        if (_disposed || !_active || abort.isCompleted) break;
        if (ready) {
          backendState = BackendState.ready;
          _notify();
          return;
        }
      } catch (_) {
        /* Render startup HTML, network errors and degraded DB are retryable reads. */
      } finally {
        if (!probeAbort.isCompleted) probeAbort.complete();
      }
      if (_disposed || !_active || abort.isCompleted) break;
      final left = connectionBudget - watch.elapsed;
      if (left <= Duration.zero) break;
      final delay = retryDelays[math.min(failures++, retryDelays.length - 1)];
      final wait = Completer<void>();
      _retryWait = wait;
      _retryTimer = Timer(delay < left ? delay : left, () {
        if (!wait.isCompleted) wait.complete();
      });
      await wait.future;
      _retryTimer?.cancel();
      _retryTimer = null;
      _retryWait = null;
    }
    backendState = BackendState.unavailable;
    _notify();
    throw const ApiException(
      'Cannot connect to the server yet. Your details are kept. Please retry.',
    );
  }

  Future<void> setActive(bool value) async {
    _active = value;
    if (!value) {
      _cancelConnection();
      return;
    }
    // Let an interrupted attempt finish before starting another one.
    try {
      await _connection;
    } catch (_) {
      /* Expected on pause. */
    }
    if (_disposed || !_active) return;
    backendState = BackendState.unavailable;
    await refresh(background: true);
  }

  void _cancelConnection() {
    final abort = _abortConnection;
    if (abort != null && !abort.isCompleted) abort.complete();
    _retryTimer?.cancel();
    final wait = _retryWait;
    if (wait != null && !wait.isCompleted) wait.complete();
  }

  Future<void> refresh({bool background = false}) =>
      _refresh(background: background);
  Future<void> _refresh({
    bool background = false,
    bool afterWrite = false,
  }) async {
    if (_disposed ||
        !_active ||
        (_writing && !afterWrite) ||
        (background && loading)) {
      return;
    }
    final generation = ++_generation;
    final requestedPeriod = period;
    final key = _periodKey;
    loading = true;
    if (!background) error = null;
    _notify();
    try {
      // Health starts now; local disk restoration never delays the wake-up request.
      await Future.wait<void>([ensureReady(), restoreCache()]);
      if (_disposed || generation != _generation) return;
      final result = await Future.wait<Object>([
        api.stats(requestedPeriod),
        api.expenses(),
        _readLoans(),
      ]);
      if (_disposed || generation != _generation) return;
      stats = result[0] as DashboardStats;
      expenses = result[1] as List<Expense>;
      final loanResult = result[2];
      if (loanResult is List<Loan>) {
        loans = loanResult;
        loansLoaded = true;
        loansError = null;
      } else {
        loansError =
            'Could not refresh borrowed and lent money. Pull down to retry.';
      }
      updatedAt = DateTime.now();
      _expensesUpdatedAt = updatedAt;
      _periods.remove(key);
      _periods[key] = {
        'stats': stats!.toJson(),
        'updated_at': updatedAt!.toIso8601String(),
      };
      while (_periods.length > 12) {
        _periods.remove(_periods.keys.first);
      }
      stale = false;
      error = null;
      await _persist();
    } catch (e) {
      if (_disposed || generation != _generation) return;
      backendState = BackendState.unavailable;
      stale = true;
      error = e is ApiException
          ? e.message
          : 'Could not load your expenses. Please try again.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> save(ExpenseDraft draft, {int? id}) =>
      _write(() => api.save(draft, id: id), date: draft.date);
  Future<void> updateExpenseFields(
    int id,
    Map<String, Object> fields, {
    DateTime? date,
  }) => _write(
    () => api.updateExpenseFields(id, fields),
    date: date,
    successLabel: 'Expense saved',
  );
  Future<void> delete(int id) => _write(() => api.delete(id));
  Future<Object> _readLoans() async {
    try {
      return await api.loans();
    } catch (e) {
      return e;
    }
  }

  Future<void> addLoan({
    required String person,
    required String direction,
    required double amount,
    required DateTime date,
    String note = '',
    int? id,
  }) => _write(() async {
    final loan = await api.addLoan(
      person: person,
      direction: direction,
      amount: amount,
      date: date,
      note: note,
      id: id,
    );
    loans = [loan, ...loans.where((item) => item.id != loan.id)];
  }, successLabel: 'Entry saved');

  Future<void> refundLoan(Loan loan) => _write(() async {
    final updated = await api.refundLoan(loan.id, !loan.refunded);
    loans = loans.map((item) => item.id == loan.id ? updated : item).toList();
  }, successLabel: 'Entry updated');

  Future<void> deleteLoan(int id) => _write(() async {
    await api.deleteLoan(id);
    loans = loans.where((item) => item.id != id).toList();
  }, successLabel: 'Entry deleted');
  Future<void> _write(
    Future<void> Function() action, {
    DateTime? date,
    String? successLabel,
  }) async {
    if (_writing) {
      throw const ApiException('Another change is being saved. Please wait.');
    }
    _writing = true;
    ++_generation; // Ignore reads that began before this write.
    loading = false;
    saveProgress = SaveProgress.connecting;
    _notify();
    try {
      await Future.wait<void>([ensureReady(force: true), restoreCache()]);
      if (_disposed) {
        throw const ApiException('The app was closed before saving.');
      }
      saveProgress = SaveProgress.saving;
      _notify();
      await action(); // Never automatically replay a mutation.
      if (_disposed) return;
      if (date != null) period = DateTime(date.year, date.month);
      // Every cached period may contain an all-time total affected by this change.
      _periods.clear();
      stale = true;
      await _persist();
      saveProgress = SaveProgress.idle;
      await _refresh(afterWrite: true);
      if (error != null) {
        error =
            '${successLabel ?? (date == null ? 'Expense deleted' : 'Expense saved')}; refresh failed. $error';
      }
    } catch (_) {
      if (!_disposed) {
        backendState = BackendState.unavailable;
        stale = true;
      }
      rethrow;
    } finally {
      _writing = false;
      saveProgress = SaveProgress.idle;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _cancelConnection();
    api.close();
    super.dispose();
  }
}
