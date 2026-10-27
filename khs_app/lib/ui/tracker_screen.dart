import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/tracker_entry.dart';
import '../models/tracker_profile.dart';
import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'glass_bottom_bar.dart';
import 'tracker_accent.dart';
import 'tracker_charts.dart';
import 'tracker_dashboard_screen.dart';
import 'tracker_detail_screen.dart';
import 'tracker_lock_screen.dart';
import 'tracker_settings_screen.dart';
import 'vault_notes_panel.dart';
import 'widgets/add_tracker_dialog.dart';

/// Номер вкладки настроек: на ней нижняя панель уезжает вниз, а на её месте
/// появляется кнопка возврата — тот же приём, что и в KHS Tasks.
/// Настройки — крайний правый пункт панели.
const int _trackerSettingsIndex = 3;

/// Полноэкранное приложение трекеров: своя шапка и своя нижняя стеклянная
/// панель (как в KHS Tasks, только пункты здесь — разделы самих трекеров):
/// Трекеры / Дашборд / Настройки / Заметки.
class TrackerHomeScreen extends StatefulWidget {
  const TrackerHomeScreen({super.key});

  @override
  State<TrackerHomeScreen> createState() => _TrackerHomeScreenState();
}

class _TrackerHomeScreenState extends State<TrackerHomeScreen> {
  int _index = 0;
  int _prevIndex = 0;
  late final PageController _controller = PageController();

  void _goTo(int i) {
    setState(() {
      if (_index != i) _prevIndex = _index;
      _index = i;
    });
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  /// Возврат из настроек: на предыдущую вкладку, а если мы уже там — на первую.
  void _backFromSettings() =>
      _goTo(_prevIndex == _trackerSettingsIndex ? 0 : _prevIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    // Раздел закрыт, пока не введён ключ лицензии (например, при запуске с
    // ярлыка --tracker в обход хаба).
    if (!state.trackerUnlocked) return const TrackerLockScreen();
    final accent = state.trackerAccent;
    final titles = <String>[
      strings.t('hubTrackerTile'),
      strings.t('trackerDashboardTitle'),
      strings.t('notes'),
      strings.t('trackerSettingsTitle'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titles[_index],
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      extendBody: true,
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          TrackerScreen(),
          TrackerDashboardScreen(embedded: true),
          VaultNotesPanel(),
          TrackerSettingsScreen(),
        ],
      ),
      bottomNavigationBar: GlassBottomBar(
        currentIndex: _index,
        onTap: _goTo,
        accent: accent,
        hidden: _index == _trackerSettingsIndex,
        onBack: _backFromSettings,
        items: [
          GlassNavItem(
            icon: Icons.tune_outlined,
            activeIcon: Icons.tune,
            label: strings.t('hubTrackerTile'),
          ),
          GlassNavItem(
            icon: Icons.dashboard_outlined,
            activeIcon: Icons.dashboard,
            label: strings.t('trackerTabDashboard'),
          ),
          GlassNavItem(
            icon: Icons.book_outlined,
            activeIcon: Icons.book,
            label: strings.t('notes'),
          ),
          GlassNavItem(
            icon: Icons.settings_outlined,
            activeIcon: Icons.settings,
            label: strings.t('trackerSettingsTitle'),
          ),
        ],
      ),
    );
  }
}

