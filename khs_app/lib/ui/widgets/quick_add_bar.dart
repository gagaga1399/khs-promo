import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../state/app_state.dart';

class QuickAddBar extends StatefulWidget {
  const QuickAddBar({super.key});

  @override
  State<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends State<QuickAddBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final parsed = state.parseQuick(text);
    if (parsed.title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('taskTitleRequired'))));
      return;
    }

    // Время без даты и уже прошло сегодня: час неоднозначен — спрашиваем
    // «утро или вечер» (9:00 или 21:00). Не угадываем дату молча.
    DateTime? dueAt = parsed.dueAt;
    final th = parsed.timeHour;
    final tm = parsed.timeMinute;
    if (dueAt != null &&
        th != null &&
        tm != null &&
        th >= 1 &&
        th <= 12 &&
        dueAt.isBefore(DateTime.now())) {
      if (!mounted) return;
      final chosen = await _resolveAmbiguousHour(th, tm);
      if (chosen != null) {
        final now = DateTime.now();
        dueAt = DateTime(
          now.year,
          now.month,
          now.day,
          chosen.hour,
          chosen.minute,
        );
      }
    }

    DateTime? reminder;
    if (parsed.hasReminder && dueAt != null) {
      reminder = dueAt;
    }

    await state.addTask(
      Task(
        title: parsed.title,
        dueAt: dueAt,
        priority: parsed.priority,
        recurrence: parsed.recurrence,
        reminderAt: reminder,
        createdAt: DateTime.now(),
      ),
    );
    if (!mounted) return;
    _controller.clear();
    _focusNode.requestFocus();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('✓ ${parsed.title}')));
  }

  Future<TimeOfDay?> _resolveAmbiguousHour(int hour, int minute) async {
    final strings = context.read<AppState>().strings;
    return showDialog<TimeOfDay>(
      context: context,
      builder: (ctx) {
        final am = TimeOfDay(hour: hour, minute: minute);
        final pm = TimeOfDay(hour: hour + 12, minute: minute);
        return AlertDialog(
          icon: const Icon(Icons.schedule, size: 32),
          title: Text(strings.t('askTimeTitle')),
          content: Text(strings.t('askTimeBody')),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.wb_sunny_outlined),
              label: Text(
                '${am.format(ctx)}\n${strings.t('askTimeMorning')}',
                textAlign: TextAlign.center,
              ),
              onPressed: () => Navigator.of(ctx).pop(am),
            ),
            TextButton.icon(
              icon: const Icon(Icons.nightlight_outlined),
              label: Text(
                '${pm.format(ctx)}\n${strings.t('askTimeEvening')}',
                textAlign: TextAlign.center,
              ),
              onPressed: () => Navigator.of(ctx).pop(pm),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: strings.t('quickAddHint'),
            helperText: strings.t('quickAddExample'),
            helperMaxLines: 2,
            prefixIcon: const Icon(Icons.add_circle_outline),
            suffixIcon: IconButton(
              icon: Icon(Icons.send, color: scheme.primary),
              tooltip: strings.t('save'),
              onPressed: _submit,
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ),
    );
  }
}
