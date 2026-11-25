import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../tracker_controller.dart';
import 'expense_form.dart';
import 'loans.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'spending_chart.dart';
import 'theme.dart';

enum DateScope { all, month, year }

class TrackerHome extends StatefulWidget {
  final TrackerController controller;
  final ValueChanged<bool> onThemeChanged;
  const TrackerHome({
    super.key,
    required this.controller,
    required this.onThemeChanged,
  });
  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> with WidgetsBindingObserver {
  TrackerController get c => widget.controller;
  Timer? _timer;
  int _tab = 0;
  String _query = '';
  String _category = 'All';
  DateScope _scope = DateScope.month;
  final _search = TextEditingController();
  final _deleting = <int>{};
  final _pendingLoans = <int>{};
  int _pendingActions = 0;
  Future<void> _writes = Future.value();
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(c.start());
    unawaited(_restoreCategory());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_active) unawaited(c.refresh(background: true));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    unawaited(c.setActive(_active));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _search.dispose();
    c.dispose();
    super.dispose();
  }

  Future<void> _choosePeriod() async {
    var month = c.period.month;
    var year = c.period.year;
    final years = {
      for (var y = DateTime.now().year - 10; y <= DateTime.now().year + 5; y++)
        y,
      year,
      ...c.expenses.map((e) => e.date.year),
    }.toList()..sort((a, b) => b.compareTo(a));
    final period = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose a month',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: month,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Month'),
                        items: List.generate(
                          12,
                          (i) => DropdownMenuItem(
                            value: i + 1,
                            child: Text(
                              DateFormat.MMMM().format(DateTime(2000, i + 1)),
                            ),
                          ),
                        ),
                        onChanged: (v) => update(() => month = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: year,
                        decoration: const InputDecoration(labelText: 'Year'),
                        items: years
                            .map(
                              (y) =>
                                  DropdownMenuItem(value: y, child: Text('$y')),
                            )
                            .toList(),
                        onChanged: (v) => update(() => year = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, DateTime(year, month)),
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (period != null && mounted) unawaited(c.selectPeriod(period));
  }

  void _undoable(
    String label,
    VoidCallback restore,
    Future<void> Function() commit,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    if (_pendingActions == 0) messenger.clearSnackBars();
    _pendingActions++;
    final notice = messenger.showSnackBar(
      SnackBar(
        content: Text(label),
        duration: const Duration(seconds: 5),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => setState(restore),
        ),
      ),
    );
    unawaited(
      notice.closed.then((reason) {
        _pendingActions--;
        if (!mounted || reason == SnackBarClosedReason.action) return;
        _writes = _writes.then((_) async {
          if (!mounted) return;
          try {
            await commit();
          } catch (_) {
            if (mounted) {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Could not save the change. Please try again.'),
                ),
              );
            }
          } finally {
            if (mounted) setState(restore);
          }
        });
      }),
    );
  }

  String? _lastCategory;

  Future<void> _restoreCategory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastCategory ??= prefs.getString('last_expense_category');
    } catch (_) {
      // Continue with the default category when preferences are unavailable.
    }
  }

  Future<void> _rememberCategory(String category) async {
    _lastCategory = category;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_expense_category', category);
    } catch (_) {
      // Saving the preference must not fail a confirmed write.
    }
  }

  void _delete(Expense expense) {
    setState(() => _deleting.add(expense.id));
    _undoable(
      'Expense deleted',
      () => _deleting.remove(expense.id),
      () => c.delete(expense.id),
    );
  }

  Future<void> _expenseSheet([Expense? expense]) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: SafeArea(
        top: false,
        child: ExpenseForm(
          controller: c,
          expense: expense,
          initialCategory: _lastCategory,
          onSave: (draft) async {
            await c.save(draft, id: expense?.id);
            await _rememberCategory(draft.category);
          },
          onSaved: () => Navigator.pop(sheetContext),
          onDelete: expense == null
              ? null
              : () {
                  Navigator.pop(sheetContext);
                  _delete(expense);
                },
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final titles = ['Home', 'Activity', 'Loans'];
      final largeHeader =
          _tab != 2 && MediaQuery.textScalerOf(context).scale(14) > 18;
      final offline = c.error != null || (_tab == 2 && c.loansError != null);
      return Scaffold(
        appBar: AppBar(
          titleSpacing: 16,
          toolbarHeight: largeHeader ? 96 : 48,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Tooltip(
                message: 'Dark theme',
                excludeFromSemantics: true,
                child: Semantics(
                  label: 'Dark theme',
                  child: Switch(
                    value: theme.brightness == Brightness.dark,
                    onChanged: widget.onThemeChanged,
                    thumbIcon: WidgetStateProperty.resolveWith(
                      (states) => Icon(
                        states.contains(WidgetState.selected)
                            ? LucideIcons.moon
                            : LucideIcons.sun,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(titles[_tab], maxLines: 1)),
                  if (_tab != 2 && !largeHeader) _periodPill(context),
                  IconButton(
                    tooltip: c.hidden ? 'Show amounts' : 'Hide amounts',
                    onPressed: c.togglePrivacy,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(c.hidden ? LucideIcons.eyeOff : LucideIcons.eye),
                  ),
                ],
              ),
              if (largeHeader) _periodPill(context, fullDate: true),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: c.refresh,
          child: ListView(
            key: PageStorageKey(_tab),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            children: [
              if (offline || c.backendState == BackendState.connecting)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Material(
                    borderRadius: BorderRadius.circular(12),
                    color: colors.secondaryContainer,
                    child: ListTile(
                      leading: Icon(
                        LucideIcons.wifiOff,
                        color: colors.onSecondaryContainer,
                      ),
                      title: Text(
                        offline
                            ? "Can't reach the server. Showing saved data."
                            : 'Connecting to the server…',
                        style: TextStyle(color: colors.onSecondaryContainer),
                      ),
                      trailing: TextButton(
                        onPressed: c.refresh,
                        child: const Text('Retry'),
                      ),
                    ),
                  ),
                ),
              if (_tab == 0) ..._home(context),
              if (_tab == 1) ..._activity(context),
              if (_tab == 2)
                LoanLedger(
                  controller: c,
                  undoable: _undoable,
                  pending: _pendingLoans,
                ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: _tab == 2 ? 'New loan entry' : 'Add expense',
          onPressed: _tab == 2
              ? () => showLoanSheet(context, c)
              : _expenseSheet,
          child: const Icon(LucideIcons.plus),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (value) => setState(() => _tab = value),
          destinations: const [
            NavigationDestination(icon: Icon(LucideIcons.house), label: 'Home'),
            NavigationDestination(
              icon: Icon(LucideIcons.list),
              label: 'Activity',
            ),
            NavigationDestination(
              icon: Icon(LucideIcons.users),
              label: 'Loans',
            ),
          ],
        ),
      );
    },
  );

  Widget _periodPill(BuildContext context, {bool fullDate = false}) {
    final colors = Theme.of(context).colorScheme;
    final compact = !fullDate && MediaQuery.sizeOf(context).width < 360;
    final arrowStyle = IconButton.styleFrom(
      minimumSize: const Size(40, 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.all(8),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Previous month',
            style: arrowStyle,
            onPressed: () =>
                c.selectPeriod(DateTime(c.period.year, c.period.month - 1)),
            icon: const Icon(LucideIcons.chevronLeft, size: 16),
          ),
          Tooltip(
            message: 'Choose month and year',
            child: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: _choosePeriod,
              child: Text(
                DateFormat(compact ? 'MMM' : 'MMM yyyy').format(c.period),
                semanticsLabel: DateFormat('MMMM yyyy').format(c.period),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            style: arrowStyle,
            onPressed: () =>
                c.selectPeriod(DateTime(c.period.year, c.period.month + 1)),
            icon: const Icon(LucideIcons.chevronRight, size: 16),
          ),
        ],
      ),
    );
  }

  List<Widget> _home(BuildContext context) {
    final stats = c.stats;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final sameMonth = c.period.year == now.year && c.period.month == now.month;
    final month = DateFormat.MMMM().format(c.period);
    if (stats == null) {
      return [
        if (c.loading)
          for (final height in [160.0, 190.0, 100.0])
            _block(
              Panel(
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
        else
          Panel(
            child: EmptyMessage(
              title: 'No spending to show',
              message: 'Pull down to refresh or add an expense.',
              action: TextButton(
                onPressed: _expenseSheet,
                child: const Text('Add expense'),
              ),
            ),
          ),
      ];
    }
    return [
      _block(
        Panel(
          color: theme.colorScheme.primaryContainer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPENT IN ${month.toUpperCase()}',
                style: theme.textTheme.labelSmall,
              ),
              Text(
                money(stats.monthly, c.hidden),
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _stat(
                    context,
                    'Daily average',
                    money(stats.dailyAverage, c.hidden),
                  ),
                  _stat(context, 'Categories', '${stats.activeCategories}'),
                  _stat(context, 'All time', money(stats.total, c.hidden)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: c.stale
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c.stale || c.updatedAt == null
                          ? 'Showing saved data · Pull to refresh'
                          : 'Synced ${DateFormat.jm().format(c.updatedAt!)} · Pull to refresh',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      _block(
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                sameMonth ? 'This month' : month,
                style: theme.textTheme.titleMedium,
              ),
              SpendingChart(
                points: stats.dailyPattern,
                hidden: c.hidden,
                today: sameMonth ? now.day : null,
              ),
            ],
          ),
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Recent', style: theme.textTheme.titleMedium),
          TextButton(
            onPressed: () => setState(() {
              _tab = 1;
              _scope = DateScope.month;
              _category = 'All';
              _query = '';
              _search.clear();
            }),
            child: const Text('See all'),
          ),
        ],
      ),
      Panel(
        child: stats.recent.where((e) => !_deleting.contains(e.id)).isEmpty
            ? const EmptyMessage(
                title: 'No recent expenses',
                message: 'Expenses for this month will appear here.',
              )
            : Column(
                children: stats.recent
                    .where((e) => !_deleting.contains(e.id))
                    .take(3)
                    .map(_row)
                    .toList(),
              ),
      ),
    ];
  }

  Widget _stat(BuildContext context, String label, String value) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );

  Widget _block(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 16), child: child);

  List<Widget> _activity(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scope = c.expenses
        .where(
          (e) =>
              !_deleting.contains(e.id) &&
              (_scope == DateScope.all ||
                  (e.date.year == c.period.year &&
                      (_scope == DateScope.year ||
                          e.date.month == c.period.month))),
        )
        .toList();
    final totals = <String, double>{};
    for (final expense in scope) {
      totals.update(
        expense.category,
        (value) => value + expense.amount,
        ifAbsent: () => expense.amount,
      );
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final tail = ranked.skip(4).toList();
    final groupOthers = tail.length > 1;
    final slices = groupOthers
        ? [
            ...ranked.take(4),
            MapEntry('Others', tail.fold<double>(0, (sum, e) => sum + e.value)),
          ]
        : ranked;
    final groups = <DateTime, List<Expense>>{};
    final matching =
        scope.where((e) {
          final categoryMatches =
              _category == 'All' ||
              (_category == _otherCategories
                  ? tail.any((entry) => entry.key == e.category)
                  : e.category == _category);
          return categoryMatches &&
              '${e.description} ${e.category}'.toLowerCase().contains(_query);
        }).toList()..sort((a, b) {
          final date = b.date.compareTo(a.date);
          return date == 0 ? b.id.compareTo(a.id) : date;
        });
    for (final expense in matching) {
      (groups[DateUtils.dateOnly(expense.date)] ??= []).add(expense);
    }
    return [
      _block(
        TextField(
          controller: _search,
          onChanged: (value) =>
              setState(() => _query = value.trim().toLowerCase()),
          decoration: const InputDecoration(
            hintText: 'Search expenses',
            prefixIcon: Icon(LucideIcons.search),
          ),
        ),
      ),
      _block(
        SegmentedButton<DateScope>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: DateScope.month, label: Text('Month')),
            ButtonSegment(value: DateScope.year, label: Text('Year')),
            ButtonSegment(value: DateScope.all, label: Text('All')),
          ],
          selected: {_scope},
          onSelectionChanged: (values) => setState(() {
            _scope = values.first;
            _category = 'All';
          }),
        ),
      ),
      _block(
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final value in {
                'All',
                ...categories,
                ...totals.keys,
                if (groupOthers) _otherCategories,
              })
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      value == _otherCategories ? 'Other categories' : value,
                    ),
                    selected: _category == value,
                    onSelected: (_) => setState(() => _category = value),
                  ),
                ),
            ],
          ),
        ),
      ),
      if (slices.isNotEmpty)
        _block(
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('By category', style: t.titleMedium),
                const SizedBox(height: 12),
                CategoryDonut(
                  slices: slices,
                  hidden: c.hidden,
                  caption: switch (_scope) {
                    DateScope.month => DateFormat.MMMM().format(c.period),
                    DateScope.year => '${c.period.year}',
                    DateScope.all => 'All time',
                  },
                  onSelect: (index) => setState(
                    () => _category = groupOthers && index == 4
                        ? _otherCategories
                        : slices[index].key,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (groups.isEmpty)
        const Panel(
          child: EmptyMessage(
            title: 'No expenses found',
            message: 'Try another filter or add an expense.',
          ),
        ),
      for (final group in groups.entries)
        _block(
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_day(group.key), style: t.labelSmall),
                    Text(
                      money(
                        group.value.fold<double>(0, (sum, e) => sum + e.amount),
                        c.hidden,
                      ),
                      style: t.labelLarge,
                    ),
                  ],
                ),
              ),
              Panel(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    for (final expense in group.value)
                      Dismissible(
                        key: ValueKey(expense.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          color: Theme.of(context).colorScheme.errorContainer,
                          padding: const EdgeInsets.all(16),
                          child: const Icon(LucideIcons.trash2),
                        ),
                        onDismissed: (_) => _delete(expense),
                        child: _row(expense),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
    ];
  }

  static const _otherCategories = '\u0000other';

  String _day(DateTime date) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(date, now)) return 'Today';
    if (DateUtils.isSameDay(date, DateTime(now.year, now.month, now.day - 1))) {
      return 'Yesterday';
    }
    return DateFormat('d MMM yyyy').format(date);
  }

  Widget _row(Expense e) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: () => _expenseSheet(e),
    leading: CategoryIcon(category: e.category),
    title: Text(e.description.trim().isEmpty ? e.category : e.description),
    subtitle: Text(_tab == 0 ? _day(e.date) : e.category),
    trailing: Text(
      money(e.amount, c.hidden),
      style: Theme.of(context).textTheme.labelLarge,
    ),
  );
}