/// Экран трекеров: движок читает датированные заметки из хранилища Obsidian,
/// а экран показывает по каждому подходящему свойству график привычки (да/нет)
/// или метрики (числа). Карточка открывает полный вид.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  String _lastVault = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefresh());
  }

  void _maybeRefresh() {
    if (!mounted) return;
    final tracker = context.read<TrackerService>();
    final vault = context.read<AppState>().obsidian.vaultPath;
    final stale = tracker.updatedAt == null && !tracker.scanning;
    if (vault != _lastVault || stale) {
      _lastVault = vault;
      tracker.refresh();
    }
  }

  /// Набор трекеров активного профиля: найденные в заметках (кроме скрытых)
  /// плюс добавленные вручную.
  List<TrackerProperty> _visibleTrackers(
    TrackerService tracker,
    TrackerProfile profile,
  ) {
    final discovered = <String>{};
    final out = <TrackerProperty>[];
    for (final prop in tracker.properties) {
      if (prop.kind != TrackerPropertyKind.boolean &&
          prop.kind != TrackerPropertyKind.number) {
        continue;
      }
      discovered.add(prop.name);
      if (profile.hidden.contains(prop.name)) continue;
      out.add(prop);
    }
    for (final custom in profile.custom) {
      if (discovered.contains(custom.name)) continue;
      if (profile.hidden.contains(custom.name)) continue;
      out.add(
        TrackerProperty(
          name: custom.name,
          kind: custom.kind,
          filled: 0,
          total: tracker.entries.length,
        ),
      );
    }
    return out;
  }

  Future<void> _addTracker() async {
    final state = context.read<AppState>();
    final tracker = context.read<TrackerService>();
    final strings = state.strings;
    final result = await showAddTrackerDialog(context, strings);
    if (result == null) return;
    final exists = tracker.properties.any(
      (p) =>
          p.name == result.name &&
          !state.activeTrackerProfile.hidden.contains(result.name) &&
          (p.kind == TrackerPropertyKind.boolean ||
              p.kind == TrackerPropertyKind.number),
    );
    final ok = exists
        ? false
        : await state.addCustomTracker(result.name, result.kind);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.t('trackerAddExists'))),
    );
  }

  Future<void> _removeTracker(String name) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    await state.removeTracker(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.t('trackerRemoved'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final tracker = context.watch<TrackerService>();
    final scheme = Theme.of(context).colorScheme;

    final profile = state.activeTrackerProfile;
    final trackers = _visibleTrackers(tracker, profile);

    return ColoredBox(
      color: scheme.surface,
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: tracker.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              20,
              16,
              20,
              32 + kGlassNavHeight + kGlassNavMarginBottom,
            ),
            children: [
              _header(context, tracker, strings),
              const SizedBox(height: 16),
              if (!tracker.configured)
                _info(
                  context,
                  icon: Icons.folder_off_outlined,
                  title: strings.t('trackerNoVault'),
                  body: strings.t('trackerNoVaultHelp'),
                )
              else if (tracker.scanning && tracker.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (tracker.error != null)
                _info(
                  context,
                  icon: Icons.error_outline,
                  title: strings.t('trackerError'),
                  body: tracker.error!,
                )
              else if (tracker.entries.isEmpty)
                _info(
                  context,
                  icon: Icons.search_off_outlined,
                  title: strings.t('trackerEmpty'),
                  body: strings.t('trackerEmptyHelp'),
                )
              else ...[
                _summary(context, tracker, strings),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _sectionTitle(
                        context,
                        strings.t('trackerSectionTitle'),
                        strings.t('trackerSectionHelp'),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addTracker,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(strings.t('trackerAdd')),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (trackers.isEmpty)
                  _notBuiltCard(context, strings)
                else
                  for (final prop in trackers) ...[
                    _TrackerCard(
                      prop: prop,
                      strings: strings,
                      onRemove: () => _removeTracker(prop.name),
                    ),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 10),
                _sectionTitle(
                  context,
                  strings.t('trackerRecentTitle'),
                  strings.t('trackerRecentSubtitle'),
                ),
                const SizedBox(height: 10),
                ..._recentNotes(context, tracker, strings),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    TrackerService tracker,
    AppStrings strings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.t('hubTrackerTile'),
                style: Theme.of(
                  context,
                ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                tracker.configured
                    ? strings.t('trackerSubtitle')
                    : strings.t('trackerConfigureHint'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: strings.t('trackerRefresh'),
          onPressed: tracker.scanning ? null : tracker.refresh,
          icon: tracker.scanning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }

  Widget _summary(
    BuildContext context,
    TrackerService tracker,
    AppStrings strings,
  ) {
    final entries = tracker.entries;
    final first = entries.first.date;
    final last = entries.last.date;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.event_note_outlined,
            value: '${entries.length}',
            label: strings.t('trackerFoundNotes'),
            accent: trackerAccent('заметок'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.tune,
            value: '${tracker.properties.length}',
            label: strings.t('trackerFoundProps'),
            accent: trackerAccent('свойств'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(
            icon: Icons.date_range_outlined,
            value: '${_fmt(first)} — ${_fmt(last)}',
            label: strings.t('trackerPeriod'),
            small: true,
            accent: trackerAccent('период'),
          ),
        ),
      ],
    );
  }

  List<Widget> _recentNotes(
    BuildContext context,
    TrackerService tracker,
    AppStrings strings,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final entries = tracker.entries.reversed.take(12).toList();
    return [
      for (var i = 0; i < entries.length; i++)
        Card(
          elevation: 0,
          color: scheme.surfaceContainerHighest,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 16,
                      color: trackerAccent('recent$i'),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _fmt(entries[i].date),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                if (entries[i].properties.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final prop in entries[i].properties.entries.take(8))
                        _chipForProp(context, prop),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
    ];
  }

  Widget _chipForProp(BuildContext context, MapEntry<String, Object?> prop) {
    final value = prop.value;
    final color = (isScoreMetric(prop.key) && value is num)
        ? metricScoreColor(value)
        : null;
    return _chip(
      context,
      '${prop.key}: ${TrackerService.displayValue(value)}',
      color: color,
    );
  }

  Widget _notBuiltCard(BuildContext context, AppStrings strings) {
    final scheme = Theme.of(context).colorScheme;
    final accent = trackerBaseAccent(context);
    return Card(
      elevation: 0,
      color: trackerBaseAccentSoft(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.show_chart_outlined, color: accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.t('trackerNone'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.t('trackerNoneHelp'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

  Widget _info(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
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
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String subtitle) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static Widget _chip(BuildContext context, String text, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color?.withValues(alpha: 0.55) ?? scheme.outlineVariant,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: color == null ? null : FontWeight.w700,
        ),
      ),
    );
  }

  /// Дата в коротком виде `дд.мм.гггг` — без зависимости от локали intl.
  static String _fmt(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day.$month.${d.year}';
  }
}

/// Карточка трекера одного свойства: превью тепловой карты или графика плюс
/// пара ключевых цифр. Тап открывает полный вид.
class _TrackerCard extends StatelessWidget {
  const _TrackerCard({
    required this.prop,
    required this.strings,
    this.onRemove,
  });

  final TrackerProperty prop;
  final AppStrings strings;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracker = context.watch<TrackerService>();
    final series = tracker.seriesFor(prop.name);
    final isHabit = prop.kind == TrackerPropertyKind.boolean;
    final accent = trackerAccent(prop.name);

    return Card(
      elevation: 0,
      color: Color.alphaBlend(
        accent.withValues(alpha: isHabit ? 0.10 : 0.07),
        scheme.surfaceContainerHighest,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: accent.withValues(alpha: isHabit ? 0.5 : 0.35),
        ),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TrackerDetailScreen(property: prop),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _avatar(context, accent, isHabit),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      prop.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  _badge(
                    context,
                    accent,
                    isHabit ? strings.t('trackerHabitBadge') : strings.t('trackerMetricBadge'),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_outward,
                    size: 18,
                    color: accent,
                  ),
                  if (onRemove != null)
                    IconButton(
                      tooltip: strings.t('trackerRemove'),
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      color: scheme.onSurfaceVariant,
                      icon: const Icon(Icons.close),
                      onPressed: onRemove,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: isHabit ? 92 : 64,
                width: double.infinity,
                child: isHabit
                    ? _habitPreview(context, tracker, accent)
                    : _metricPreview(context, tracker, accent),
              ),
              const SizedBox(height: 10),
              Text(
                isHabit
                    ? _habitStatsLine(series)
                    : _metricStatsLine(series),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, Color accent, bool isHabit) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isHabit ? Icons.check : Icons.show_chart,
        size: 20,
        color: scheme.brightness == Brightness.dark ? accent : accent,
      ),
    );
  }

  Widget _habitPreview(
    BuildContext context,
    TrackerService tracker,
    Color accent,
  ) {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    const days = 30;
    final first = end.subtract(Duration(days: days - 1));
    final values = <DateTime, HabitDay>{};
    for (final s in tracker.seriesFor(prop.name)) {
      final d = DateTime(s.$1.year, s.$1.month, s.$1.day);
      if (d.isBefore(first)) continue;
      values[d] = s.$2 == true ? HabitDay.yes : HabitDay.no;
    }
    return HabitStrip(
      end: end,
      days: days,
      values: values,
      accent: accent,
      legend: [
        strings.t('trackerDotLegendDone'),
        strings.t('trackerDotLegendNo'),
        strings.t('trackerDotLegendMissing'),
        strings.t('trackerDotLegendToday'),
      ],
    );
  }

  Widget _metricPreview(
    BuildContext context,
    TrackerService tracker,
    Color accent,
  ) {
    final today = DateTime.now();
    final from = DateTime(today.year, today.month, today.day)
        .subtract(const Duration(days: 29));
    if (isScoreMetric(prop.name)) {
      final end = DateTime(today.year, today.month, today.day);
      const weeks = 14;
      final first = end.subtract(const Duration(days: weeks * 7));
      final values = <DateTime, num>{};
      for (final s in tracker.seriesFor(prop.name)) {
        if (s.$2 is! num) continue;
        final d = DateTime(s.$1.year, s.$1.month, s.$1.day);
        if (d.isBefore(first) || d.isAfter(end)) continue;
        values[d] = (s.$2 as num).clamp(0, 100);
      }
      return ValueYearGrid(
        end: end,
        months: 3,
        values: values,
        valueColor: metricScoreColor,
      );
    }
    final data = [
      for (final s in tracker.seriesFor(prop.name))
        if (s.$2 is num && !s.$1.isBefore(from)) s,
    ];
    return MetricChart(
      series: data,
      compact: true,
      labels: false,
      accent: accent,
    );
  }

  String _habitStatsLine(List<(DateTime, Object?)> series) {
    final streak = TrackerService.habitStreak(series);
    int done30(List<(DateTime, Object?)> s) {
      final today = DateTime.now();
      final from = DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 29));
      var count = 0;
      for (final v in s) {
        if (!v.$1.isBefore(from) && v.$2 == true) count++;
      }
      return count;
    }

    return '${strings.t('trackerStreak')}: $streak   ·   '
        '${strings.t('trackerDone30')}: ${done30(series)}   ·   '
        '${strings.t('trackerFilledTotal')}: ${prop.filled}';
  }

  String _metricStatsLine(List<(DateTime, Object?)> series) {
    final nums = [
      for (final s in series)
        if (s.$2 is num) (s.$2 as num).toDouble(),
    ];
    if (nums.isEmpty) {
      return '${strings.t('trackerFilledTotal')}: ${prop.filled}';
    }
    var sum = 0.0;
    for (final n in nums) {
      sum += n;
    }
    String fmt(num v) =>
        (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(1);
    return '${strings.t('trackerLast')}: ${fmt(nums.last)}   ·   '
        '${strings.t('trackerAvg')}: ${fmt(sum / nums.length)}   ·   '
        '${strings.t('trackerFilledTotal')}: ${nums.length}';
  }

  Widget _badge(BuildContext context, Color accent, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: accent.withValues(alpha: scheme.brightness == Brightness.dark ? 0.45 : 0.3),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, color: accent),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
    this.small = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color? accent;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: accent ?? trackerBaseAccent(context)),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: small ? 13 : 22,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
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