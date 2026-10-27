import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';
import '../../models/tracker_entry.dart';

/// Результат диалога добавления трекера: имя свойства и его тип.
typedef NewTracker = ({String name, TrackerPropertyKind kind});

/// Диалог добавления трекера вручную: имя свойства и тип (привычка или метрика).
Future<NewTracker?> showAddTrackerDialog(
  BuildContext context,
  AppStrings strings, {
  String? initialName,
}) {
  final controller = TextEditingController(text: initialName ?? '');
  var kind = TrackerPropertyKind.boolean;
  return showDialog<NewTracker>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(strings.t('trackerAddTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('tracker_add_name'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: strings.t('trackerAddName'),
                hintText: strings.t('trackerAddNameHint'),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                strings.t('trackerAddKind'),
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<TrackerPropertyKind>(
              segments: [
                ButtonSegment(
                  value: TrackerPropertyKind.boolean,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(strings.t('trackerAddHabit')),
                ),
                ButtonSegment(
                  value: TrackerPropertyKind.number,
                  icon: const Icon(Icons.show_chart),
                  label: Text(strings.t('trackerAddMetric')),
                ),
              ],
              selected: {kind},
              onSelectionChanged: (value) => setState(() => kind = value.first),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(strings.t('trackerAddNameRequired'))),
                );
                return;
              }
              Navigator.pop(dialogContext, (name: name, kind: kind));
            },
            child: Text(strings.t('ok')),
          ),
        ],
      ),
    ),
  ).whenComplete(controller.dispose);
}
