import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api.dart';
import '../models.dart';
import '../tracker_controller.dart';
import 'theme.dart';

typedef Undoable = void Function(
  String label,
  VoidCallback restore,
  Future<void> Function() commit,
);

class LoanLedger extends StatefulWidget {
  final TrackerController controller;
  final Undoable undoable;
  final Set<int> pending;
  const LoanLedger({
    super.key,
    required this.controller,
    required this.undoable,
    required this.pending,
  });

  @override
  State<LoanLedger> createState() => _LoanLedgerState();
}

class _LoanLedgerState extends State<LoanLedger> {
  bool _settled = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loans =
        c.loans.where((loan) => !widget.pending.contains(loan.id)).toList()
          ..sort((a, b) {
            final date = b.date.compareTo(a.date);
            return date == 0 ? b.id.compareTo(a.id) : date;
          });
    double balance(String direction) => loans
        .where((loan) => !loan.refunded && loan.direction == direction)
        .fold(0.0, (sum, loan) => sum + loan.amount);
    Widget tile(
      String label,
      String direction,
      Color foreground,
      Color background,
      IconData icon,
    ) => Expanded(
      child: Panel(
        color: background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground),
            ),
            const SizedBox(height: 4),
            Text(
              c.loansLoaded ? money(balance(direction), c.hidden) : '—',
              style: theme.textTheme.headlineSmall?.copyWith(color: foreground),
            ),
          ],
        ),
      ),
    );
    final visible = loans.where((loan) => loan.refunded == _settled);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            tile(
              'Owed to you',
              'lent',
              colors.onPrimaryContainer,
              colors.primaryContainer,
              LucideIcons.arrowUpRight,
            ),
            const SizedBox(width: 12),
            tile(
              'You owe',
              'borrowed',
              colors.onSecondaryContainer,
              colors.secondaryContainer,
              LucideIcons.arrowDownLeft,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Open')),
            ButtonSegment(value: true, label: Text('Settled')),
          ],
          selected: {_settled},
          onSelectionChanged: (selection) =>
              setState(() => _settled = selection.first),
        ),
        const SizedBox(height: 16),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: visible.isEmpty
              ? EmptyMessage(
                  title: _settled ? 'No settled loans' : 'No open loans',
                  message: _settled
                      ? 'Settled entries will appear here.'
                      : 'Add an entry to track borrowed or lent money.',
                  action: _settled
                      ? null
                      : TextButton(
                          onPressed: () => showLoanSheet(context, c),
                          child: const Text('New loan entry'),
                        ),
                )
              : Column(
                  children: [
                    for (final loan in visible)
                      Dismissible(
                        key: ValueKey(loan.id),
                        direction: _settled
                            ? DismissDirection.none
                            : DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.all(16),
                          color: colors.primaryContainer,
                          child: const Icon(LucideIcons.check),
                        ),
                        onDismissed: (_) => _change(
                          loan,
                          'Loan settled',
                          () => c.refundLoan(loan),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          onTap: () async {
                            final action = await showLoanSheet(
                              context,
                              c,
                              loan,
                            );
                            if (!mounted) return;
                            if (action == LoanAction.delete) {
                              _change(
                                loan,
                                'Loan deleted',
                                () => c.deleteLoan(loan.id),
                              );
                            } else if (action == LoanAction.reopen) {
                              _change(
                                loan,
                                'Loan reopened',
                                () => c.refundLoan(loan),
                              );
                            } else if (action == LoanAction.settle) {
                              _change(
                                loan,
                                'Loan settled',
                                () => c.refundLoan(loan),
                              );
                            }
                          },
                          leading: CircleAvatar(
                            backgroundColor: colors.surfaceContainerHighest,
                            child: Text(
                              loan.person.characters.firstOrNull
                                      ?.toUpperCase() ??
                                  '?',
                            ),
                          ),
                          title: Text(loan.person),
                          subtitle: Text(
                            [
                              if (loan.note.isNotEmpty) loan.note,
                              DateFormat('d MMM').format(loan.date),
                            ].join(' · '),
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(loan.amount, c.hidden),
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: loan.direction == 'lent'
                                      ? colors.primary
                                      : colors.secondary,
                                ),
                              ),
                              Text(
                                loan.direction == 'lent' ? 'Lent' : 'Borrowed',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  void _change(Loan loan, String label, Future<void> Function() commit) {
    setState(() => widget.pending.add(loan.id));
    final pending = widget.pending;
    widget.undoable(label, () => pending.remove(loan.id), commit);
  }
}

enum LoanAction { delete, settle, reopen }

Future<LoanAction?> showLoanSheet(
  BuildContext context,
  TrackerController controller, [
  Loan? loan,
]) => showModalBottomSheet<LoanAction>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => _LoanSheet(controller: controller, loan: loan),
);

class _LoanSheet extends StatefulWidget {
  final TrackerController controller;
  final Loan? loan;
  const _LoanSheet({required this.controller, this.loan});

  @override
  State<_LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<_LoanSheet> {
  final _form = GlobalKey<FormState>();
  late final _person = TextEditingController(text: widget.loan?.person);
  late final _amount = TextEditingController(
    text: widget.loan?.amount.toStringAsFixed(2),
  );
  late final _note = TextEditingController(text: widget.loan?.note);
  late String _direction = widget.loan?.direction ?? 'lent';
  late DateTime _date = widget.loan?.date ?? DateUtils.dateOnly(DateTime.now());
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (mounted && result != null) setState(() => _date = result);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.addLoan(
        id: widget.loan?.id,
        person: _person.text,
        direction: _direction,
        amount: double.parse(_amount.text),
        date: _date,
        note: _note.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.loan == null ? 'Loan added' : 'Loan updated'),
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not save the loan. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.loan == null ? 'New loan entry' : 'Edit loan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (widget.loan != null)
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, LoanAction.delete),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      child: const Text('Delete'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'lent', label: Text('Lent')),
                  ButtonSegment(value: 'borrowed', label: Text('Borrowed')),
                ],
                selected: {_direction},
                onSelectionChanged: _saving
                    ? null
                    : (value) => setState(() => _direction = value.first),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _person,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(
                  labelText: 'Person',
                  counterText: '',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a name'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  final amount = double.tryParse(text);
                  return amount == null ||
                          amount <= 0 ||
                          amount > 9999999999.99 ||
                          !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text)
                      ? 'Enter a positive amount with up to two decimals'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: const Icon(LucideIcons.calendar, size: 16),
                  label: Text(DateFormat.yMMMd().format(_date)),
                  onPressed: _saving ? null : _pickDate,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                enabled: !_saving,
                maxLength: 2000,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save loan'),
              ),
              if (widget.loan case final loan?)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.pop(
                          context,
                          loan.refunded ? LoanAction.reopen : LoanAction.settle,
                        ),
                  child: Text(loan.refunded ? 'Reopen loan' : 'Mark settled'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
