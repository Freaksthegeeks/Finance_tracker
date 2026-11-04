import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

class TrackerController extends ChangeNotifier {
  final TrackerApi api;
  DateTime period = DateTime(DateTime.now().year, DateTime.now().month);
  DashboardStats? stats;
  List<Expense> expenses = [];
  bool loading = false;
  bool hidden = false;
  String? error;
  DateTime? updatedAt;
  int _generation = 0;
  bool _disposed = false;
  TrackerController(this.api);

  Future<void> restorePrivacy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      hidden = prefs.getBool('hide_amounts') ?? false;
      notifyListeners();
    } catch (_) {
      /* Preferences are optional; network workflows still work. */
    }
  }

  Future<void> togglePrivacy() async {
    hidden = !hidden;
    notifyListeners();
    try {
      await (await SharedPreferences.getInstance()).setBool(
        'hide_amounts',
        hidden,
      );
    } catch (_) {
      /* Session privacy remains active. */
    }
  }

  Future<void> selectPeriod(DateTime value) async {
    period = DateTime(value.year, value.month);
    stats = null;
    await refresh();
  }

  Future<void> refresh({bool background = false}) async {
    if (_disposed || (background && loading)) return;
    final generation = ++_generation;
    loading = true;
    if (!background) error = null;
    notifyListeners();
    try {
      final result = await Future.wait<Object>([
        api.stats(period),
        api.expenses(),
      ]);
      if (_disposed || generation != _generation) return;
      stats = result[0] as DashboardStats;
      expenses = result[1] as List<Expense>;
      updatedAt = DateTime.now();
      error = null;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e is ApiException
          ? e.message
          : 'Could not load your expenses. Please try again.';
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> save(ExpenseDraft draft, {int? id}) async {
    await api.save(draft, id: id);
    period = DateTime(draft.date.year, draft.date.month);
    stats = null;
    await refresh();
  }

  Future<void> delete(int id) async {
    await api.delete(id);
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    api.close();
    super.dispose();
  }
}
