import 'package:flutter/material.dart';

import '../../localization/app_strings.dart';

/// Открывает нижнюю панель выбора времени с двумя вертикальными колёсами
/// (часы и минуты). Возвращает выбранное время или null при отмене.
Future<TimeOfDay?> showTimeWheelPicker(
  BuildContext context, {
  required AppStrings strings,
  required TimeOfDay initial,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: true,
    builder: (_) => TimeWheelSheet(initial: initial, strings: strings),
  );
}

/// Нижняя панель выбора времени: два вертикальных колеса (часы и минуты).
class TimeWheelSheet extends StatefulWidget {
  final TimeOfDay initial;
  final AppStrings strings;

  const TimeWheelSheet({
    super.key,
    required this.initial,
    required this.strings,
  });

  @override
  State<TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<TimeWheelSheet> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  late final FixedExtentScrollController _hoursCtrl =
      FixedExtentScrollController(initialItem: widget.initial.hour);
  late final FixedExtentScrollController _minutesCtrl =
      FixedExtentScrollController(initialItem: widget.initial.minute);

  @override
  void dispose() {
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.strings;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.t('chooseTime'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: WheelColumn(
                    controller: _hoursCtrl,
                    label: strings.t('hours'),
                    items: List.generate(
                      24,
                      (i) => i.toString().padLeft(2, '0'),
                    ),
                    onChanged: (i) => setState(() => _hour = i),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: WheelColumn(
                    controller: _minutesCtrl,
                    label: strings.t('minutes'),
                    items: List.generate(
                      60,
                      (i) => i.toString().padLeft(2, '0'),
                    ),
                    onChanged: (i) => setState(() => _minute = i),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(strings.t('cancel')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    TimeOfDay(hour: _hour, minute: _minute),
                  ),
                  child: Text(strings.t('ok')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Одно вертикальное колесо выбора.
class WheelColumn extends StatelessWidget {
  final FixedExtentScrollController controller;
  final String label;
  final List<String> items;
  final ValueChanged<int> onChanged;

  const WheelColumn({
    super.key,
    required this.controller,
    required this.label,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        SizedBox(
          height: 180,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: controller,
                itemExtent: 40,
                useMagnifier: true,
                magnification: 1.15,
                diameterRatio: 1.6,
                onSelectedItemChanged: onChanged,
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: items.length,
                  builder: (context, i) => Center(
                    child: Text(
                      items[i],
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
