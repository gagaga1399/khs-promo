import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/tracker_entry.dart';
import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'glass_bottom_bar.dart';
import 'tracker_accent.dart';
import 'tracker_charts.dart';

/// Привычки из канваса — список для «Привычки по месяцам» (узел 02).
const List<String> _kHabitsAll = [
  'сон с 22:30',
  'зарядка',
  'творог',
  'подготовка',
  'тренировка',
  'чтение',
  'Английский',
];

/// Привычки для блока предупреждений о пропусках (узел 10).
const List<String> _kWarnHabits = [
  'чтение',
  'тренировка',
  'творог',
  'зарядка',
  'сон с 22:30',
];

/// Привычки для тепловых карт (узел 14).
const List<String> _kHeatmapHabits = [
  'Английский',
  'чтение',
  'подготовка',
  'зарядка',
  'тренировка',
  'сон с 22:30',
  'творог',
];

/// Ивент «Неделя смерти» (узел 13).
const String _kEventName = 'Неделя смерти';
const List<String> _kEventHabits = ['спорт', 'сон', 'бег', 'зарядка', 'душ'];

/// Градации самоощущения/продуктивности (0–100): эмодзи и подпись.
class _MoodRange {
  final int min;
  final int max;
  final String label;
  final String emoji;

  const _MoodRange(this.min, this.max, this.label, this.emoji);
}

const List<_MoodRange> _kMoodRanges = [
  _MoodRange(0, 20, 'Тяжело', '😫'),
  _MoodRange(20, 40, 'Не очень', '😞'),
  _MoodRange(40, 60, 'Нормально', '😐'),
  _MoodRange(60, 80, 'Хорошо', '😄'),
  _MoodRange(80, 101, 'Прекрасно', '✨'),
];

