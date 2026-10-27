import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'tracker_accent.dart';

/// Состояние привычки в конкретный день.
enum HabitDay { missing, no, yes }

/// Тепловая карта привычки в стиле GitHub: строки — дни недели (пн сверху),
/// столбцы — недели; сегодня всегда в правом нижнем углу.
///
/// Отсутствие данных за день — бледная клетка, явное `false` — заметный
/// «пусто», `true` — заливка акцентным цветом.
class HabitHeatmap extends StatelessWidget {
  const HabitHeatmap({
    super.key,
    required this.end,
    required this.weeks,
    required this.values,
    this.accent,
    this.weekdayLabels = const ['Пн', 'Ср', 'Пт'],
    this.labelsWidth = 18,
  });

  /// Последняя дата (обычно сегодня).
  final DateTime end;

  /// Сколько столбцов-недель отрисовать.
  final int weeks;

  /// Значение на конкретный день (ключ — дата без времени).
  final Map<DateTime, HabitDay> values;

  /// Цвет «выполненных» дней. По умолчанию — основной цвет темы.
  final Color? accent;

  /// Подписи строк недели, оставляемые в левом гуттере.
  final List<String> weekdayLabels;

  /// Ширина левого гуттера под подписи дней.
  final double labelsWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 400.0;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 96.0;
        return CustomPaint(
          size: Size(width, height),
          painter: _HeatmapPainter(
            values: values,
            end: end,
            weeks: weeks,
            cellRadius: 2.2,
            background: scheme.surfaceContainerHighest,
            outline: scheme.outlineVariant,
            empty: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            noColor: scheme.onSurfaceVariant.withValues(alpha: 0.28),
            yesColor: accent ?? trackerBaseAccent(context),
            labelStyle:
                Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ) ??
                const TextStyle(fontSize: 11),
            labelsWidth: labelsWidth,
            weekdayLabels: weekdayLabels,
          ),
        );
      },
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.values,
    required this.end,
    required this.weeks,
    required this.cellRadius,
    required this.background,
    required this.outline,
    required this.empty,
    required this.noColor,
    required this.yesColor,
    required this.labelStyle,
    required this.labelsWidth,
    required this.weekdayLabels,
  });

  final Map<DateTime, HabitDay> values;
  final DateTime end;
  final int weeks;
  final double cellRadius;
  final Color background;
  final Color outline;
  final Color empty;
  final Color noColor;
  final Color yesColor;
  final TextStyle labelStyle;
  final double labelsWidth;
  final List<String> weekdayLabels;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks <= 0) return;
    final gridWidth = size.width - labelsWidth;
    if (gridWidth <= 0) return;

    final cellW = gridWidth / weeks;
    final cellH = size.height / 7;
    final cell = math.min(cellW, cellH);

    // Понедельник последнего столбца — неделя содержит `end`.
    final lastMonday = DateTime(end.year, end.month, end.day)
        .subtract(Duration(days: end.weekday - 1));

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, cell, cell),
      Radius.circular(cellRadius),
    );
    final dayPaint = Paint();
    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var w = 0; w < weeks; w++) {
      final columnMonday = lastMonday.subtract(Duration(days: (weeks - 1 - w) * 7));
      for (var row = 0; row < 7; row++) {
        final day = columnMonday.add(Duration(days: row));
        if (day.isAfter(end)) continue;
        final state =
            values[DateTime(day.year, day.month, day.day)] ?? HabitDay.missing;
        final x = labelsWidth + w * cellW + (cellW - cell) / 2;
        final y = row * cellH + (cellH - cell) / 2;
        dayPaint.color = switch (state) {
          HabitDay.yes => yesColor,
          HabitDay.no => noColor,
          HabitDay.missing => empty,
        };
        canvas.drawRRect(rect.shift(Offset(x, y)), dayPaint);
        if (state == HabitDay.missing || state == HabitDay.no) {
          outlinePaint.color = outline.withValues(alpha: 0.6);
          canvas.drawRRect(
            rect.shift(Offset(x, y)),
            outlinePaint,
          );
        }
      }
    }

    // Подписи дней недели слева.
    for (var row = 0; row < 7; row++) {
      if (row.isOdd) continue;
      final idx = row ~/ 2;
      if (idx >= weekdayLabels.length) break;
      final painter = TextPainter(
        text: TextSpan(text: weekdayLabels[idx], style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          (labelsWidth - painter.width) / 2,
          row * cellH + (cellH - painter.height) / 2 + 1,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.values != values ||
      old.end != end ||
      old.weeks != weeks ||
      old.yesColor != yesColor;
}

/// Полоса последних дней для превью привычки на карточке: каждая точка —
/// один день (неделя-столбец отсутствует, чтобы не путать), под точками —
/// числа месяца, сегодня — правая точка в кольце, выполненные дни —
/// акцентным цветом. Под полосой — легенда цветов.
class HabitStrip extends StatelessWidget {
  const HabitStrip({
    super.key,
    required this.end,
    required this.days,
    required this.values,
    this.accent,
    this.legend = const [],
    this.showDayNumbers = true,
  });

  /// Последняя дата (обычно сегодня) — ей соответствует правый квадратик.
  final DateTime end;

  /// Сколько дней нарисовать (точка = день).
  final int days;

  /// Значение на конкретный день (ключ — дата без времени).
  final Map<DateTime, HabitDay> values;

  /// Цвет «выполненных» дней. По умолчанию — основной цвет темы.
  final Color? accent;

  /// Подписи легенды в порядке: сделано, нет, нет данных, сегодня.
  final List<String> legend;

  /// Подписывать каждый квадратик числом дня месяца.
  final bool showDayNumbers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? trackerBaseAccent(context);
    final textStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 4.0;
        final width = constraints.maxWidth > 0
            ? (constraints.maxWidth - gap * (days - 1)) / days
            : 0.0;
        final dot = width.clamp(6.0, 18.0).toDouble();
        final showNumbers = showDayNumbers && dot >= 9;
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < days; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  _dayDot(scheme, color, i, dot),
                ],
              ],
            ),
            if (showNumbers) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < days; i++) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(width: dot, child: _dayLabel(i, dot, textStyle)),
                  ],
                ],
              ),
            ],
            if (legend.length >= 4) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 4,
                children: [
                  _legendItem(
                    scheme,
                    color,
                    textStyle,
                    fill: color,
                    label: legend[0],
                  ),
                  _legendItem(
                    scheme,
                    color,
                    textStyle,
                    fill: scheme.onSurfaceVariant.withValues(alpha: 0.28),
                    label: legend[1],
                  ),
                  _legendItem(
                    scheme,
                    color,
                    textStyle,
                    fill: scheme.surfaceContainerHighest.withValues(alpha: 0.75),
                    label: legend[2],
                  ),
                  _legendItem(
                    scheme,
                    color,
                    textStyle,
                    fill: color,
                    label: legend[3],
                    ring: true,
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _dayDot(ColorScheme scheme, Color color, int i, double dot) {
    final day = end.subtract(Duration(days: days - 1 - i));
    final state =
        values[DateTime(day.year, day.month, day.day)] ?? HabitDay.missing;
    final isToday = i == days - 1;
    final fill = switch (state) {
      HabitDay.yes => color,
      HabitDay.no => scheme.onSurfaceVariant.withValues(alpha: 0.28),
      HabitDay.missing => scheme.surfaceContainerHighest.withValues(alpha: 0.35),
    };
    return Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(dot / 2),
        border: isToday ? Border.all(color: color, width: 1.6) : null,
      ),
      child: isToday
          ? Center(
              child: Container(
                width: (dot - 6).clamp(2.0, double.infinity).toDouble(),
                height: (dot - 6).clamp(2.0, double.infinity).toDouble(),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }

  Widget _dayLabel(int i, double dot, TextStyle? style) {
    final date = end.subtract(Duration(days: days - 1 - i));
    return Text(
      '${date.day}',
      textAlign: TextAlign.center,
      style: dot >= 11 ? style : style?.copyWith(fontSize: 8),
    );
  }

  Widget _legendItem(
    ColorScheme scheme,
    Color color,
    TextStyle? style, {
    required Color fill,
    required String label,
    bool ring = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(5),
            border: ring ? Border.all(color: color, width: 1.4) : null,
          ),
          child: ring
              ? Center(
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(width: 5),
        Text(label, style: style),
      ],
    );
  }
}

  /// Год привычки календарём из точек: строка — месяц, столбец — день месяца,
/// выполненные дни — акцентным цветом, сегодня — точка в кольце. Тот же
/// «точечный» вид, что у карточки-превью, только за год, а не за месяц.
class HabitYearGrid extends StatelessWidget {
  const HabitYearGrid({
    super.key,
    required this.end,
    required this.values,
    this.accent,
    this.months = 12,
    this.locale = 'ru',
  });

  /// Последний день (обычно сегодня).
  final DateTime end;

  /// Значение на конкретный день (ключ — дата без времени).
  final Map<DateTime, HabitDay> values;

  /// Цвет «выполненных» дней. По умолчанию — цвет трекеров.
  final Color? accent;

  /// Сколько месяцев показать (12 — год).
  final int months;

  /// Язык подписей месяцев: 'ru' или 'en'.
  final String locale;

  static const _monthsRu = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  static const _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = accent ?? trackerBaseAccent(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 10,
    );
    final today = DateTime(end.year, end.month, end.day);
    final firstMonth = DateTime(end.year, end.month - (months - 1), 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelW = 54.0;
        const gap = 8.0;
        const cols = 31;
        final avail = constraints.maxWidth - labelW - gap;
        final cell = (avail / cols).clamp(6.0, 18.0).toDouble();
        final dot = (cell - 3).clamp(3.0, 14.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dot >= 8) _dayHeader(labelW, gap, cell, labelStyle),
            for (var i = 0; i < months; i++)
              _monthRow(
                scheme,
                color,
                labelStyle,
                DateTime(firstMonth.year, firstMonth.month + i, 1),
                today,
                labelW,
                gap,
                cell,
                dot,
              ),
          ],
        );
      },
    );
  }

  Widget _dayHeader(
    double labelW,
    double gap,
    double cell,
    TextStyle? style,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(width: labelW),
          SizedBox(width: gap),
          for (var d = 1; d <= 31; d++)
            SizedBox(
              width: cell,
              child: Center(
                child: Text(
                  '$d',
                  textAlign: TextAlign.center,
                  style: style?.copyWith(fontSize: cell >= 12 ? 9 : 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthRow(
    ColorScheme scheme,
    Color color,
    TextStyle? style,
    DateTime month,
    DateTime today,
    double labelW,
    double gap,
    double cell,
    double dot,
  ) {
    final names = locale == 'ru' ? _monthsRu : _monthsEn;
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final year = (month.year % 100).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelW,
            child: Text('${names[month.month - 1]} $year', style: style),
          ),
          SizedBox(width: gap),
          for (var d = 1; d <= 31; d++)
            SizedBox(
              width: cell,
              child: Center(
                child: d <= lastDay
                    ? _dotCell(scheme, color, month, d, today, dot)
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dotCell(
    ColorScheme scheme,
    Color color,
    DateTime month,
    int d,
    DateTime today,
    double dot,
  ) {
    final day = DateTime(month.year, month.month, d);
    if (day.isAfter(today)) return const SizedBox.shrink();
    final state = values[day] ?? HabitDay.missing;
    final isToday = day == today;
    final fill = switch (state) {
      HabitDay.yes => color,
      HabitDay.no => scheme.onSurfaceVariant.withValues(alpha: 0.28),
      HabitDay.missing => scheme.surfaceContainerHighest.withValues(alpha: 0.75),
    };
    return Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(dot / 2),
        border: isToday ? Border.all(color: color, width: 1.6) : null,
      ),
      child: isToday
          ? Center(
              child: Container(
                width: (dot - 6).clamp(2.0, double.infinity).toDouble(),
                height: (dot - 6).clamp(2.0, double.infinity).toDouble(),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            )
          : null,
    );
  }
}

/// Год числовой метрики календарём из квадратиков: строка — месяц, столбец —
/// день месяца, цвет квадрата — оттенок по значению дня (у оценок — красный
/// до 50 и зелёный от 50), дни без данных бледные, сегодня — квадратик в
/// рамке. Тот же вид, что у `HabitYearGrid`, только квадратики по значению.
/// При наведении мышью показывается число дня; тап по дню вызывает
/// [onTapDay] (например, чтобы открыть заметку этого дня).
class ValueYearGrid extends StatelessWidget {
  const ValueYearGrid({
    super.key,
    required this.end,
    required this.values,
    required this.valueColor,
    this.months = 12,
    this.locale = 'ru',
    this.onTapDay,
  });

  /// Последний день (обычно сегодня).
  final DateTime end;

  /// Значение метрики на конкретный день (ключ — дата без времени).
  final Map<DateTime, num> values;

  /// Цвет по значению дня.
  final Color Function(num value) valueColor;

  /// Сколько месяцев показать (12 — год).
  final int months;

  /// Язык подписей месяцев: 'ru' или 'en'.
  final String locale;

  /// Тап по прошедшему дню (включая дни без данных) — например, открыть
  /// заметку дня. Без него сетка только отображается.
  final void Function(DateTime day)? onTapDay;

  static const _monthsRu = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  static const _monthsEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = trackerBaseAccent(context);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontSize: 10,
    );
    final today = DateTime(end.year, end.month, end.day);
    final firstMonth = DateTime(end.year, end.month - (months - 1), 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        const labelW = 54.0;
        const gap = 8.0;
        const cols = 31;
        final avail = constraints.maxWidth - labelW - gap;
        final cell = (avail / cols).clamp(6.0, 18.0).toDouble();
        final dot = (cell - 3).clamp(3.0, 14.0).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (dot >= 8) _dayHeader(labelW, gap, cell, labelStyle),
            for (var i = 0; i < months; i++)
              _monthRow(
                scheme,
                accent,
                labelStyle,
                DateTime(firstMonth.year, firstMonth.month + i, 1),
                today,
                labelW,
                gap,
                cell,
                dot,
              ),
          ],
        );
      },
    );
  }

  Widget _dayHeader(
    double labelW,
    double gap,
    double cell,
    TextStyle? style,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(width: labelW),
          SizedBox(width: gap),
          for (var d = 1; d <= 31; d++)
            SizedBox(
              width: cell,
              child: Center(
                child: Text(
                  '$d',
                  textAlign: TextAlign.center,
                  style: style?.copyWith(fontSize: cell >= 12 ? 9 : 8),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _monthRow(
    ColorScheme scheme,
    Color accent,
    TextStyle? style,
    DateTime month,
    DateTime today,
    double labelW,
    double gap,
    double cell,
    double dot,
  ) {
    final names = locale == 'ru' ? _monthsRu : _monthsEn;
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final year = (month.year % 100).toString().padLeft(2, '0');
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelW,
            child: Text('${names[month.month - 1]} $year', style: style),
          ),
          SizedBox(width: gap),
          for (var d = 1; d <= 31; d++)
            SizedBox(
              width: cell,
              height: cell,
              child: d <= lastDay
                  ? _valueCell(scheme, accent, month, d, today, dot, cell)
                  : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _valueCell(
    ColorScheme scheme,
    Color accent,
    DateTime month,
    int d,
    DateTime today,
    double dot,
    double cell,
  ) {
    final day = DateTime(month.year, month.month, d);
    if (day.isAfter(today)) return const SizedBox.shrink();
    final value = values[day];
    final isToday = day == today;
    final fill = value != null
        ? valueColor(value)
        : scheme.surfaceContainerHighest.withValues(alpha: 0.75);
    final square = Container(
      width: dot,
      height: dot,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(2.5),
        border: isToday ? Border.all(color: accent, width: 1.6) : null,
      ),
      child: isToday
          ? Center(
              child: Container(
                width: (dot - 6).clamp(2.0, double.infinity).toDouble(),
                height: (dot - 6).clamp(2.0, double.infinity).toDouble(),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1.2),
                ),
              ),
            )
          : null,
    );

    Widget hit = SizedBox(
      width: cell,
      height: cell,
      child: Center(child: square),
    );
    final tap = onTapDay;
    if (tap != null) {
      hit = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => tap(day),
        child: hit,
      );
    }
    if (value != null) {
      hit = Tooltip(message: '$value', child: hit);
    }
    return hit;
  }
}

/// Линейный график метрики: линия с заливкой, сетка и подписи минимума/максимума.
/// В компактном режиме — только линия (для карточки-превью). Если задан
/// [valueColor], линия, точки и заливка красятся по значению (у оценок —
/// красный до 50 и зелёный от 50), как квадратики в `ValueYearGrid`.
class MetricChart extends StatelessWidget {
  const MetricChart({
    super.key,
    required this.series,
    this.compact = false,
    this.labels = false,
    this.accent,
    this.valueColor,
  });

  /// Отсортированные по дате значения `(дата, число)`.
  final List<(DateTime, Object?)> series;

  /// Только линия без подписей и сетки.
  final bool compact;

  /// Подписи минимума/середины/максимума слева.
  final bool labels;

  /// Цвет линии и заливки. По умолчанию — основной цвет темы.
  final Color? accent;

  /// Цвет по значению: если задан, линия, точки и заливка красятся по нему,
  /// а [accent] не используется.
  final Color Function(num value)? valueColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final data = [
      for (final s in series)
        if (s.$2 is num) (s.$1, (s.$2 as num).toDouble()),
    ];
    final color = accent ?? trackerBaseAccent(context);
    return CustomPaint(
      painter: _MetricPainter(
        data: data,
        compact: compact,
        labels: labels,
        lineColor: color,
        fillColor: color.withValues(alpha: 0.22),
        gridColor: scheme.outlineVariant.withValues(alpha: 0.5),
        valueColor: valueColor,
        labelStyle: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant) ??
            const TextStyle(fontSize: 11),
      ),
    );
  }
}

