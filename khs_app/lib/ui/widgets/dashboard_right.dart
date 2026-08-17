import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../state/app_state.dart';
import 'reminder_card.dart';
import 'timeline_panel.dart';

/// Правая панель дашборда: неделя-календарь, таймлайн дня, напоминание.
class DashboardRightPanel extends StatelessWidget {
  const DashboardRightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final selected = state.selectedDate;

    final dayTasks = state.tasksForSelectedDate
        .where((t) => !t.completed)
        .toList();
    final timed =
        dayTasks
            .where(
              (t) =>
                  t.dueAt != null &&
                  (t.dueAt!.hour != 0 || t.dueAt!.minute != 0),
            )
            .toList()
          ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));

    final reminder = state.nextReminder;
    String? reminderSubtitle;
    if (reminder != null) {
      final r = reminder.reminderAt!;
      final hh = r.hour.toString().padLeft(2, '0');
      final mm = r.minute.toString().padLeft(2, '0');
      final now = DateTime.now();
      final isToday =
          r.year == now.year && r.month == now.month && r.day == now.day;
      reminderSubtitle = isToday
          ? '${strings.t('today')}, $hh:$mm'
          : '${DateFormat('EEE', strings.locale).format(r)}, $hh:$mm';
    }

    return Container(
      width: 320,
      color: scheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeekStrip(selected: selected),
            const SizedBox(height: 24),
            TimelinePanel(tasks: timed, title: strings.t('schedule')),
            const SizedBox(height: 24),
            ReminderCard(
              task: reminder,
              title: reminder?.title ?? '',
              subtitle: reminderSubtitle,
              dismissTooltip: strings.t('delete'),
              onDismiss: () {
                if (reminder != null) state.clearReminder(reminder);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStrip extends StatelessWidget {
  final DateTime selected;

  const _WeekStrip({required this.selected});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateFormat = DateFormat('E', strings.locale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.t('calendar'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final day in days) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => state.selectDate(day),
                  child: Container(
                    height: 54,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: day == selected
                          ? scheme.primary
                          : scheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: day == today && day != selected
                          ? Border.all(color: scheme.primary)
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          dateFormat.format(day),
                          style: TextStyle(
                            fontSize: 10,
                            color: day == selected
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: day == selected
                                ? scheme.onPrimary
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _hasTasks(state.tasks, day)
                                ? (day == selected
                                      ? scheme.onPrimary
                                      : scheme.primary)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  bool _hasTasks(List<Task> tasks, DateTime day) {
    return tasks.any(
      (t) =>
          !t.completed &&
          t.dueAt != null &&
          t.dueAt!.year == day.year &&
          t.dueAt!.month == day.month &&
          t.dueAt!.day == day.day,
    );
  }
}
