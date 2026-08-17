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

    DateTime? reminder;
    if (parsed.hasReminder && parsed.dueAt != null) {
      reminder = parsed.dueAt;
    }

    await state.addTask(
      Task(
        title: parsed.title,
        dueAt: parsed.dueAt,
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
