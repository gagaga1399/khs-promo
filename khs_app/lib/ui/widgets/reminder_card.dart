import 'package:flutter/material.dart';

import '../../models/task.dart';
import '../app_theme.dart';

/// Компактная карточка ближайшего напоминания (референс: «Amanda at Ruth's, Today, 4 p.m.»).
class ReminderCard extends StatelessWidget {
  final Task? task;
  final String title;
  final String? subtitle;
  final String dismissTooltip;
  final VoidCallback onDismiss;

  const ReminderCard({
    super.key,
    required this.task,
    required this.title,
    this.subtitle,
    required this.dismissTooltip,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final t = task;
    if (t == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.notifications_active,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: dismissTooltip,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
          ),
        ],
      ),
    );
  }
}
