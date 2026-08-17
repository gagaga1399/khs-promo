import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../ui/widgets/stats_charts.dart';

/// Экран статистики: дневная цель, столбики по приоритетам, графики.
class StatisticsScreen extends StatelessWidget {
  /// [embedded] — внутри вкладки (шапку и кнопку «назад» не показываем).
  final bool embedded;

  const StatisticsScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final bars = state.progressBars;
    final scheme = Theme.of(context).colorScheme;

    final sections = <Widget>[];
    if (bars.contains(AppState.barGoal)) {
      sections.add(_GoalCard(state: state, strings: strings));
    }
    if (bars.contains(AppState.barOverdue) && state.overdueCount(null) > 0) {
      sections.add(
        _Card(
          title: strings.t('overdue'),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error),
              const SizedBox(width: 8),
              Text(
                '${strings.t('overdue')}: ${state.overdueCount(null)}',
                style: TextStyle(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (bars.contains(AppState.barPriorities)) {
      sections.add(_PriorityBarsCard(state: state, strings: strings));
    }
    if (bars.contains(AppState.barWeek)) {
      sections.add(
        _Card(
          title: strings.t('barWeek'),
          subtitle: strings.t('lastWeek'),
          child: DailyLineChart(
            values: state.doneCountsLast(7),
            labels: _dayLabels(7, strings.locale),
            color: Colors.teal,
          ),
        ),
      );
    }
    if (bars.contains(AppState.barMonth)) {
      sections.add(
        _Card(
          title: strings.t('barMonth'),
          subtitle: strings.t('lastMonth'),
          child: DailyLineChart(
            values: state.doneCountsLast(30),
            labels: _monthLabels(30, strings.locale),
            color: AppTheme.accentBlue,
          ),
        ),
      );
    }
    if (bars.contains(AppState.barMonthCompare)) {
      final now = DateTime.now();
      final thisMonth = state.doneCountsMonth(now.year, now.month);
      final lastMonth = DateTime(now.month == 1 ? now.year - 1 : now.year, now.month == 1 ? 12 : now.month - 1);
      final prevData = state.doneCountsMonth(lastMonth.year, lastMonth.month);
      final thisTotal = state.doneCountMonth(now.year, now.month);
      final prevTotal = state.doneCountMonth(lastMonth.year, lastMonth.month);
      sections.add(
        _Card(
          title: strings.t('barMonthCompare'),
          child: _MonthCompareChart(
            thisMonth: thisMonth,
            lastMonth: prevData,
            thisTotal: thisTotal,
            prevTotal: prevTotal,
            thisLabel: strings.t('thisMonth'),
            prevLabel: strings.t('prevMonth'),
            locale: strings.locale,
          ),
        ),
      );
    }

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(
                strings.t('progressBarsSubtitle'),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          for (final s in sections) ...[s, const SizedBox(height: 12)],
      ],
    );

    if (embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('statistics'))),
      body: body,
    );
  }

  /// Подписи дней для графика за неделю (день недели, сокращённо).
  List<String> _dayLabels(int days, String locale) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fmt = DateFormat('E', locale);
    return List.generate(days, (i) {
      final day = today.subtract(Duration(days: days - 1 - i));
      return fmt.format(day);
    });
  }

  /// Подписи дней для графика за месяц (каждые 5 дней).
  List<String> _monthLabels(int days, String locale) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fmt = DateFormat('d.M', locale);
    return List.generate(days, (i) {
      final day = today.subtract(Duration(days: days - 1 - i));
      return day.day % 5 == 0 ? fmt.format(day) : '';
    });
  }
}

class _GoalCard extends StatelessWidget {
  final AppState state;
  final AppStrings strings;

