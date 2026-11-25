import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../tracker_controller.dart';
import 'expense_form.dart';
import 'loans.dart';
import 'spending_chart.dart';
import 'theme.dart';

enum DateScope { all, month, year }

class TrackerHome extends StatefulWidget {
  final TrackerController controller;
  const TrackerHome({super.key, required this.controller});
  @override
  State<TrackerHome> createState() => _TrackerHomeState();
}

class _TrackerHomeState extends State<TrackerHome> with WidgetsBindingObserver {
  TrackerController get c => widget.controller;
  Timer? _timer;
  int _tab = 0;
  String _query = '';
  String _category = 'All';
  DateScope _scope = DateScope.all;
  final _search = TextEditingController();
  final _deleting = <int>{};
  bool _active = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(c.start());
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

  void _viewHistory({
    String category = 'All',
    DateScope scope = DateScope.month,
  }) => setState(() {
    _category = category;
    _scope = scope;
    _query = '';
    _search.clear();
    _tab = 2;
  });

  Future<void> _edit(Expense expense) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Edit expense')),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Panel(
                    child: ExpenseForm(
                      controller: c,
                      expense: expense,
                      onSave: (draft) => c.save(draft, id: expense.id),
                      onSaved: () => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('“${expense.description}” will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting.add(expense.id));
    try {
      await c.delete(expense.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException
                  ? e.message
                  : 'Could not delete the expense. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting.remove(expense.id));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: sage),
            SizedBox(width: 10),
            Flexible(
              child: Text(
                'Expense Tracker',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: c.hidden ? 'Show amounts' : 'Hide amounts',
            onPressed: c.togglePrivacy,
            icon: Icon(
              c.hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          FocusScope.of(context).unfocus();
          setState(() => _tab = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline_rounded),
            selectedIcon: Icon(Icons.add_circle_rounded),
            label: 'Add Expense',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'All Expenses',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake),
            label: 'Borrow & Lend',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'YOUR SPENDING, IN FOCUS',
                              style: TextStyle(
                                fontSize: 10,
                                letterSpacing: 1.4,
                                color: muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              DateFormat('MMMM yyyy').format(c.period),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _choosePeriod,
                        icon: const Icon(
                          Icons.calendar_month_outlined,
                          size: 17,
                        ),
                        label: const Text('Period'),
                      ),
                      IconButton(
                        tooltip: 'Refresh expenses',
                        onPressed: c.loading ? null : () => c.refresh(),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
                if (c.loading)
                  const LinearProgressIndicator(minHeight: 2)
                else
                  const SizedBox(height: 2),
                if (c.backendState == BackendState.connecting ||
                    (c.stale && c.updatedAt != null))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${c.backendState == BackendState.connecting ? 'Connecting to server… ' : ''}'
                        '${c.updatedAt == null ? '' : 'Showing saved data · Last updated ${DateFormat('dd MMM, HH:mm').format(c.updatedAt!.toLocal())}'}',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ),
                  ),
                if (c.error != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                    padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c.updatedAt == null ? '' : 'Showing previously loaded data. '}${c.error}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: c.loading ? null : () => c.refresh(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _scroll(_dashboard()),
                      _scroll([
                        Panel(
                          child: ExpenseForm(
                            controller: c,
                            onSave: (draft) => c.save(draft),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.sync_rounded,
                              size: 16,
                              color: sage,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                c.stale
                                    ? 'Waiting to sync with your web tracker'
                                    : 'Synced with your web tracker',
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ]),
                      _scroll(_history()),
                      _scroll([LoanLedger(controller: c)]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _scroll(List<Widget> children) => RefreshIndicator(
    onRefresh: () => c.refresh(),
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: children,
    ),
  );

  List<Widget> _dashboard() {
    final stats = c.stats;
    if (stats == null) {
      return [
        Panel(
          child: c.loading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 18),
                      Text('Loading your spending…'),
                      SizedBox(height: 8),
                      Text(
                        'The server may take a moment to wake up.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                    ],
                  ),
                )
              : EmptyMessage(
                  title: 'Unable to load dashboard',
                  message: 'Check your connection and retry.',
                  action: FilledButton(
                    onPressed: () => c.refresh(),
                    child: const Text('Try again'),
                  ),
                ),
        ),
      ];
    }
    return [
      LayoutBuilder(
        builder: (context, constraints) {
          final columns =
              constraints.maxWidth < 300 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4
              ? 1
              : 2;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _stat(
                'Total Expenses',
                money(stats.total, c.hidden),
                'All time spending',
                Icons.account_balance_wallet_outlined,
                width,
              ),
              _stat(
                'This Month',
                money(stats.monthly, c.hidden),
                DateFormat('MMMM yyyy').format(c.period),
                Icons.trending_up_rounded,
                width,
              ),
              _stat(
                'Daily Average',
                money(stats.dailyAverage, c.hidden),
                'Average per day',
                Icons.bolt_outlined,
                width,
              ),
              _stat(
                'Categories',
                '${stats.activeCategories}',
                'Active this month',
                Icons.category_outlined,
                width,
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),
      LoanSummary(controller: c, onManage: () => setState(() => _tab = 3)),
      const SizedBox(height: 20),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(
              'Daily Spending Pattern',
              'Your daily expenses for ${DateFormat('MMMM').format(c.period)}',
            ),
            const SizedBox(height: 16),
            SpendingChart(points: stats.dailyPattern, hidden: c.hidden),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _heading(
                    'Recent Expenses',
                    'Your latest activity this month',
                  ),
                ),
                TextButton(
                  onPressed: _viewHistory,
                  child: const Text('View all'),
                ),
              ],
            ),
            if (stats.recent.isEmpty)
              EmptyMessage(
                title: 'A fresh start',
                message: 'Record your first expense for this month.',
                action: TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: const Text('Add an expense'),
                ),
              )
            else
              ...stats.recent.map((e) => _expenseTile(e, actions: false)),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _categoryPanel(
        'Top Categories',
        'Where your money went this month',
        stats.topCategories,
      ),
      const SizedBox(height: 20),
      _categoryPanel(
        'Total Expenses by Category',
        'Your spending in ${c.period.year}',
        stats.yearlyCategories,
        yearly: true,
      ),
      if (c.updatedAt != null)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            'Last synced ${DateFormat('h:mm a').format(c.updatedAt!)} · Pull down to refresh',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: muted),
          ),
        ),
    ];
  }

  Widget _heading(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 5),
      Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
    ],
  );

  Widget _stat(
    String title,
    String value,
    String subtitle,
    IconData icon,
    double width,
  ) => SizedBox(
    width: width,
    child: Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    color: muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 17, color: sage),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: ink,
                letterSpacing: -0.7,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: muted)),
        ],
      ),
    ),
  );

  Widget _categoryPanel(
    String title,
    String subtitle,
    List<CategoryTotal> items, {
    bool yearly = false,
  }) {
    final total = items.fold<double>(0, (sum, item) => sum + item.total);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(title, subtitle),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const EmptyMessage(
              title: 'No spending yet',
              message: 'Category totals will appear here.',
            ),
          ...items.map(
            (item) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _viewHistory(
                category: item.category,
                scope: yearly ? DateScope.year : DateScope.month,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: categoryColor(item.category)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            categoryIcon(item.category),
                            size: 18,
                            color: categoryColor(item.category),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.category,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${item.count} transaction${item.count == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            money(item.total, c.hidden),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 17,
                          color: muted,
                        ),
                      ],
                    ),
                    if (!c.hidden)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: total > 0 ? item.total / total : 0,
                            color: categoryColor(item.category),
                            backgroundColor: canvas,
                            minHeight: 4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _history() {
    final list = c.expenses.where((e) {
      final matchesDate =
          _scope == DateScope.all ||
          (e.date.year == c.period.year &&
              (_scope == DateScope.year || e.date.month == c.period.month));
      return matchesDate &&
          '${e.description} ${e.category}'.toLowerCase().contains(
            _query.toLowerCase().trim(),
          ) &&
          (_category == 'All' || e.category == _category);
    }).toList();
    final choices = {
      'All',
      ...categories,
      ...c.expenses.map((e) => e.category),
      _category,
    };
    return [
      _heading('All Expenses', 'Find, edit and manage your spending'),
      const SizedBox(height: 20),
      TextField(
        controller: _search,
        onChanged: (v) => setState(() => _query = v),
        decoration: InputDecoration(
          hintText: 'Search expenses',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: ValueKey(_category),
        initialValue: _category,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Category',
          prefixIcon: Icon(Icons.filter_list_rounded),
        ),
        items: choices
            .map(
              (item) => DropdownMenuItem(
                value: item,
                child: Text(
                  item == 'All' ? 'All categories' : item,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: (v) => setState(() => _category = v!),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('All dates'),
            selected: _scope == DateScope.all,
            onSelected: (_) => setState(() => _scope = DateScope.all),
          ),
          ChoiceChip(
            label: Text(DateFormat('MMM yyyy').format(c.period)),
            selected: _scope == DateScope.month,
            onSelected: (_) => setState(() => _scope = DateScope.month),
          ),
          ChoiceChip(
            label: Text('${c.period.year}'),
            selected: _scope == DateScope.year,
            onSelected: (_) => setState(() => _scope = DateScope.year),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '${list.length} expense${list.length == 1 ? '' : 's'} · ${money(list.fold<double>(0, (sum, e) => sum + e.amount), c.hidden)}',
          style: const TextStyle(
            color: muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      if (list.isEmpty)
        Panel(
          child: EmptyMessage(
            title: c.loading && c.updatedAt == null
                ? 'Loading expenses…'
                : 'No expenses found',
            message: 'Try a different filter or add a new expense.',
            action: TextButton(
              onPressed: () => setState(() => _tab = 1),
              child: const Text('Add an expense'),
            ),
          ),
        )
      else
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(children: list.map((e) => _expenseTile(e)).toList()),
        ),
    ];
  }

  Widget _expenseTile(Expense expense, {bool actions = true}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: categoryColor(expense.category).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            categoryIcon(expense.category),
            size: 19,
            color: categoryColor(expense.category),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                expense.description,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 5),
              Text(
                expense.category,
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('dd MMM yyyy').format(expense.date),
                style: const TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(
            money(expense.amount, c.hidden),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            textAlign: TextAlign.end,
          ),
        ),
        if (actions)
          _deleting.contains(expense.id)
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : PopupMenuButton<String>(
                  tooltip: 'Expense actions',
                  padding: EdgeInsets.zero,
                  onSelected: (value) =>
                      value == 'edit' ? _edit(expense) : _delete(expense),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: Colors.red,
                          ),
                          SizedBox(width: 10),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
      ],
    ),
  );
}
