import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import 'widgets/time_wheel_picker.dart';

class TaskEditScreen extends StatefulWidget {
  final Task? task;
  final DateTime? defaultDate;

  const TaskEditScreen({super.key, this.task, this.defaultDate});

  @override
  State<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends State<TaskEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;
  late DateTime? _dueDate;
  late TimeOfDay? _dueTime;
  late int _priority;
  late String _recurrence;
  late int _reminderMinutes; // 0 = on time, -1 = none
  late bool _notify;
  late String? _category;

  bool get _isNew => widget.task == null;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    _titleController = TextEditingController(text: task?.title ?? '');
    _notesController = TextEditingController(text: task?.notes ?? '');
    _dueDate =
        task?.dueDate ?? (widget.defaultDate ?? _dateOnly(DateTime.now()));
    _dueTime = task?.dueAt == null
        ? null
        : TimeOfDay.fromDateTime(task!.dueAt!);
    _priority = task?.priority ?? 1;
    _recurrence = task?.recurrence ?? '';
    // Новая задача по умолчанию напоминает в срок (0), чтобы пуш пришёл сам.
    _reminderMinutes = task == null
        ? 0
        : _reminderFrom(task.reminderAt, task.dueAt);
    _notify = task?.notify ?? true;
    _category = task?.category;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  int _reminderFrom(DateTime? reminder, DateTime? due) {
    if (reminder == null || due == null) return -1;
    final diff = due.difference(reminder).inMinutes;
    if (diff <= 0) return 0;
    return diff;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime? get _dueAt {
    if (_dueDate == null) return null;
    var result = _dueDate!;
    if (_dueTime != null) {
      result = result.add(
        Duration(hours: _dueTime!.hour, minutes: _dueTime!.minute),
      );
    }
    return result;
  }

  DateTime? get _reminderAt {
    if (_reminderMinutes < 0 || _dueAt == null) return null;
    if (_reminderMinutes == 0) return _dueAt;
    return _dueAt!.subtract(Duration(minutes: _reminderMinutes));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _dueDate = _dateOnly(picked));
  }

  Future<void> _pickTime() async {
    final strings = context.read<AppState>().strings;
    final picked = await showTimeWheelPicker(
      context,
      initial: _dueTime ?? const TimeOfDay(hour: 9, minute: 0),
      strings: strings,
    );
    if (picked != null) setState(() => _dueTime = picked);
  }

  Future<void> _createGroup(BuildContext context, AppState state) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(state.strings.t('createGroup')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: state.strings.t('groupName')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(state.strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(state.strings.t('create')),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await state.createGroup(name);
      if (mounted) setState(() => _category = name);
    }
  }

