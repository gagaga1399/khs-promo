import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import 'task_edit_screen.dart';
import 'widgets/task_tile.dart';

/// Подстраница «Задачи» внутри панели заметок: все активные задачи,
/// сгруппированные по срокам (просроченные / сегодня / далее / без даты).
class NotesTasksScreen extends StatelessWidget {
  const NotesTasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final overdue = <Task>[];
    final todayTasks = <Task>[];
    final later = <Task>[];
    final noDate = <Task>[];
    for (final t in state.tasks.where((t) => !t.completed)) {
      final due = t.dueAt;
      if (due == null) {
        noDate.add(t);
        continue;
      }
      final day = DateTime(due.year, due.month, due.day);
      if (day.isBefore(today)) {
        overdue.add(t);
      } else if (day == today) {
        todayTasks.add(t);
      } else {
        later.add(t);
      }
    }
    int byDue(Task a, Task b) {
      final ad = a.dueAt;
      final bd = b.dueAt;
      if (ad == null || bd == null) return 0;
      return ad.compareTo(bd);
    }

    overdue.sort(byDue);
    todayTasks.sort(byDue);
    later.sort(byDue);
    noDate.sort((a, b) {
      final ad = a.dueAt;
      final bd = b.dueAt;
      if (ad == null || bd == null) return 0;
      return ad.compareTo(bd);
    });

    final sections = <(String, List<Task>)>[
      if (overdue.isNotEmpty) (strings.t('overdue'), overdue),
      if (todayTasks.isNotEmpty) (strings.t('today'), todayTasks),
      if (later.isNotEmpty) (strings.t('laterTasks'), later),
      if (noDate.isNotEmpty) (strings.t('withoutDate'), noDate),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('tasks'))),
      body: sections.isEmpty
          ? Center(
              child: Text(
                strings.t('emptyAll'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                for (final (title, tasks) in sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${tasks.length}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final task in tasks)
                    TaskTile(
                      task: task,
                      strings: strings,
                      onToggle: (v) => state.toggleCompleted(task),
                      onTap: () {
                        state.selectTask(task);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskEditScreen(task: task),
                          ),
                        );
                      },
                      onDelete: () => state.deleteTask(task),
                    ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
    );
  }
}