class _MetricPainter extends CustomPainter {
  _MetricPainter({
    required this.data,
    required this.compact,
    required this.labels,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.labelStyle,
    this.valueColor,
  });

  final List<(DateTime, num)> data;
  final bool compact;
  final bool labels;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final TextStyle labelStyle;

  /// Цвет по значению (если задан — красит линию, точки и заливку).
  final Color Function(num value)? valueColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty || size.width <= 0 || size.height <= 0) return;

    final gutter = labels ? 34.0 : 4.0;
    final plot = Rect.fromLTWH(
      gutter,
      4,
      size.width - gutter - 4,
      size.height - 8,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    var minY = data.map((d) => d.$2).reduce(math.min).toDouble();
    var maxY = data.map((d) => d.$2).reduce(math.max).toDouble();
    if (maxY - minY < 1e-9) {
      final pad = minY.abs() < 1e-9 ? 1.0 : minY * 0.2;
      minY -= pad;
      maxY += pad;
    }
    final span = maxY - minY;

    double xAt(int i) => plot.left +
        (data.length == 1 ? plot.width / 2 : plot.width * i / (data.length - 1));
    double yAt(num v) =>
        plot.top + plot.height * (1 - (v.toDouble() - minY) / span);

    final points = <Offset>[for (var i = 0; i < data.length; i++) Offset(xAt(i), yAt(data[i].$2))];

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      if (i == 0) {
        path.moveTo(points[i].dx, points[i].dy);
      } else {
        path.lineTo(points[i].dx, points[i].dy);
      }
    }

    final vc = valueColor;

    if (!compact) {
      final fillPath = Path.from(path)
        ..lineTo(
          data.length == 1 ? plot.left + plot.width / 2 : plot.right,
          plot.bottom,
        )
        ..lineTo(plot.left, plot.bottom)
        ..close();
      final fillPaint = Paint()..color = fillColor;
      if (vc != null) {
        fillPaint.shader = _axisGradient(plot, minY, maxY, vc, alpha: 0.22);
      }
      canvas.drawPath(fillPath, fillPaint);

      // Сетка.
      final gridPaint = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      for (final t in const [0.0, 0.5, 1.0]) {
        final y = plot.top + plot.height * t;
        canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      }

      if (labels) {
        String fmt(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(1);
        for (final t in const [0.0, 0.5, 1.0]) {
          final y = plot.top + plot.height * t;
          final value = maxY - span * t;
          final painter = TextPainter(
            text: TextSpan(text: fmt(value), style: labelStyle),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.right,
          )..layout();
          painter.paint(
            canvas,
            Offset(0, y - painter.height / 2),
          );
        }
      }
    }

    final strokeWidth = compact ? 2.0 : 2.4;
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (vc != null) {
      // Линия по сегментам: каждый красится градиентом по значениям концов.
      for (var i = 0; i < points.length - 1; i++) {
        linePaint.shader = ui.Gradient.linear(
          points[i],
          points[i + 1],
          [vc(data[i].$2), vc(data[i + 1].$2)],
        );
        canvas.drawLine(points[i], points[i + 1], linePaint);
      }
    } else {
      linePaint.color = lineColor;
      canvas.drawPath(path, linePaint);
    }

    Color pointColor(num value) => vc?.call(value) ?? lineColor;

    // Точки (последняя — крупнее).
    for (var i = 0; i < points.length; i++) {
      canvas.drawCircle(
        points[i],
        compact ? 1.6 : 2.4,
        Paint()..color = pointColor(data[i].$2),
      );
    }
    if (points.isNotEmpty) {
      final last = points.last;
      final lastColor = pointColor(data.last.$2);
      canvas.drawCircle(
        last,
        compact ? 3.0 : 4.0,
        Paint()..color = lastColor,
      );
      canvas.drawCircle(
        last,
        compact ? 4.0 : 5.5,
        Paint()..color = lastColor.withValues(alpha: 0.25),
      );
    }
  }

  /// Вертикальный градиент по оси значений: снизу — цвет минимума, сверху —
  /// цвет максимума (с учётом порога 50 у оценок), для заливки под линией.
  Shader _axisGradient(
    Rect rect,
    double minY,
    double maxY,
    Color Function(num) vc, {
    required double alpha,
  }) {
    const steps = 24;
    final colors = <Color>[];
    final stops = <double>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps; // 0 — верх (maxY), 1 — низ (minY)
      final v = maxY - (maxY - minY) * t;
      colors.add(vc(v).withValues(alpha: alpha));
      stops.add(t);
    }
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: colors,
      stops: stops,
    ).createShader(rect);
  }

  @override
  bool shouldRepaint(covariant _MetricPainter old) =>
      old.data != data ||
      old.compact != compact ||
      old.labels != labels ||
      old.lineColor != lineColor ||
      (old.valueColor == null) != (valueColor == null);
}
