import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/tracker_entry.dart';
import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'notes_editor_screen.dart';
import 'tracker_accent.dart';
import 'tracker_charts.dart';

/// Полный вид трекера по одному свойству: привычка — календарь из точек за год;
/// метрика — график с выбором периода, средним и разбросом.
class TrackerDetailScreen extends StatefulWidget {
  const TrackerDetailScreen({super.key, required this.property});

  final TrackerProperty property;

  @override
  State<TrackerDetailScreen> createState() => _TrackerDetailScreenState();
}

class _TrackerDetailScreenState extends State<TrackerDetailScreen> {
  String _range = 'year'; // 'week' | 'month' | 'year' | 'all'

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final tracker = context.watch<TrackerService>();
    final scheme = Theme.of(context).colorScheme;
    final prop = widget.property;
    final accent = trackerAccent(prop.name);
    final series = tracker.seriesFor(prop.name);

    final isHabit = prop.kind == TrackerPropertyKind.boolean;
    final scoreMetric = !isHabit && isScoreMetric(prop.name);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(
                prop.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isHabit
                    ? strings.t('trackerHabitBadge')
                    : strings.t('trackerMetricBadge'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
      ),
      body: series.isEmpty
          ? Center(
              child: Text(
                strings.t('trackerNoData'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                if (isHabit)
                  _habitStats(context, tracker, prop, series, strings)
                else
                  _metricControls(context, strings, accent),
                const SizedBox(height: 14),
                Card(
                  elevation: 0,
                  color: scheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: isHabit
                        ? _habitChart(context, tracker, prop, accent)
                        : _metricChart(context, tracker, prop, series, accent),
                  ),
                ),
                // Для метрик-оценок график вынесен в отдельную карточку,
                // чтобы линия не сливалась с квадратиками годовой сетки.
                if (scoreMetric) ...[
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _scoreChart(context, prop, series, accent),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _scoreLegend(context, strings),
                ],
                const SizedBox(height: 14),
                if (isHabit)
                  _legend(context, strings, accent)
                else
                  _metricStats(context, tracker, prop, series, strings),
                const SizedBox(height: 20),
                _recentValues(context, tracker, prop, strings),
              ],
            ),
    );
  }

  Widget _habitStats(
    BuildContext context,
    TrackerService tracker,
    TrackerProperty prop,
    List<(DateTime, Object?)> series,
    AppStrings strings,
  ) {
    final streak = TrackerService.habitStreak(series);
    final best = TrackerService.bestStreak(series);
    final span = _span(series);
    return Row(
      children: [
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerStreakNow'),
            value: '$streak',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerStreakBest'),
            value: '$best',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerDoneYear'),
            value: '${_doneLast(series, 365)}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerDaysTotal'),
            value: '$span',
          ),
        ),
      ],
    );
  }

  Widget _metricControls(BuildContext context, AppStrings strings, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final onAccent = ThemeData.estimateBrightnessForColor(accent) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;
    Widget button(String range, String label) {
      final selected = _range == range;
      return Expanded(
        child: Material(
          color: selected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _range = range),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? onAccent : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            button('week', strings.t('trackerRangeWeek')),
            const SizedBox(width: 4),
            button('month', strings.t('trackerRangeMonth')),
            const SizedBox(width: 4),
            button('year', strings.t('trackerRangeYear')),
            const SizedBox(width: 4),
            button('all', strings.t('trackerRangeAll')),
          ],
        ),
      ),
    );
  }

  Widget _habitChart(
    BuildContext context,
    TrackerService tracker,
    TrackerProperty prop,
    Color accent,
  ) {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final values = <DateTime, HabitDay>{};
    for (final s in tracker.seriesFor(prop.name)) {
      final d = DateTime(s.$1.year, s.$1.month, s.$1.day);
      values[d] = s.$2 == true ? HabitDay.yes : HabitDay.no;
    }
    final locale = context.watch<AppState>().locale;

    return HabitYearGrid(
      end: end,
      values: values,
      accent: accent,
      locale: locale,
    );
  }

  Widget _metricChart(
    BuildContext context,
    TrackerService tracker,
    TrackerProperty prop,
    List<(DateTime, Object?)> fullSeries,
    Color accent,
  ) {
    final strings = context.watch<AppState>().strings;
    final data = _slice(fullSeries);
    if (data.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            strings.t('trackerNoData'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    if (isScoreMetric(prop.name)) {
      final values = <DateTime, num>{};
      for (final s in data) {
        if (s.$2 is! num) continue;
        final d = DateTime(s.$1.year, s.$1.month, s.$1.day);
        values[d] = (s.$2 as num).clamp(0, 100);
      }
      final today = DateTime.now();
      final end = DateTime(today.year, today.month, today.day);
      final locale = context.watch<AppState>().locale;
      return ValueYearGrid(
        end: end,
        values: values,
        valueColor: metricScoreColor,
        locale: locale,
        onTapDay: _openDayNote,
      );
    }
    return SizedBox(
      height: 180,
      child: MetricChart(series: data, labels: true, accent: accent),
    );
  }

  /// Линейный график метрики-оценки — отдельной карточкой под сеткой
  /// квадратиков (значения красятся по шкале 0–100).
  Widget _scoreChart(
    BuildContext context,
    TrackerProperty prop,
    List<(DateTime, Object?)> fullSeries,
    Color accent,
  ) {
    final strings = context.watch<AppState>().strings;
    final data = _slice(fullSeries);
    if (data.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            strings.t('trackerNoData'),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 180,
      width: double.infinity,
      child: MetricChart(
        series: data,
        labels: true,
        accent: accent,
        valueColor: metricScoreColor,
      ),
    );
  }

  /// Легенда тонов: полоса-градиент от 0 к 100 с подписями — что означает
  /// каждый оттенок квадратика (красный ниже 50, зелёный от 50).
  Widget _scoreLegend(BuildContext context, AppStrings strings) {
    final scheme = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.t('trackerScoreLegend'),
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('0', style: labelStyle),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: scheme.outlineVariant),
                  gradient: LinearGradient(
                    colors: [
                      metricScoreColor(0),
                      metricScoreColor(25),
                      metricScoreColor(50),
                      metricScoreColor(75),
                      metricScoreColor(100),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('100', style: labelStyle),
          ],
        ),
      ],
    );
  }

  /// Открыть заметку дня: сначала ищем локальную заметку, иначе тянем текст
  /// из хранилища Obsidian (тот же приём, что и в календаре).
  Future<void> _openDayNote(DateTime day) async {
    final state = context.read<AppState>();
    final existing = state.notesForDate(day);
    if (existing.isNotEmpty) {
      if (!mounted) return;
      await Navigator.push(
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
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotesEditorScreen(date: day, initialContent: prefill),
      ),
    );
  }

  Widget _metricStats(
    BuildContext context,
    TrackerService tracker,
    TrackerProperty prop,
    List<(DateTime, Object?)> fullSeries,
    AppStrings strings,
  ) {
    final data = _slice(fullSeries);
    final nums = [
      for (final s in data)
        if (s.$2 is num) (s.$2 as num).toDouble(),
    ];
    if (nums.isEmpty) {
      return SizedBox.shrink();
    }
    var sum = 0.0;
    var min = nums.first;
    var max = nums.first;
    for (final n in nums) {
      sum += n;
      if (n < min) min = n;
      if (n > max) max = n;
    }
    final avg = sum / nums.length;
    final last = nums.last;
    String fmt(num v) => (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(1);
    final score = isScoreMetric(prop.name);

    return Row(
      children: [
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerLast'),
            value: fmt(last),
            color: score ? metricScoreColor(last) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerAvg'),
            value: fmt(avg),
            color: score ? metricScoreColor(avg) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerMin'),
            value: fmt(min),
            color: score ? metricScoreColor(min) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            context,
            label: strings.t('trackerMax'),
            value: fmt(max),
            color: score ? metricScoreColor(max) : null,
          ),
        ),
      ],
    );
  }

  Widget _recentValues(
    BuildContext context,
    TrackerService tracker,
    TrackerProperty prop,
    AppStrings strings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final data = tracker.seriesFor(prop.name);
    if (data.isEmpty) return const SizedBox.shrink();
    final recent = data.reversed.take(12).toList();
    final score = isScoreMetric(prop.name);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.t('trackerRecentTitle'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        ...recent.map(
          (s) => Card(
            elevation: 0,
            color: scheme.surfaceContainerHighest,
            margin: const EdgeInsets.only(bottom: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Text(
                    _fmt(s.$1),
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    TrackerService.displayValue(s.$2),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: (score && s.$2 is num)
                          ? metricScoreColor(s.$2 as num)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _legend(BuildContext context, AppStrings strings, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    Widget swatch(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
    return Row(
      children: [
        swatch(accent),
        const SizedBox(width: 6),
        Text(
          strings.t('trackerLegendYes'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 16),
        swatch(scheme.onSurfaceVariant.withValues(alpha: 0.35)),
        const SizedBox(width: 6),
        Text(
          strings.t('trackerLegendNo'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 16),
        swatch(scheme.surfaceContainerHighest.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(
          strings.t('trackerLegendNone'),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String label,
    required String value,
    Color? color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// Отрезок серии по выбранному периоду.
  List<(DateTime, Object?)> _slice(List<(DateTime, Object?)> full) {
    if (_range == 'all') return full;
    final days = switch (_range) {
      'week' => 6,
      'year' => 364,
      _ => 29,
    };
    final today = DateTime.now();
    final from = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: days));
    return [
      for (final s in full)
        if (!s.$1.isBefore(from)) s,
    ];
  }

  static int _doneLast(List<(DateTime, Object?)> series, int days) {
    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: days - 1));
    var count = 0;
    for (final s in series) {
      if (s.$1.isBefore(from)) continue;
      if (s.$2 == true) count++;
    }
    return count;
  }

  static int _span(List<(DateTime, Object?)> series) {
    if (series.isEmpty) return 0;
    return series.last.$1.difference(series.first.$1).inDays + 1;
  }

  static String _fmt(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day.$month.${d.year}';
  }
}