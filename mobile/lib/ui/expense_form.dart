import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../models.dart';
import 'theme.dart';

class ExpenseForm extends StatefulWidget {
  final Expense? expense;
  final Future<void> Function(ExpenseDraft) onSave;
  final VoidCallback? onSaved;
  const ExpenseForm({
    super.key,
    this.expense,
    required this.onSave,
    this.onSaved,
  });
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late String _category;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.expense?.amount.toStringAsFixed(2) ?? '',
    );
    _description = TextEditingController(
      text: widget.expense?.description ?? '',
    );
    _category = widget.expense?.category ?? categories.first;
    _date = widget.expense?.date ?? DateUtils.dateOnly(DateTime.now());
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200, 12, 31),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        ExpenseDraft(
          amount: double.parse(_amount.text),
          category: _category,
          description: _description.text,
          date: _date,
        ),
      );
      if (!mounted) return;
      if (widget.expense == null) {
        _amount.clear();
        _description.clear();
        setState(() {
          _category = categories.first;
          _date = DateUtils.dateOnly(DateTime.now());
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.expense == null
                ? 'Expense added successfully'
                : 'Expense updated successfully',
          ),
        ),
      );
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ApiException
              ? e.message
              : 'Could not save your expense. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choices = {...categories, _category};
    return PopScope(
      canPop: !_saving,
      child: Form(
        key: _form,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.expense == null ? 'Add New Expense' : 'Edit Expense',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                widget.expense == null
                    ? 'A little tracking. A clearer picture.'
                    : 'Update the details of your expense.',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _amount,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹ ',
                  hintText: '0.00',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                textInputAction: TextInputAction.next,
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  if (amount == null || !amount.isFinite || amount <= 0) {
                    return 'Enter an amount greater than zero';
                  }
                  if (amount > 9999999999.99) {
                    return 'Amount exceeds the supported limit';
                  }
                  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value!)) {
                    return 'Use no more than 2 decimal places';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                key: ValueKey(_category),
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: choices
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Row(
                          children: [
                            Icon(
                              categoryIcon(category),
                              size: 19,
                              color: categoryColor(category),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                category,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _category = value!),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _description,
                enabled: !_saving,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What did you spend on?',
                  alignLabelWithHint: true,
                ),
                textCapitalization: TextCapitalization.sentences,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter a description'
                    : null,
              ),
              const SizedBox(height: 12),
              Semantics(
                button: true,
                label: 'Expense date',
                child: InkWell(
                  onTap: _saving ? null : _chooseDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      suffixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(DateFormat('dd MMMM yyyy').format(_date)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          widget.expense == null
                              ? Icons.add_rounded
                              : Icons.check_rounded,
                        ),
                  label: Text(
                    _saving
                        ? 'Saving…'
                        : widget.expense == null
                        ? 'Add Expense'
                        : 'Save Changes',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Every expense counts towards better habits.',
                  style: TextStyle(fontSize: 12, color: muted),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