_MoodRange _moodFor(num value) {
  final v = value.clamp(0, 100).round();
  for (final r in _kMoodRanges) {
    if (v >= r.min && v < r.max) return r;
  }
  return _kMoodRanges.last;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

String _ruMonthYear(int year, int month) {
  final name = DateFormat('LLLL', 'ru').format(DateTime(year, month));
  return '${name[0].toUpperCase()}${name.substring(1)} $year';
}

String _fmtDay(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

String _fmtNum(num v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

/// Русское склонение слова «день».
String _pluralDays(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return 'день';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'дня';
  return 'дней';
}

/// Полноэкранный дашборд-обзор, повторяющий виджеты канваса «трекеры».
/// С `embedded: true` отдаётся без своей шапки — так он живёт вкладкой в
/// нижней панели приложения трекеров.
class TrackerDashboardScreen extends StatefulWidget {
  const TrackerDashboardScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<TrackerDashboardScreen> createState() => _TrackerDashboardScreenState();
}

class _TrackerDashboardScreenState extends State<TrackerDashboardScreen> {
  Future<List<_EventNote>>? _eventFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeRefresh();
      _loadEvent();
    });
  }

  void _maybeRefresh() {
    if (!mounted) return;
    final tracker = context.read<TrackerService>();
    if (tracker.updatedAt == null && !tracker.scanning) {
      tracker.refresh();
    }
  }

  void _loadEvent() {
    if (!mounted) return;
    final vault = context.read<AppState>().obsidian.vaultPath.trim();
    setState(() {
      _eventFuture = _readEventNotes(vault);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    final tracker = context.watch<TrackerService>();
    final entries = tracker.entries;

    final body = !tracker.configured
        ? _Empty(
            icon: Icons.folder_off_outlined,
            title: strings.t('trackerNoVault'),
            body: strings.t('trackerNoVaultHelp'),
          )
        : entries.isEmpty
        ? (tracker.scanning
              ? const Center(child: CircularProgressIndicator())
              : _Empty(
                  icon: Icons.search_off_outlined,
                  title: strings.t('trackerEmpty'),
                  body: strings.t('trackerEmptyHelp'),
                ))
        : RefreshIndicator(
            onRefresh: () async {
              await tracker.refresh();
              _loadEvent();
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                widget.embedded
                    ? 40 + kGlassNavHeight + kGlassNavMarginBottom
                    : 40,
              ),
              children: [
                _MetricChartCard(
                  entries: entries,
                  property: 'продуктивность',
                  title: strings.t('trackerProductivityChart'),
                  axisLabel: strings.t('trackerMoodAxis'),
                  strings: strings,
                ),
                const SizedBox(height: 14),
                _MetricChartCard(
                  entries: entries,
                  property: 'самоощущение',
                  title: strings.t('trackerMoodChart'),
                  axisLabel: strings.t('trackerMoodAxis'),
                  strings: strings,
                ),
                const SizedBox(height: 14),
                _MiniCardsRow(entries: entries, strings: strings),
                const SizedBox(height: 14),
                _MissWarnings(entries: entries, strings: strings),
                const SizedBox(height: 14),
                _TaskStats(entries: entries, strings: strings),
                const SizedBox(height: 14),
                _HabitsByMonth(entries: entries, strings: strings),
                const SizedBox(height: 14),
                _HabitHeatmaps(entries: entries, strings: strings),
                const SizedBox(height: 14),
                _EventCard(future: _eventFuture, strings: strings),
                const SizedBox(height: 14),
                _ActivityTable(entries: entries, strings: strings),
              ],
            ),
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.t('trackerDashboardTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: strings.t('trackerRefresh'),
            onPressed: tracker.scanning
                ? null
                : () {
                    tracker.refresh();
                    _loadEvent();
                  },
            icon: tracker.scanning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: body,
    );
  }
}

// ─────────────────────────── Общие каркасы ───────────────────────────

class _DashCard extends StatelessWidget {
  const _DashCard({required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Pills extends StatelessWidget {
  const _Pills({required this.days, required this.on});

  final List<DateTime> days;
  final Set<DateTime> on;

  @override
  Widget build(BuildContext context) {
    final accent = trackerBaseAccent(context);
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < days.length; i++)
          Builder(
            builder: (_) {
              final d = days[i];
              final ok = on.contains(_day(d));
              final isToday = i == days.length - 1;
              return Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ok
                      ? const Color(0xFF2B8A3E)
                      : const Color(0xFFE03131).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                  border: isToday
                      ? Border.all(color: accent, width: 2)
                      : null,
                ),
                child: Text(
                  ok ? '✓' : '✗',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

List<DateTime> _lastNDays(int n) {
  final today = _day(DateTime.now());
  return [for (var i = n - 1; i >= 0; i--) today.subtract(Duration(days: i))];
}

// ─────────────── 01. Деятельность и исполнительность ───────────────

class _ActivityTable extends StatelessWidget {
  const _ActivityTable({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = _day(DateTime.now());
    final from = today.subtract(const Duration(days: 29));
    final recent = entries
        .where((e) => !_day(e.date).isBefore(from))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (recent.isEmpty) {
      return _DashCard(
        title: strings.t('trackerActivityTitle'),
        child: Text(strings.t('trackerNoData'),
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    var moodSum = 0.0;
    var moodCount = 0;
    var wishCount = 0;
    var tasksTotal = 0;
    var wordsTotal = 0;
    for (final e in recent) {
      final mood = e.properties['самоощущение'];
      if (mood is num) {
        moodSum += mood.clamp(0, 100);
        moodCount++;
      }
      if (TrackerService.isDone(e.properties['желание действовать'])) {
        wishCount++;
      }
      tasksTotal += TrackerService.completedTasksIn(e.body);
      wordsTotal += TrackerService.wordsIn(e.body);
    }
    final avg = moodCount == 0 ? null : (moodSum / moodCount).round();
    final avgWords = recent.isEmpty ? 0 : (wordsTotal / recent.length).round();

    Widget cell(String text, {Color? color, FontWeight? weight}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: weight, fontSize: 13),
      ),
    );

    final headerStyle = TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 12,
      color: scheme.onSurfaceVariant,
    );

    return _DashCard(
      title: strings.t('trackerActivityTitle'),
      subtitle: strings.t('trackerActivitySubtitle'),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 34,
          dataRowMinHeight: 34,
          dataRowMaxHeight: 40,
          columnSpacing: 4,
          horizontalMargin: 4,
          headingTextStyle: headerStyle,
          columns: [
            DataColumn(label: Text(strings.t('trackerColDay'))),
            DataColumn(label: Text(strings.t('trackerColMood'))),
            DataColumn(label: Text(strings.t('trackerColWish'))),
            DataColumn(label: Text(strings.t('trackerColTasks'))),
            DataColumn(label: Text(strings.t('trackerColWords'))),
          ],
          rows: [
            DataRow(
              color: WidgetStatePropertyAll(
                trackerBaseAccent(context).withValues(alpha: 0.35),
              ),
              cells: [
                DataCell(cell(strings.t('trackerRowSummary'),
                    weight: FontWeight.w800)),
                DataCell(
                  cell(
                    avg == null ? '—' : '${_moodFor(avg).emoji} $avg',
                    color: avg == null ? null : metricScoreColor(avg),
                    weight: FontWeight.w700,
                  ),
                ),
                DataCell(cell('$wishCount', weight: FontWeight.w700)),
                DataCell(
                  cell('$tasksTotal',
                      color: const Color(0xFF3B82F6),
                      weight: FontWeight.w700),
                ),
                DataCell(cell('$wordsTotal ($avgWords)')),
              ],
            ),
            for (final e in recent)
              DataRow(
                cells: [
                  DataCell(cell(_fmtDay(e.date))),
                  DataCell(_moodCell(e.properties['самоощущение'])),
                  DataCell(
                    cell(
                      TrackerService.isDone(e.properties['желание действовать'])
                          ? '✔️'
                          : '❌',
                    ),
                  ),
                  DataCell(
                    cell(
                      '${TrackerService.completedTasksIn(e.body)}',
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  DataCell(cell('${TrackerService.wordsIn(e.body)}')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _moodCell(Object? value) {
    if (value is! num) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: const Text('—', style: TextStyle(fontSize: 13)),
      );
    }
    final v = value.clamp(0, 100).round();
    final r = _moodFor(v);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        '${r.emoji} $v',
        textAlign: TextAlign.center,
        style: TextStyle(color: metricScoreColor(v), fontSize: 13),
      ),
    );
  }
}

// ─────────────── 07/08. Графики метрики по месяцам ───────────────

class _MetricChartCard extends StatefulWidget {
  const _MetricChartCard({
    required this.entries,
    required this.property,
    required this.title,
    required this.axisLabel,
    required this.strings,
  });

  final List<TrackerEntry> entries;
  final String property;
  final String title;
  final String axisLabel;
  final AppStrings strings;

  @override
  State<_MetricChartCard> createState() => _MetricChartCardState();
}

class _MetricChartCardState extends State<_MetricChartCard> {
  String? _selected;

  List<DateTime> _months() {
    final set = <DateTime>{};
    for (final e in widget.entries) {
      final v = e.properties[widget.property];
      if (v is num) set.add(DateTime(e.date.year, e.date.month));
    }
    return set.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = widget.strings;
    final months = _months();
    if (months.isEmpty) {
      return _DashCard(
        title: widget.title,
        child: Text(
          '${widget.property}: ${strings.t('trackerNoData')}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }

    if (isScoreMetric(widget.property)) {
      return _buildScoreHeatmap(context, scheme, strings);
    }

    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    final selection = _selected ??
        (months.contains(current)
            ? '${current.year}-${current.month}'
            : 'all');

    final items = <(DateTime, Object?)>[];
    for (final e in widget.entries) {
      final v = e.properties[widget.property];
      if (v is! num) continue;
      if (selection != 'all') {
        final parts = selection.split('-');
        if (e.date.year != int.parse(parts[0]) ||
            e.date.month != int.parse(parts[1])) {
          continue;
        }
      }
      items.add((e.date, e.properties[widget.property]));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));

    final values = [for (final i in items) (i.$2 as num).clamp(0, 100)];
    final avg = values.isEmpty
        ? null
        : (values.reduce((a, b) => a + b) / values.length).round();
    final minV = values.isEmpty ? null : values.reduce(math.min);
    final maxV = values.isEmpty ? null : values.reduce(math.max);
    final mood = avg == null ? null : _moodFor(avg);

    return _DashCard(
      title: widget.title,
      subtitle: widget.axisLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: selection,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: Text(strings.t('trackerRangeAll')),
              ),
              for (final m in months.reversed)
                DropdownMenuItem(
                  value: '${m.year}-${m.month}',
                  child: Text(_ruMonthYear(m.year, m.month)),
                ),
            ],
            onChanged: (v) => setState(() => _selected = v),
          ),
          const SizedBox(height: 12),
          if (mood != null)
            Row(
              children: [
                Text(mood.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Text(
                  '${mood.label} · ${strings.t('trackerAvg')} $avg',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: metricScoreColor(avg!),
                  ),
                ),
                const Spacer(),
                if (minV != null && maxV != null)
                  Text(
                    '$minV → $maxV',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: values.isEmpty
                ? Center(
                    child: Text(
                      strings.t('trackerNoData'),
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : MetricChart(
                    series: items,
                    labels: true,
                    accent: trackerBaseAccent(context),
                  ),
          ),
        ],
      ),
    );
  }

  /// Для метрик-оценок вместо линии — тепловая карта по дням: цвет квадрата
  /// отражает значение дня (красные оттенки до 50, зелёные от 50).
  Widget _buildScoreHeatmap(
    BuildContext context,
    ColorScheme scheme,
    AppStrings strings,
  ) {
    const weeks = 26;
    final today = _day(DateTime.now());
    final from = today.subtract(const Duration(days: weeks * 7));
    final values = <DateTime, num>{};
    final nums = <num>[];
    for (final e in widget.entries) {
      final v = e.properties[widget.property];
      if (v is! num) continue;
      final d = _day(e.date);
      if (d.isBefore(from) || d.isAfter(today)) continue;
      values[d] = v.clamp(0, 100);
      nums.add(v.clamp(0, 100));
    }
    final avg = nums.isEmpty
        ? null
        : (nums.reduce((a, b) => a + b) / nums.length).round();
    final minV = nums.isEmpty ? null : nums.reduce(math.min);
    final maxV = nums.isEmpty ? null : nums.reduce(math.max);
    final mood = avg == null ? null : _moodFor(avg);

    return _DashCard(
      title: widget.title,
      subtitle: widget.axisLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (mood != null)
            Row(
              children: [
                Text(mood.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Text(
                  '${mood.label} · ${strings.t('trackerAvg')} $avg',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: metricScoreColor(avg!),
                  ),
                ),
                const Spacer(),
                if (minV != null && maxV != null)
                  Text(
                    '$minV → $maxV',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ValueYearGrid(
              end: today,
              values: values,
              valueColor: metricScoreColor,
              locale: context.watch<AppState>().locale,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── 09/11/12. Мини-карточки ───────────────

class _MiniCardsRow extends StatelessWidget {
  const _MiniCardsRow({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 620;
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _NoteStreakCard(entries: entries, strings: strings),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MarathonCard(entries: entries, strings: strings),
              ),
              const SizedBox(width: 12),
              Expanded(child: _LifeRingCard(strings: strings)),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NoteStreakCard(entries: entries, strings: strings),
            const SizedBox(height: 12),
            _MarathonCard(entries: entries, strings: strings),
            const SizedBox(height: 12),
            _LifeRingCard(strings: strings),
          ],
        );
      },
    );
  }
}

class _NoteStreakCard extends StatelessWidget {
  const _NoteStreakCard({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Пустые авто-заметки из шаблона (файл есть, но ничего не заполнено) в
    // серию не идут — иначе пропущенные дни не помечаются.
    final days = <DateTime>{
      for (final e in entries)
        if (TrackerService.noteWritten(e)) _day(e.date),
    };
    final today = _day(DateTime.now());
    final haveToday = days.contains(today);
    var cursor = haveToday ? today : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (days.contains(cursor) && streak < 3650) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final last = days.isEmpty ? null : (days.toList()..sort()).last;

    return _DashCard(
      title: strings.t('trackerNoteStreak'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$streak',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2B8A3E),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _pluralDays(streak),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            haveToday
                ? strings.t('trackerIncludingToday')
                : strings.t('trackerExcludingToday'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (last != null)
            Text(
              '${strings.t('trackerLast')}: ${_fmtDay(last)}.${last.year % 100}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          const SizedBox(height: 10),
          _Pills(days: _lastNDays(30), on: days),
        ],
      ),
    );
  }
}

class _MarathonCard extends StatelessWidget {
  const _MarathonCard({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.watch<AppState>();
    final today = _day(DateTime.now());
    final start = _day(state.marathonStart);
    final goal = state.marathonGoal;
    // Марафон — календарные дни от старта до сегодня включительно. Число не
    // ограничено целью: она лишь показывает прогресс и может быть любой (0 —
    // без цели, тогда шкала не рисуется).
    final total = today.difference(start).inDays + 1;
    final remain = goal <= 0 ? 0 : math.max(0, goal - total);
    final pct = goal <= 0 ? 0.0 : (total / goal).clamp(0.0, 1.0);

    return _DashCard(
      title: strings.t('trackerMarathon'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF2B8A3E),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _pluralDays(total),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            goal > 0
                ? '${strings.t('trackerMarathonStart')} ${_fmtDay(start)} · '
                      '${strings.t('trackerMarathonTarget')} $goal'
                : '${strings.t('trackerMarathonStart')} ${_fmtDay(start)}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if (goal > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 10,
                backgroundColor: scheme.surface,
                color: const Color(0xFF2B8A3E),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              remain > 0
                  ? '${strings.t('trackerMarathonLeft')}: $remain ${_pluralDays(remain)}'
                  : strings.t('trackerMarathonDone'),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '${strings.t('trackerMarathonNotes')}: ${entries.length}',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _LifeRingCard extends StatelessWidget {
  const _LifeRingCard({required this.strings});

  final AppStrings strings;

  // Запасной день рождения, если пользователь не задал его в настройках.
  static final DateTime _fallbackBirth = DateTime(2010, 3, 19);
  static const int _lifespanYears = 70;

  @override
  Widget build(BuildContext context) {
    final birth = context.watch<AppState>().birthday ?? _fallbackBirth;
    final lifespanDays = (_lifespanYears * 365.25).round();
    final now = _day(DateTime.now());
    final lived = now.difference(birth).inDays;
    final left = math.max(0, lifespanDays - lived);
    final pct = (lived / lifespanDays).clamp(0.0, 1.0);

    return _DashCard(
      title: strings.t('trackerLifeTitle'),
      child: Center(
        child: SizedBox(
          width: 190,
          height: 190,
          child: CustomPaint(
            painter: _LifeRingPainter(
              pct: pct,
              track: Theme.of(context).colorScheme.surface,
              color: const Color(0xFFFF5252),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$left',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    strings.t('trackerLifeDaysLeft'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LifeRingPainter extends CustomPainter {
  _LifeRingPainter({
    required this.pct,
    required this.track,
    required this.color,
  });

  final double pct;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = 16.0;
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) / 2 - stroke / 2;
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * pct,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _LifeRingPainter old) =>
      old.pct != pct || old.color != color || old.track != track;
}

// ─────────────── 10. Привычки с предупреждениями ───────────────

class _MissWarnings extends StatelessWidget {
  const _MissWarnings({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 720
            ? 4
            : constraints.maxWidth > 520
            ? 3
            : constraints.maxWidth > 340
            ? 2
            : 1;
        return _DashCard(
          title: strings.t('trackerMissTitle'),
          subtitle: strings.t('trackerMissSubtitle'),
          child: GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.62,
            children: [
              for (final h in _kWarnHabits)
                _MissCard(habit: h, entries: entries, strings: strings),
            ],
          ),
        );
      },
    );
  }
}

class _MissCard extends StatelessWidget {
  const _MissCard({
    required this.habit,
    required this.entries,
    required this.strings,
  });

  final String habit;
  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = <DateTime>{};
    for (final e in entries) {
      if (TrackerService.isDone(e.properties[habit])) done.add(_day(e.date));
    }
    final today = _day(DateTime.now());
    var miss = 0;
    for (var d = today; miss < 400; d = d.subtract(const Duration(days: 1))) {
      if (done.contains(d)) break;
      miss++;
    }
    final longAgo = miss >= 400;
    final warn = miss >= 3;
    final color = warn ? const Color(0xFFE8590C) : const Color(0xFF2B8A3E);
    final last = done.isEmpty ? null : (done.toList()..sort()).last;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(
            habit,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(warn ? '⚠️' : '✅', style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            longAgo ? '400+' : (warn ? '$miss ${strings.t('trackerDaysShort')}' : '—'),
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          Text(
            last == null ? '—' : _fmtDay(last),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _Pills(days: _lastNDays(14), on: done),
        ],
      ),
    );
  }
}

// ─────────────── 11/12 already above ───────────────

// ─────────────── 04. Статистика задач ───────────────

class _TaskStats extends StatelessWidget {
  const _TaskStats({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final counts = <DateTime, int>{};
    for (final e in entries) {
      counts[_day(e.date)] = TrackerService.completedTasksIn(e.body);
    }
    final today = _day(DateTime.now());
    final year = today.year;
    final yearStart = DateTime(year, 1, 1);
    var total = 0;
    var daysWith = 0;
    for (final entry in counts.entries) {
      if (entry.key.isBefore(yearStart)) continue;
      total += entry.value;
      if (entry.value > 0) daysWith++;
    }
    final todayCount = counts[today] ?? 0;
    final avg = daysWith == 0 ? 0.0 : total / daysWith;

    // Тепловая карта: день с выполненными задачами = активен.
    final values = <DateTime, HabitDay>{};
    for (final e in entries) {
      final d = _day(e.date);
      values[d] = (counts[d] ?? 0) > 0 ? HabitDay.yes : HabitDay.no;
    }

    return _DashCard(
      title: strings.t('trackerTaskStatsTitle'),
      subtitle: strings.t('trackerTaskStatsSubtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatTile(
                value: '$todayCount',
                label: strings.t('trackerTasksToday'),
                color: const Color(0xFF3B82F6),
              ),
              _StatTile(
                value: '$total',
                label: '${strings.t('trackerTasksTotalShort')} $year',
              ),
              _StatTile(
                value: '$daysWith',
                label: strings.t('trackerTasksDaysWith'),
              ),
              _StatTile(
                value: _fmtNum(avg),
                label: strings.t('trackerTasksAvg'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            strings.t('trackerTasksHeatmap'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 96,
            child: HabitHeatmap(
              end: today,
              weeks: 26,
              values: values,
              accent: trackerBaseAccent(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────── 02. Привычки по месяцам ───────────────

class _HabitsByMonth extends StatelessWidget {
  const _HabitsByMonth({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<TrackerEntry>>{};
    for (final e in entries) {
      final key =
          '${e.date.year}-${e.date.month.toString().padLeft(2, '0')}';
      groups.putIfAbsent(key, () => []).add(e);
    }
    final months = groups.keys.toList()..sort();

    return _DashCard(
      title: strings.t('trackerHabitsByMonthTitle'),
      subtitle: strings.t('trackerHabitsByMonthSubtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final ym in months.reversed) ...[
            _MonthBlock(
              key: ValueKey(ym),
              year: int.parse(ym.split('-')[0]),
              month: int.parse(ym.split('-')[1]),
              monthEntries: groups[ym]!,
              strings: strings,
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _MonthBlock extends StatelessWidget {
  const _MonthBlock({
    super.key,
    required this.year,
    required this.month,
    required this.monthEntries,
    required this.strings,
  });

  final int year;
  final int month;
  final List<TrackerEntry> monthEntries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = _daysInMonth(year, month);
    final rows = <(String, int)>[];
    for (final h in _kHabitsAll) {
      var done = 0;
      for (final e in monthEntries) {
        if (TrackerService.isDone(e.properties[h])) done++;
      }
      rows.add((h, done));
    }
    rows.sort((a, b) => b.$2.compareTo(a.$2));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _ruMonthYear(year, month),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        for (final row in rows) ...[
          Row(
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  row.$1,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                '${row.$2}/$days',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: 8),
              Expanded(child: _PercentBar(done: row.$2, total: days)),
              const SizedBox(width: 8),
              SizedBox(
                width: 42,
                child: Text(
                  '${(row.$2 / days * 100).round()}%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _PercentBar extends StatelessWidget {
  const _PercentBar({required this.done, required this.total});

  final int done;
  final int total;

  Color get _color {
    final pct = total == 0 ? 0 : done / total * 100;
    if (pct < 25) return const Color(0xFFEF4444);
    if (pct < 50) return const Color(0xFFF97316);
    if (pct < 75) return const Color(0xFFFFC107);
    return const Color(0xFF2B8A3E);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: pct,
        minHeight: 8,
        backgroundColor: scheme.surface,
        color: _color,
      ),
    );
  }
}

// ─────────────── 14. Тепловые карты привычек ───────────────

class _HabitHeatmaps extends StatelessWidget {
  const _HabitHeatmaps({required this.entries, required this.strings});

  final List<TrackerEntry> entries;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final today = _day(DateTime.now());
    return _DashCard(
      title: strings.t('trackerHeatmapsTitle'),
      subtitle: strings.t('trackerHeatmapsSubtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final h in _kHeatmapHabits) ...[
            _HabitHeatmapRow(habit: h, entries: entries, today: today),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _HabitHeatmapRow extends StatelessWidget {
  const _HabitHeatmapRow({
    required this.habit,
    required this.entries,
    required this.today,
  });

  final String habit;
  final List<TrackerEntry> entries;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    const weeks = 26;
    final from = today.subtract(const Duration(days: weeks * 7));
    final values = <DateTime, HabitDay>{};
    for (final e in entries) {
      final d = _day(e.date);
      if (d.isBefore(from) || d.isAfter(today)) continue;
      values[d] = TrackerService.isDone(e.properties[habit])
          ? HabitDay.yes
          : HabitDay.no;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          habit,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 84,
          child: HabitHeatmap(
            end: today,
            weeks: weeks,
            values: values,
            accent: trackerAccent(habit),
          ),
        ),
      ],
    );
  }
}

// ─────────────── 13. Ивент «Неделя смерти» ───────────────

class _EventNote {
  final String name;
  final Map<String, Object?> properties;

  const _EventNote(this.name, this.properties);
}

Future<List<_EventNote>> _readEventNotes(String vault) async {
  if (vault.isEmpty) return const [];
  final dir = Directory(p.join(vault, 'ивенты', _kEventName));
  if (!await dir.exists()) return const [];
  final notes = <_EventNote>[];
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.md')) continue;
      final name = p.basenameWithoutExtension(entity.path);
      if (!name.contains(_kEventName)) continue;
      try {
        final content = await entity.readAsString();
        final parsed = TrackerService.parseFrontmatter(content);
        notes.add(_EventNote(name, parsed.properties));
      } catch (_) {}
    }
  } catch (_) {}
  notes.sort((a, b) => a.name.compareTo(b.name));
  return notes;
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.future, required this.strings});

  final Future<List<_EventNote>>? future;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = future;
    if (pending == null) {
      return _DashCard(
        title: _kEventName,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return FutureBuilder<List<_EventNote>>(
      future: pending,
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const <_EventNote>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _DashCard(
            title: _kEventName,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (notes.isEmpty) {
          return _DashCard(
            title: _kEventName,
            child: Text(
              strings.t('trackerEventEmpty'),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          );
        }

        var scoreSum = 0;
        var daysDone = 0;
        var checksTotal = 0;
        final byDay = <DateTime, int>{};
        for (final n in notes) {
          var checked = 0;
          for (final h in _kEventHabits) {
            if (TrackerService.isDone(n.properties[h])) checked++;
          }
          scoreSum += checked;
          checksTotal += checked;
          if (checked > 0) daysDone++;
          final d = TrackerService.dateFromFileName(n.name);
          if (d != null) byDay[d] = checked;
        }
        const barTarget = 35; // 7 дней × 5 флажков
        final pct = (scoreSum / barTarget * 100).clamp(0, 100).round();

        return _DashCard(
          title: _kEventName,
          subtitle: strings.t('trackerEventSubtitle'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatTile(
                    value: '$daysDone',
                    label: strings.t('trackerEventDays'),
                    color: const Color(0xFF2B8A3E),
                  ),
                  _StatTile(
                    value: '$checksTotal',
                    label: strings.t('trackerEventChecks'),
                  ),
                  _StatTile(
                    value: '$scoreSum',
                    label: strings.t('trackerEventScore'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    strings.t('trackerEventProgress'),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    '$scoreSum / $barTarget · $pct%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: pct / 100,
                  minHeight: 10,
                  backgroundColor: scheme.surface,
                  color: const Color(0xFF4263EB),
                ),
              ),
              const SizedBox(height: 14),
              _EventBars(byDay: byDay),
            ],
          ),
        );
      },
    );
  }
}

class _EventBars extends StatelessWidget {
  const _EventBars({required this.byDay});

  final Map<DateTime, int> byDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = byDay.keys.toList()..sort();
    if (days.isEmpty) return const SizedBox.shrink();
    const maxH = 70.0;
    return SizedBox(
      height: maxH + 26,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final d in days)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 18,
                      height: math.max(
                        4,
                        maxH * byDay[d]! / _kEventHabits.length,
                      ),
                      decoration: BoxDecoration(
                        color: byDay[d]! >= _kEventHabits.length
                            ? const Color(0xFF2B8A3E)
                            : const Color(0xFF4263EB),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 4),
                    RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        _fmtDay(d),
                        style: TextStyle(
                          fontSize: 9,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