  const _GoalCard({required this.state, required this.strings});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = state.dailyGoalPercent;
    return _Card(
      title: strings.t('dailyGoal'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${state.doneToday} / ${state.dailyGoal}',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Icon(Icons.local_fire_department, color: Colors.orange),
              Text(
                '${strings.t('streak')}: ${state.streakDays}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 10,
              color: Colors.deepPurple,
              backgroundColor: scheme.surfaceContainerHigh,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$percent%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PriorityBarsCard extends StatelessWidget {
  final AppState state;
  final AppStrings strings;

  const _PriorityBarsCard({required this.state, required this.strings});

  @override
  Widget build(BuildContext context) {
    int totalOf(int priority) =>
        state.tasks.where((t) => t.priority == priority).length;
    int doneOf(int priority) => state
        .tasks
        .where((t) => t.priority == priority && t.completed)
        .length;

    return _Card(
      title: strings.t('barPriorities'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PriorityBarChart(
            items: [
              (
                color: Colors.redAccent,
                label: strings.t('high'),
                done: doneOf(2),
                remaining: totalOf(2) - doneOf(2),
              ),
              (
                color: Colors.amber,
                label: strings.t('normal'),
                done: doneOf(1),
                remaining: totalOf(1) - doneOf(1),
              ),
              (
                color: Colors.grey,
                label: strings.t('low'),
                done: doneOf(0),
                remaining: totalOf(0) - doneOf(0),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _LegendDot(
                color: Theme.of(context).colorScheme.primary,
                label: strings.t('doneCount'),
              ),
              const SizedBox(width: 12),
              _LegendDot(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                label: strings.t('remaining'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _MonthCompareChart extends StatelessWidget {
  final List<int> thisMonth;
  final List<int> lastMonth;
  final int thisTotal;
  final int prevTotal;
  final String thisLabel;
  final String prevLabel;
  final String locale;

  const _MonthCompareChart({
    required this.thisMonth,
    required this.lastMonth,
    required this.thisTotal,
    required this.prevTotal,
    required this.thisLabel,
    required this.prevLabel,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxDays = thisMonth.length > lastMonth.length
        ? thisMonth.length
        : lastMonth.length;
    final labels = List.generate(maxDays, (i) {
      final d = i + 1;
      return d % 5 == 0 ? '$d' : '';
    });
    final maxVal = [
      ...thisMonth,
      ...lastMonth,
    ].fold<int>(1, (m, v) => v > m ? v : m);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: AppTheme.accentBlue, label: '$thisLabel ($thisTotal)'),
            const SizedBox(width: 12),
            _LegendDot(
              color: scheme.outlineVariant,
              label: '$prevLabel ($prevTotal)',
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ComparePainter(
              thisMonth: thisMonth,
              lastMonth: lastMonth,
              labels: labels,
              maxVal: maxVal,
              thisColor: AppTheme.accentBlue,
              prevColor: scheme.outlineVariant,
              textColor: scheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          thisTotal >= prevTotal
              ? '+${thisTotal - prevTotal} vs $prevLabel'
              : '${thisTotal - prevTotal} vs $prevLabel',
          style: TextStyle(
            color: thisTotal >= prevTotal ? Colors.green : scheme.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ComparePainter extends CustomPainter {
  final List<int> thisMonth;
  final List<int> lastMonth;
  final List<String> labels;
  final int maxVal;
  final Color thisColor;
  final Color prevColor;
  final Color textColor;

  _ComparePainter({
    required this.thisMonth,
    required this.lastMonth,
    required this.labels,
    required this.maxVal,
    required this.thisColor,
    required this.prevColor,
    required this.textColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padLeft = 24.0;
    const padBottom = 18.0;
    const padTop = 8.0;
    final chartWidth = size.width - padLeft - 4;
    final chartHeight = size.height - padTop - padBottom;
    final count = labels.length;
    if (count < 2) return;
    final stepX = chartWidth / (count - 1);

    Offset point(int i, List<int> data) {
      final val = i < data.length ? data[i] : 0;
      return Offset(
        padLeft + stepX * i,
        padTop + chartHeight * (1 - val / maxVal.clamp(1, 1 << 30)),
      );
    }

    // Grid
    final gridPaint = Paint()
      ..color = prevColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    final labelStyle = TextStyle(color: textColor, fontSize: 9);
    for (final f in [0.0, 0.5, 1.0]) {
      final y = padTop + chartHeight * (1 - f);
      canvas.drawLine(Offset(padLeft, y), Offset(size.width - 4, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(maxVal * f).round()}',
          style: labelStyle,
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // Previous month line (dashed effect via dots)
    for (var i = 0; i < count; i++) {
      if (i > 0) {
        canvas.drawLine(point(i - 1, lastMonth), point(i, lastMonth), Paint()
          ..color = prevColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round);
      }
      canvas.drawCircle(point(i, lastMonth), 2, Paint()..color = prevColor);
    }

    // This month area + line
    final areaPath = Path()
      ..moveTo(point(0, thisMonth).dx, padTop + chartHeight)
      ..lineTo(point(0, thisMonth).dx, point(0, thisMonth).dy);
    for (var i = 1; i < count; i++) {
      areaPath.lineTo(point(i, thisMonth).dx, point(i, thisMonth).dy);
    }
    areaPath
      ..lineTo(point(count - 1, thisMonth).dx, padTop + chartHeight)
      ..close();
    canvas.drawPath(areaPath, Paint()..color = thisColor.withValues(alpha: 0.12));

    final linePath = Path()..moveTo(point(0, thisMonth).dx, point(0, thisMonth).dy);
    for (var i = 1; i < count; i++) {
      linePath.lineTo(point(i, thisMonth).dx, point(i, thisMonth).dy);
    }
    canvas.drawPath(linePath, Paint()
      ..color = thisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round);

    // Dots + day labels
    final dotPaint = Paint()..color = thisColor;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(point(i, thisMonth), 3, dotPaint);
      if (labels[i].isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: labels[i], style: labelStyle),
          textDirection: ui.TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(point(i, thisMonth).dx - tp.width / 2, size.height - 14));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ComparePainter old) =>
      old.thisMonth != thisMonth || old.lastMonth != lastMonth;
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _Card({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
