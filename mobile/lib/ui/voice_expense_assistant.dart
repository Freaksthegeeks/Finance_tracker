import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api.dart';
import '../expense_speech.dart';
import '../models.dart';
import '../tracker_controller.dart';
import '../voice_expense_commands.dart';
import '../voice_recording.dart';

class VoiceExpenseAssistant extends StatefulWidget {
  final TrackerController controller;

  const VoiceExpenseAssistant({super.key, required this.controller});

  @override
  State<VoiceExpenseAssistant> createState() => _VoiceExpenseAssistantState();
}

class _VoiceExpenseAssistantState extends State<VoiceExpenseAssistant>
    with WidgetsBindingObserver {
  static const _speech = MethodChannel('finance_tracker/expense_playback');
  static final _fields = RegExp(
    r'\b(amount|category|date|description|note|name)\b(?:\s+(?:of (?:the )?expense|change|to|is)\b)*',
  );

  final _changes = <VoiceField, Object>{};
  VoiceField? _waitingFor;
  Expense? _editing;
  bool _adding = false;
  bool _waitingForId = false;
  bool _confirming = false;
  bool _busy = false;
  bool _held = false;
  bool _recording = false;
  bool _stopping = false;
  bool _hidden = true;
  bool _foreground = true;
  VoiceRecording? _session;
  String? _heard;
  String? _error;
  String _prompt =
      'Say “add expense”, “edit expense ID forty-three”, or “total this month”.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hidden = widget.controller.hidden;
    widget.controller.addListener(_privacyChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_privacyChanged);
    WidgetsBinding.instance.removeObserver(this);
    _session?.cancel();
    unawaited(_call('stopSpeaking'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _session?.cancel();
      unawaited(_call('stopSpeaking'));
    }
  }

  void _privacyChanged() {
    if (!mounted || _hidden == widget.controller.hidden) return;
    setState(() {
      _hidden = widget.controller.hidden;
      _heard = null;
      if (_hidden) {
        _prompt = _confirming
            ? 'Your changes are ready. Say save to confirm.'
            : 'Amounts are hidden.';
      }
    });
    if (_hidden) unawaited(_call('stopSpeaking'));
  }

  Future<void> _call(String method, [Object? value]) async {
    try {
      await _speech.invokeMethod<void>(method, value);
    } on PlatformException {
      // Transcription failures are reported by the listen call.
    } on MissingPluginException {
      // The assistant remains readable without speech playback.
    }
  }

  void _reply(String text) {
    if (!mounted) return;
    setState(() => _prompt = text);
    if (_foreground) {
      unawaited(_call('speak', text.replaceAll('₹', 'rupees ')));
    }
  }

  Future<void> _listen({bool held = false}) async {
    if (_session != null || _busy) return;
    final id = widget.controller.createVoiceRecording();
    setState(() {
      _session = id;
      _held = held;
      _error = null;
    });
    try {
      await _call('stopSpeaking');
      final transcript = await id.listen(
        widget.controller.api,
        onRecording: () {
          if (mounted) setState(() => _recording = true);
        },
        onTranscribing: () {
          if (mounted) {
            setState(() {
              _recording = false;
              _stopping = true;
            });
          }
        },
      );
      await widget.controller.restorePrivacy();
      if (!mounted || _session != id || id.isCancelled || transcript == null) {
        return;
      }
      if (transcript.trim().isEmpty) {
        setState(
          () =>
              _error = 'No speech detected. Wait for Listening and try again.',
        );
        return;
      }
      setState(() {
        _heard = _hidden ? null : transcript;
        _busy = true;
      });
      await _handle(transcript);
    } on ApiException catch (error) {
      if (mounted && !id.isCancelled) setState(() => _error = error.message);
    } on PlatformException catch (error) {
      if (mounted && !id.isCancelled) {
        setState(() => _error = error.message ?? 'Voice entry failed.');
      }
    } on Exception {
      if (mounted && !id.isCancelled) {
        setState(() => _error = 'Voice entry is unavailable.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _session = null;
          _held = false;
          _recording = false;
          _stopping = false;
          _busy = false;
        });
      }
    }
  }

  void _stop({bool release = false}) {
    final session = _session;
    if (session == null || _stopping) return;
    setState(() => _stopping = true);
    if (release && !_recording) {
      session.cancel();
    } else {
      session.stop();
    }
  }

  void _reset() {
    _adding = false;
    _editing = null;
    _waitingForId = false;
    _waitingFor = null;
    _confirming = false;
    _changes.clear();
  }

  Future<void> _handle(String input) async {
    final text = normalizeVoiceTranscript(input)
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (RegExp(r'^(cancel|start over|never mind)$').hasMatch(text)) {
      _reset();
      _reply('Cancelled. What would you like to do?');
      return;
    }
    if (RegExp(r'^edit\b').hasMatch(text)) {
      await _beginEdit(voiceExpenseId(text));
      return;
    }
    if (RegExp(r'^add\b').hasMatch(text)) {
      _reset();
      _adding = true;
      final details = text.replaceFirst(
        RegExp(r'^add(?: (?:an?|new|the)(?= |$))?(?: expense(?= |$))?\s*'),
        '',
      );
      _captureAdd(details);
      _nextAddQuestion();
      return;
    }
    if (_waitingForId) {
      await _beginEdit(voiceExpenseId(text));
      return;
    }
    if ((_adding || _editing != null) &&
        RegExp(r'^(save(?: (?:it|expense|changes|it now))?|confirm|yes|done)$')
            .hasMatch(text)) {
      if (_confirming) {
        await _save();
      } else if (_adding) {
        _nextAddQuestion();
      } else {
        _reply('What would you like to change?');
      }
      return;
    }
    if (_waitingFor != null) {
      final field = _waitingFor!;
      final value = _fields.matchAsPrefix(text);
      final payload = value != null && _field(value[1]!) == field
          ? text.substring(value.end).trim()
          : text;
      if (!_setField(field, payload)) {
        _ask(field, retry: true);
      } else if (_adding) {
        _nextAddQuestion();
      } else {
        _waitingFor = null;
        _review();
      }
      return;
    }

    if (isSpendingQuestion(text)) {
      await _answer(text);
      return;
    }

    if (_editing != null || _adding) {
      final update = text.replaceFirst(
        RegExp(r'^(?:change|set|update)(?: the)?\s+'),
        '',
      );
      final match = _fields.matchAsPrefix(update);
      if (match != null) {
        final field = _field(match[1]!);
        if (!_setField(field, update.substring(match.end).trim())) {
          _ask(field);
        } else if (_adding) {
          _nextAddQuestion();
        } else {
          _review();
        }
      } else {
        _reply(
          _confirming
              ? 'Say save to confirm, cancel, or name a field to change.'
              : 'Which field would you like to change? Say amount, category, date, or note.',
        );
      }
      return;
    }

    _reply(
      'Say add expense, edit expense ID followed by the number, or ask a spending question.',
    );
  }

  void _captureAdd(String details) {
    if (details.isEmpty) return;
    final explicitDate = RegExp(r'\bon (.+)$').firstMatch(details);
    if (explicitDate != null && _setField(VoiceField.date, explicitDate[1]!)) {
      details = details.substring(0, explicitDate.start).trim();
    }
    final relativeDate = RegExp(r'\b(today|yesterday)$').firstMatch(details);
    if (relativeDate != null) {
      _setField(VoiceField.date, relativeDate[1]!);
      details = details
          .substring(0, relativeDate.start)
          .trim()
          .replaceFirst(RegExp(r'(?:\b(?:on|date)|\band)$'), '')
          .trim();
    }
    final matches = _fields.allMatches(details).toList();
    var prefix = details.substring(0, matches.firstOrNull?.start).trim();
    if (prefix.isNotEmpty) {
      final categorySuffix = RegExp(r'\bin (.+)$').firstMatch(prefix);
      if (categorySuffix != null &&
          _setField(VoiceField.category, categorySuffix[1]!)) {
        prefix = prefix.substring(0, categorySuffix.start).trim();
      }
      final parsed = parseExpenseSpeech(prefix);
      final parts = prefix.split(' for ');
      final amount = parsed.amount ?? parts.first;
      if (_setField(VoiceField.amount, amount)) {
        final note = parsed.amount != null
            ? parsed.note
            : parts.skip(1).join(' for ');
        if (note.isNotEmpty && !_setField(VoiceField.category, note)) {
          _setField(VoiceField.description, note);
        }
      } else {
        _setField(VoiceField.category, prefix);
      }
    }
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final end = index + 1 == matches.length
          ? details.length
          : matches[index + 1].start;
      final value = details.substring(match.end, end).trim();
      _setField(_field(match[1]!), value.replaceFirst(RegExp(r'\s+and$'), ''));
    }
  }

  VoiceField _field(String name) => switch (name) {
    'amount' => VoiceField.amount,
    'category' => VoiceField.category,
    'date' => VoiceField.date,
    _ => VoiceField.description,
  };

  bool _setField(VoiceField field, String text) {
    final value = text.trim().replaceFirst(RegExp(r'^(?:on|to) '), '');
    if (value.isEmpty) return false;
    final Object? parsed = switch (field) {
      VoiceField.amount => voiceAmount(value),
      VoiceField.category => voiceCategory(value),
      VoiceField.date => voiceDate(value, DateTime.now()),
      VoiceField.description =>
        value == 'clear' || value == 'none'
            ? ''
            : text.characters.take(500).toString(),
    };
    if (parsed == null) return false;
    _changes[field] = parsed;
    _waitingFor = null;
    return true;
  }

  void _nextAddQuestion() {
    for (final field in [
      VoiceField.amount,
      VoiceField.category,
      VoiceField.date,
    ]) {
      if (!_changes.containsKey(field)) {
        _ask(field);
        return;
      }
    }
    _review();
  }

  void _ask(VoiceField field, {bool retry = false}) {
    _waitingFor = field;
    _confirming = false;
    final prompt = switch (field) {
      VoiceField.amount => 'What is the amount in rupees?',
      VoiceField.category =>
        'Which category? For example, Food and Dining, Shopping, or Travel.',
      VoiceField.date =>
        'What date? Say today, yesterday, or a date like November twenty.',
      VoiceField.description =>
        'What should the note say? Say clear to remove it.',
    };
    _reply(retry ? 'I did not recognize that. $prompt' : prompt);
  }

  Future<Expense?> _findExpense(int id) async {
    final controller = widget.controller;
    await controller.ensureReady();
    final expenses = await controller.api.expenses();
    return expenses.where((row) => row.id == id).firstOrNull;
  }

  Future<void> _beginEdit(int? id) async {
    _reset();
    _waitingForId = true;
    if (id == null || id <= 0) {
      _reply('What expense ID would you like to edit?');
      return;
    }
    try {
      final expense = await _findExpense(id);
      if (!mounted) return;
      if (expense == null) {
        _reply('I could not find expense ID $id. Say another ID or cancel.');
        return;
      }
      _waitingForId = false;
      _editing = expense;
      _reply(
        'Expense ID $id. What would you like to change? Say amount, category, date, or note.',
      );
    } catch (_) {
      _reply(
        'I could not load expense ID $id. Check your connection and say the ID again.',
      );
    }
  }

  ExpenseDraft _draft(Expense? base) => ExpenseDraft(
    amount: _changes[VoiceField.amount] as double? ?? base!.amount,
    category: _changes[VoiceField.category] as String? ?? base!.category,
    date: _changes[VoiceField.date] as DateTime? ?? base!.date,
    description:
        _changes[VoiceField.description] as String? ?? base?.description ?? '',
  );

  void _review() {
    _confirming = true;
    final draft = _draft(_editing);
    final date = DateFormat.yMMMMd().format(draft.date);
    final action = _adding
        ? 'New expense'
        : 'Update expense ID ${_editing!.id}';
    if (_hidden) {
      _reply(
        '$action is ready. Say save to confirm or name a field to change.',
      );
      return;
    }
    final amount = ', ${money(draft.amount, false)}';
    final note = draft.description.isEmpty ? '' : ', note ${draft.description}';
    _reply(
      '$action: ${draft.category}, $date$amount$note. Say save to confirm or name a field to change.',
    );
  }

  Future<void> _save() async {
    final controller = widget.controller;
    final id = _editing?.id;
    try {
      if (id == null) {
        await controller.save(_draft(null));
      } else {
        final values = _draft(_editing).toJson();
        await controller.updateExpenseFields(id, {
          for (final field in _changes.keys)
            field.name: values[field.name] as Object,
        }, date: _changes[VoiceField.date] as DateTime?);
      }
      if (!mounted) return;
      _reset();
      _reply(
        controller.error?.startsWith('Expense saved;') == true
            ? 'Expense saved. The expense list could not refresh.'
            : id == null
            ? 'Expense added.'
            : 'Expense ID $id updated.',
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not save the expense. Check the expense list before retrying.',
        );
      }
    }
  }

  Future<void> _answer(String question) async {
    final controller = widget.controller;
    await controller.restorePrivacy();
    if (!mounted) return;
    if (controller.hidden) {
      _reply(
        'Amounts are hidden. Turn off amount privacy to hear spending answers.',
      );
      return;
    }
    if (controller.updatedAt == null || controller.stale) {
      await controller.refresh();
    }
    if (!mounted) return;
    if (controller.updatedAt == null) {
      _reply(
        'Expense data is unavailable. Try again after the tracker connects.',
      );
      return;
    }
    final answer = spendingAnswer(
      question,
      controller.expenses,
      DateTime.now(),
      hidden: controller.hidden,
    );
    _reply(
      controller.stale && !controller.hidden
          ? 'From saved data: $answer'
          : answer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _busy
        ? 'Processing…'
        : _stopping
        ? 'Transcribing…'
        : _recording
        ? 'Listening…'
        : _session != null
        ? 'Preparing microphone…'
        : 'Push to talk';
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Expense assistant',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(_prompt),
            if (_heard != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Heard: $_heard'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 16),
            GestureDetector(
              onLongPressStart: _session == null && !_busy
                  ? (_) => unawaited(_listen(held: true))
                  : null,
              onLongPressEnd: (_) {
                if (_held) _stop(release: true);
              },
              child: FilledButton.icon(
                onPressed: _busy || _stopping
                    ? null
                    : _session == null
                    ? () => unawaited(_listen())
                    : _recording
                    ? _stop
                    : null,
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(status),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap to start, then tap again to stop. You can also hold to talk and release to stop. Voice sends audio to the tracker server and requires a connection.',
            ),
          ],
        ),
      ),
    );
  }
}
