import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../app_theme.dart';

/// Временная шкала дня: слева время, справа цветные полосы задач.
class TimelinePanel extends StatelessWidget {
  final List<Task> tasks;
  final String title;

  const TimelinePanel({super.key, required this.tasks, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(title, style: Theme.of(context).textTheme.titleSmall),
        ),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('—', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        for (final task in tasks) _TimelineRow(task: task),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  final Task task;

  const _TimelineRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final color = task.category == null
        ? AppTheme.accentBlue
        : AppTheme.groupColor(task.category!);
    final start = task.dueAt;
    final hh = (start?.hour ?? 0).toString().padLeft(2, '0');
    final mm = (start?.minute ?? 0).toString().padLeft(2, '0');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '$hh:$mm',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Container(width: 3, height: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
