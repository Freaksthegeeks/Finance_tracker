import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../expense_speech.dart';
import '../models.dart';
import '../tracker_controller.dart';
import '../voice_recording.dart';
import 'theme.dart';

class ExpenseForm extends StatefulWidget {
  final Expense? expense;
  final TrackerController? controller;
  final Future<void> Function(ExpenseDraft) onSave;
  final VoidCallback? onSaved;
  final VoidCallback? onDelete;
  final String? initialCategory;
  const ExpenseForm({
    super.key,
    this.expense,
    this.controller,
    required this.onSave,
    this.onSaved,
    this.onDelete,
    this.initialCategory,
  });
  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _description;
  late String _category;
  late DateTime _date;
  bool _saving = false;
  bool _more = false;
  String? _error;
  VoiceRecording? _voiceSession;
  bool _transcribing = false;
  bool _listening = false;
  String? _voiceMessage;

  bool get _supportsVoice =>
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android &&
      widget.controller != null;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.expense?.amount.toStringAsFixed(2) ?? '',
    );
    _description = TextEditingController(
      text: widget.expense?.description ?? '',
    );
    _category =
        widget.expense?.category ?? widget.initialCategory ?? categories.first;
    _amount.addListener(() => setState(() {}));
    _date = widget.expense?.date ?? DateUtils.dateOnly(DateTime.now());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _voiceSession?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voiceSession?.cancel();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    if (_voiceSession != null || _saving) return;
    FocusScope.of(context).unfocus();
    final session = widget.controller!.createVoiceRecording();
    setState(() {
      _voiceSession = session;
      _voiceMessage = null;
    });
    try {
      final transcript = await session.listen(
        widget.controller!.api,
        onRecording: () {
          if (mounted) setState(() => _listening = true);
        },
        onTranscribing: () {
          if (mounted) {
            setState(() {
              _listening = false;
              _transcribing = true;
            });
          }
        },
      );
      if (!mounted ||
          _voiceSession != session ||
          session.isCancelled ||
          transcript == null) {
        return;
      }
      if (transcript.trim().isEmpty) {
        setState(() => _voiceMessage = 'No speech detected. Try again.');
        return;
      }
      final draft = parseExpenseSpeech(transcript);
      final amount = draft.amount;
      final validAmount = amount != null && _amountError(amount) == null;
      setState(() {
        if (validAmount) _amount.text = amount;
        if (draft.note.isNotEmpty) {
          _description.text = draft.note.characters.take(500).toString();
        }
        _voiceMessage = validAmount
            ? 'Review the amount and note, then tap Save expense.'
            : 'Amount not recognized. Check the amount and note before saving.';
      });
    } on ApiException catch (error) {
      if (mounted && _voiceSession == session && !session.isCancelled) {
        setState(() => _voiceMessage = error.message);
      }
    } on PlatformException catch (error) {
      if (mounted && _voiceSession == session && !session.isCancelled) {
        setState(() => _voiceMessage = error.message ?? 'Voice entry failed.');
      }
    } on Exception {
      if (mounted && _voiceSession == session && !session.isCancelled) {
        setState(() => _voiceMessage = 'Voice entry is unavailable.');
      }
    } finally {
      if (mounted && _voiceSession == session) {
        setState(() {
          _voiceSession = null;
          _listening = false;
          _transcribing = false;
        });
      }
    }
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
    if (_saving || _voiceSession != null || !_form.currentState!.validate()) {
      return;
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.controller?.error?.startsWith('Expense saved;') == true
                ? 'Expense saved; refresh failed. Pull down to retry.'
                : widget.expense == null
                ? 'Expense added'
                : 'Expense updated',
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
    final choices = {...(_more ? categories : categories.take(8)), _category};
    final theme = Theme.of(context);
    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final voiceSession = _voiceSession;
    return PopScope(
      canPop: !_saving,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.expense == null
                        ? 'New expense'
                        : 'Edit expense #${widget.expense!.id}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (widget.onDelete != null)
                  TextButton(
                    onPressed: _saving ? null : widget.onDelete,
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('Delete'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_supportsVoice && widget.expense == null) ...[
              if (voiceSession == null)
                OutlinedButton.icon(
                  onPressed: _saving ? null : _listen,
                  icon: const Icon(Icons.mic),
                  label: const Text('Enter by voice'),
                )
              else
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _transcribing
                          ? 'Transcribing…'
                          : _listening
                          ? 'Listening…'
                          : 'Preparing microphone…',
                    ),
                    if (_listening)
                      TextButton(
                        onPressed: voiceSession.stop,
                        child: const Text('Stop'),
                      ),
                    TextButton(
                      onPressed: voiceSession.cancel,
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              const Text(
                'Voice sends audio to the tracker server and requires a connection.',
              ),
              Text(_voiceMessage ?? 'Say “two hundred rupees for lunch”.'),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _amount,
              enabled: !_saving && voiceSession == null,
              autofocus: widget.expense == null,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineLarge,
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
              autovalidateMode: AutovalidateMode.onUserInteraction,
              validator: (value) => _amountError(value ?? ''),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                runSpacing: 8,
                children: [
                  for (final category in choices)
                    SizedBox(
                      width: constraints.maxWidth / 4,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Semantics(
                          button: true,
                          selected: _category == category,
                          enabled: !_saving,
                          label: category,
                          excludeSemantics: true,
                          onTap: _saving
                              ? null
                              : () => setState(() => _category = category),
                          child: Material(
                            color: _category == category
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              onTap: _saving
                                  ? null
                                  : () => setState(() => _category = category),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: Column(
                                  children: [
                                    CategoryIcon(category: category),
                                    Text(
                                      category,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: _saving ? null : () => setState(() => _more = !_more),
              child: Text(_more ? 'Less' : 'More'),
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: DateUtils.isSameDay(_date, today),
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _date = today),
                ),
                ChoiceChip(
                  label: const Text('Yesterday'),
                  selected: DateUtils.isSameDay(_date, yesterday),
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _date = yesterday),
                ),
                ActionChip(
                  label: Text(
                    DateUtils.isSameDay(_date, today) ||
                            DateUtils.isSameDay(_date, yesterday)
                        ? 'Pick date'
                        : DateFormat.yMMMd().format(_date),
                  ),
                  onPressed: _saving || voiceSession != null
                      ? null
                      : _chooseDate,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              enabled: !_saving && voiceSession == null,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                counterText: '',
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed:
                  _saving ||
                      voiceSession != null ||
                      _amountError(_amount.text) != null
                  ? null
                  : _submit,
              child: _saving && widget.controller != null
                  ? ListenableBuilder(
                      listenable: widget.controller!,
                      builder: (context, _) =>
                          Text(widget.controller!.savingLabel),
                    )
                  : Text(
                      _saving
                          ? 'Saving…'
                          : widget.expense == null
                          ? 'Save expense'
                          : 'Save changes',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String? _amountError(String value) {
    final amount = double.tryParse(value);
    if (amount == null || !amount.isFinite || amount <= 0) {
      return 'Enter an amount greater than zero';
    }
    if (amount > 9999999999.99) return 'Amount exceeds the supported limit';
    if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
      return 'Use no more than 2 decimal places';
    }
    return null;
  }
}