  Future<void> _save() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.t('taskTitleRequired'))));
      return;
    }

    final effectiveDueAt = _recurrence.isNotEmpty
        ? (() {
            final now = DateTime.now();
            final base = DateTime(now.year, now.month, now.day);
            if (_dueTime != null) {
              return base.add(
                Duration(hours: _dueTime!.hour, minutes: _dueTime!.minute),
              );
            }
            return base;
          })()
        : _dueAt;
    final effectiveReminder = _recurrence.isNotEmpty
        ? (effectiveDueAt == null ? null : effectiveDueAt)
        : _reminderAt;

    if (_isNew) {
      await state.addTask(
        Task(
          title: title,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          dueAt: effectiveDueAt,
          priority: _priority,
          recurrence: _recurrence,
          reminderAt: effectiveReminder,
          category: _category,
          notify: _notify,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await state.updateTask(
        widget.task!.copyWith(
          title: title,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          dueAt: effectiveDueAt,
          priority: _priority,
          recurrence: _recurrence,
          reminderAt: effectiveReminder,
          category: _category,
          notify: _notify,
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final dateFormat = DateFormat('d MMMM yyyy', strings.locale);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? strings.t('addTask') : strings.t('editTask')),
        actions: [
          if (!_isNew)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(strings.t('deleteConfirm')),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(strings.t('cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          strings.t('delete'),
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await state.deleteTask(widget.task!);
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            autofocus: _isNew,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.t('title'),
              hintText: strings.t('titleHint'),
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.edit),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: strings.t('notes'),
              hintText: strings.t('notesHint'),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.event),
                  title: Text(strings.t('dueDate')),
                  subtitle: Text(
                    _recurrence.isNotEmpty
                        ? strings.t('recurringAutoDate')
                        : _dueDate == null
                            ? strings.t('noDueDate')
                            : dateFormat.format(_dueDate!),
                  ),
                  trailing: _recurrence.isNotEmpty
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _dueDate == null
                                  ? null
                                  : () => setState(() => _dueDate = null),
                            ),
                            IconButton(
                              icon: const Icon(Icons.calendar_month),
                              onPressed: _pickDate,
                            ),
                          ],
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: Text(strings.t('dueTime')),
                  subtitle: Text(
                    _dueTime == null
                        ? strings.t('noDueDate')
                        : _dueTime!.format(context),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _dueTime == null
                            ? null
                            : () => setState(() => _dueTime = null),
                      ),
                      IconButton(
                        icon: const Icon(Icons.access_time),
                        onPressed: _pickTime,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.repeat),
                  title: Text(strings.t('recurrence')),
                  trailing: DropdownButton<String>(
                    value: _recurrence,
                    underline: const SizedBox.shrink(),
                    items: [
                      DropdownMenuItem(
                        value: '',
                        child: Text(strings.t('never')),
                      ),
                      DropdownMenuItem(
                        value: 'daily',
                        child: Text(strings.t('daily')),
                      ),
                      DropdownMenuItem(
                        value: 'weekly',
                        child: Text(strings.t('weekly')),
                      ),
                      DropdownMenuItem(
                        value: 'monthly',
                        child: Text(strings.t('monthly')),
                      ),
                    ],
                    onChanged: (v) => setState(() => _recurrence = v ?? ''),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            strings.t('groups'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(strings.t('noGroup')),
                    ),
                    for (final g in state.groups)
                      DropdownMenuItem<String?>(value: g, child: Text(g)),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: strings.t('createGroup'),
                icon: const Icon(Icons.add),
                onPressed: () => _createGroup(context, state),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            strings.t('priority'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                label: Text(strings.t('low')),
                icon: const Icon(Icons.flag_outlined),
              ),
              ButtonSegment(
                value: 1,
                label: Text(strings.t('normal')),
                icon: const Icon(Icons.flag),
              ),
              ButtonSegment(
                value: 2,
                label: Text(strings.t('high')),
                icon: const Icon(Icons.flag, color: Colors.redAccent),
              ),
            ],
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
          ),
          const SizedBox(height: 16),
          Text(
            strings.t('reminder'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _reminderMinutes,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: [
              DropdownMenuItem(value: -1, child: Text(strings.t('noReminder'))),
              DropdownMenuItem(
                value: 0,
                child: Text(strings.t('remindOnTime')),
              ),
              DropdownMenuItem(value: 5, child: Text(strings.t('remind5min'))),
              DropdownMenuItem(
                value: 30,
                child: Text(strings.t('remind30min')),
              ),
              DropdownMenuItem(
                value: 60,
                child: Text(strings.t('remind1hour')),
              ),
              DropdownMenuItem(
                value: 1440,
                child: Text(strings.t('remind1day')),
              ),
            ],
            onChanged: (v) => setState(() => _reminderMinutes = v ?? -1),
          ),
          const SizedBox(height: 8),
          Card(
            child: SwitchListTile(
              value: _notify,
              onChanged: (v) => setState(() => _notify = v),
              secondary: const Icon(Icons.notifications_active_outlined),
              title: Text(strings.t('notifyReminder')),
              subtitle: Text(strings.t('notifyReminderSubtitle')),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(strings.t('save')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              textStyle: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
