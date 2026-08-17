import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import 'notes_editor_screen.dart';
import 'task_edit_screen.dart';
import 'widgets/task_tile.dart';

class CalendarScreen extends StatefulWidget {
  /// [embedded] — вкладка нижней навигации на телефоне (без собственного
  /// Scaffold и шапки). Иначе экран открывается отдельным окном (ПК).
  const CalendarScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;
  DateTime? _lastTapDay;
  DateTime? _lastTapAt;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _focusedDay = state.selectedDate;
    _selectedDay = state.selectedDate;
  }

  /// Задачи с сроком на выбранный день (включая выполненные — они
  /// остаются в списке с пометкой, а на сетке дают маркер).
  List<Task> _tasksForDay(DateTime day, List<Task> all) {
    return all
        .where(
          (t) =>
              t.dueAt != null &&
              t.dueAt!.year == day.year &&
              t.dueAt!.month == day.month &&
              t.dueAt!.day == day.day,
        )
        .toList();
  }

  Future<void> _openDayNotes(DateTime day) async {
    final state = context.read<AppState>();
    final existing = state.notesForDate(day);
    if (existing.isNotEmpty) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NotesEditorScreen(note: existing.first),
        ),
      );
      return;
    }
    String prefill = '';
    if (state.obsidian.isConfigured) {
      prefill = await state.obsidian.readDailyNoteBody(day);
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesEditorScreen(date: day, initialContent: prefill),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final all = state.tasks;
    final dayTasks = _tasksForDay(_selectedDay, all);
    final dateFormat = DateFormat('d MMMM yyyy', strings.locale);

    final body = Column(
      children: [
        TableCalendar<Object>(
          firstDay: DateTime(2020),
          lastDay: DateTime(2035),
          focusedDay: _focusedDay,
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selected, focused) {
            final now = DateTime.now();
            final isDouble =
                isSameDay(_lastTapDay, selected) &&
                _lastTapAt != null &&
                now.difference(_lastTapAt!) < const Duration(milliseconds: 350);
            setState(() {
              _selectedDay = selected;
              _focusedDay = focused;
            });
            _lastTapDay = selected;
            _lastTapAt = now;
            if (isDouble) _openDayNotes(selected);
          },
          eventLoader: (day) {
            return _tasksForDay(day, all);
          },
          locale: strings.locale,
          startingDayOfWeek: StartingDayOfWeek.monday,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {
            CalendarFormat.month: 'Month',
            CalendarFormat.week: 'Week',
          },
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          calendarStyle: CalendarStyle(
            markerDecoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                Icons.task_alt,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${strings.t('tasksFor')} ${dateFormat.format(_selectedDay)}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_calendar_outlined),
                tooltip: strings.t('createNote'),
                onPressed: () => _openDayNotes(_selectedDay),
              ),
              IconButton(
                icon: const Icon(Icons.add_task),
                tooltip: strings.t('addTaskShort'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TaskEditScreen(defaultDate: _selectedDay),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: dayTasks.isEmpty
              ? Center(child: Text(strings.t('emptyTasks')))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: dayTasks.length,
                  itemBuilder: (context, i) {
                    final task = dayTasks[i];
                    return TaskTile(
                      task: task,
                      strings: strings,
                      onToggle: (v) => state.toggleCompleted(task),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskEditScreen(task: task),
                        ),
                      ),
                      onDelete: () => state.deleteTask(task),
                    );
                  },
                ),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t('calendar')),
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: strings.t('back'),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: body,
    );
  }
}


