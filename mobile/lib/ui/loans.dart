import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import '../tracker_controller.dart';
import 'theme.dart';

class LoanSummary extends StatelessWidget {
  final TrackerController controller;
  final VoidCallback? onManage;
  const LoanSummary({super.key, required this.controller, this.onManage});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Borrowed & lent',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Outstanding across all dates · Excluded from expenses',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          if (c.loansError != null) ...[
            const SizedBox(height: 8),
            Text(
              '${c.loansLoaded ? 'Showing saved balances. ' : ''}${c.loansError}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 28,
            runSpacing: 16,
            children: [
              _balance(context, 'Borrowed · You owe', 'borrowed'),
              _balance(context, 'Lent · Owed to you', 'lent'),
            ],
          ),
          if (onManage != null)
            TextButton(
              onPressed: onManage,
              child: const Text('Manage borrowed & lent'),
            ),
        ],
      ),
    );
  }

  Widget _balance(BuildContext context, String label, String direction) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: muted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            controller.loansLoaded
                ? money(controller.outstanding(direction), controller.hidden)
                : '—',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      );
}

class LoanLedger extends StatefulWidget {
  final TrackerController controller;
  const LoanLedger({super.key, required this.controller});
  @override
  State<LoanLedger> createState() => _LoanLedgerState();
}

class _LoanLedgerState extends State<LoanLedger> {
  final _form = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _direction = 'lent';
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  String? _error;
  bool _busy = false;
  TrackerController get c => widget.controller;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not save the change. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await _perform(() async {
      await c.addLoan(
        person: _person.text,
        direction: _direction,
        amount: double.parse(_amount.text),
        date: _date,
        note: _note.text,
      );
      if (!mounted) return;
      _person.clear();
      _amount.clear();
      _note.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entry saved')));
    });
  }

  Future<void> _delete(Loan loan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(
          'Remove the entry for ${loan.person}? This also removes it from outstanding balances.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(() => c.deleteLoan(loan.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy || c.saveProgress != SaveProgress.idle;
    final ordered = [...c.loans]
      ..sort((a, b) {
        if (a.refunded != b.refunded) return a.refunded ? 1 : -1;
        final byDate = b.date.compareTo(a.date);
        return byDate == 0 ? b.id.compareTo(a.id) : byDate;
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LoanSummary(controller: c),
        const SizedBox(height: 20),
        Panel(
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Record borrowed or lent money',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(
                      value: 'lent',
                      child: Text(
                        'Lent · I gave money',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'borrowed',
                      child: Text(
                        'Borrowed · I received money',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() => _direction = value!),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _person,
                  enabled: !busy,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: 'Person’s name'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Loan amount',
                    prefixText: '₹ ',
                  ),
                  validator: (v) {
                    final amount = double.tryParse(v ?? '');
                    if (amount == null ||
                        !amount.isFinite ||
                        amount <= 0 ||
                        amount > 9999999999.99) {
                      return 'Enter a positive amount up to 9,999,999,999.99';
                    }
                    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v!)) {
                      return 'Use up to two decimal places';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(1900),
                            lastDate: DateTime(2200, 12, 31),
                          );
                          if (date != null && mounted) {
                            setState(() => _date = date);
                          }
                        },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(DateFormat('dd MMM yyyy').format(_date)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
                  enabled: !busy,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: busy ? null : _add,
                  child: Text(busy ? 'Saving change…' : 'Save entry'),
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 20),
        Text(
          'Entries & repayment history',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (ordered.isEmpty)
          Text(
            c.loansLoaded
                ? 'No entries yet. Add a person and amount above.'
                : 'Entries have not loaded yet.',
          ),
        for (final loan in ordered)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loan.person,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: loan.refunded
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${loan.direction == 'lent' ? 'Lent' : 'Borrowed'} · ${money(loan.amount, c.hidden)}',
                  ),
                  Text(
                    DateFormat('dd MMM yyyy').format(loan.date),
                    style: const TextStyle(color: muted),
                  ),
                  if (loan.note.isNotEmpty) Text(loan.note),
                  if (loan.refunded)
                    const Text(
                      'Refunded',
                      style: TextStyle(
                        color: sage,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: busy
                            ? null
                            : () => _perform(() => c.refundLoan(loan)),
                        icon: Icon(
                          loan.refunded
                              ? Icons.undo
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          loan.refunded ? 'Undo refund' : 'Mark refunded',
                        ),
                      ),
                      TextButton(
                        onPressed: busy ? null : () => _delete(loan),
                        child: const Text('Delete entry'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
