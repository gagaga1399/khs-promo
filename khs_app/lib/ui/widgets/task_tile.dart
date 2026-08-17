import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../models/task.dart';
import '../app_theme.dart';

class TaskTile extends StatelessWidget {
  final Task task;
  final AppStrings strings;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const TaskTile({
    super.key,
    required this.task,
    required this.strings,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  Color get _priorityColor {
    switch (task.priority) {
      case 2:
        return Colors.redAccent;
      case 0:
        return Colors.grey;
      default:
        return Colors.amber;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overdue =
        !task.completed &&
        task.dueAt != null &&
        task.dueAt!.isBefore(DateTime.now());
    final subtitleParts = <String>[];
    if (task.dueTime != null) subtitleParts.add(task.dueTime!);
    if (task.isRecurring) subtitleParts.add(_recurrenceLabel);
    if (task.reminderAt != null) {
      subtitleParts.add(
        '${strings.t('reminder')} ${_timeOf(task.reminderAt!)}',
      );
    }

    return Dismissible(
      key: ValueKey('task-${task.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade700,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
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
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: task.category == null
                        ? Colors.transparent
                        : AppTheme.groupColor(task.category!),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: task.completed,
                  onChanged: (v) => onToggle(v ?? false),
                  shape: const CircleBorder(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (task.priority > 0) ...[
                            Icon(Icons.flag, size: 14, color: _priorityColor),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 16,
                                decoration: task.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.completed
                                    ? Theme.of(context).disabledColor
                                    : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' · '),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: overdue
                                    ? Colors.redAccent
                                    : Theme.of(context).disabledColor,
                              ),
                        ),
                      if (task.completed)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 13,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                strings.t('done'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (task.completed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.check_circle,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _recurrenceLabel {
    switch (task.recurrence) {
      case 'daily':
        return strings.t('daily');
      case 'weekly':
        return strings.t('weekly');
      case 'monthly':
        return strings.t('monthly');
      default:
        return '';
    }
  }

  String _timeOf(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
