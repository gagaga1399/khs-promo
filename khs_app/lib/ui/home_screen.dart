import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../ui/widgets/dashboard_right.dart';
import '../ui/widgets/dashboard_sidebar.dart';
import '../ui/widgets/event_card.dart';
import 'calendar_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';
import 'statistics_screen.dart';
import 'task_edit_screen.dart';
import 'widgets/quick_add_bar.dart';
import 'widgets/task_tile.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 980;

    if (!wide) return const MobileShell();

    final design = state.isDesignMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.t('appTitle')),
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: CircleAvatar(
            radius: 18,
            backgroundImage: AssetImage('assets/avatar.png'),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: strings.t('calendar'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CalendarScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: strings.t('settings'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          const DashboardSidebar(),
          const VerticalDivider(width: 1),
          Expanded(child: design ? const NotesPanel() : const _CenterPanel()),
          if (!design) ...[
            const VerticalDivider(width: 1),
            const DashboardRightPanel(),
          ],
        ],
      ),
    );
  }
}

/// Кастомная физика для PageView:.requires超过 длинного свайпа для смены вкладки.
class _DampenedScrollPhysics extends ScrollPhysics {
  const _DampenedScrollPhysics({super.parent});

  @override
  _DampenedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _DampenedScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // Только если свайп быстрый — переключаем страницу
    if (velocity.abs() > 400) {
      return super.createBallisticSimulation(position, velocity);
    }
    // Медленный свайп — возвращаем на место
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      position.pixels,
      0,
    );
  }

  @override
  bool get allowImplicitScrolling => false;
}

/// Нижняя навигация телефона: Главная / Статистика / Календарь / Заметки / Настройки.
class MobileShell extends StatefulWidget {
  const MobileShell({super.key});

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell> {
  int _index = 0;
  late final PageController _pageController = PageController();

  void _goTo(int i) {
    setState(() => _index = i);
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final titles = <String>[
      strings.t('appTitle'),
      strings.t('statistics'),
      strings.t('calendar'),
      strings.t('notes'),
      strings.t('settings'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        leading: _index == 0
            ? const Padding(
                padding: EdgeInsets.only(left: 12),
                child: CircleAvatar(
                  radius: 18,
                  backgroundImage: AssetImage('assets/avatar.png'),
                ),
              )
            : null,
      ),
      body: PageView(
        controller: _pageController,
        physics: const _DampenedScrollPhysics(),
        onPageChanged: (i) => setState(() => _index = i),
        children: const [
          _NarrowDashboard(),
          StatisticsScreen(embedded: true),
          CalendarScreen(embedded: true),
          NotesPanel(showAddButton: true),
          SettingsScreen(embedded: true),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _goTo,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: strings.t('home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.insert_chart_outlined),
            selectedIcon: const Icon(Icons.insert_chart),
            label: strings.t('statistics'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: strings.t('calendar'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.book_outlined),
            selectedIcon: const Icon(Icons.book),
            label: strings.t('notes'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: strings.t('settings'),
          ),
        ],
      ),
    );
  }
}

/// Центральная панель (широкий экран).
class _CenterPanel extends StatelessWidget {
  const _CenterPanel();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final tasks = state.filteredTasks;
    final filter = state.categoryFilter;
    final now = DateTime.now();
    final isToday =
        state.selectedDate == DateTime(now.year, now.month, now.day);
    final dateFormat = DateFormat('d MMMM yyyy', strings.locale);
    final header = isToday
        ? strings.t('today')
        : dateFormat.format(state.selectedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  filter ?? header,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (filter != null)
                ActionChip(
                  label: Text(strings.t('allTasks')),
                  onPressed: () => state.setCategoryFilter(null),
                  avatar: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
        ),
        const _PriorityFilterRow(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              if (tasks.isNotEmpty)
                for (final task in tasks)
                  TaskTile(
                    task: task,
                    strings: strings,
                    onToggle: (v) => state.toggleCompleted(task),
                    onTap: () {
                      state.selectTask(task);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskEditScreen(task: task),
                        ),
                      );
                    },
                    onDelete: () => state.deleteTask(task),
                  ),
              const SizedBox(height: 12),
              const QuickAddBar(),
              const SizedBox(height: 16),
              _EventsSection(),
              const SizedBox(height: 12),
              Center(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TaskEditScreen(defaultDate: state.selectedDate),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(strings.t('addTaskShort')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EventsSection extends StatelessWidget {
  final double height;

  const _EventsSection({this.height = 150});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final events = state.upcomingEvents(3);
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            strings.t('events'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          height: height,
          child: events.isEmpty
              ? Center(
                  child: Text(
                    strings.t('emptyAll'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final t = events[i];
                    final color = t.category == null
                        ? AppTheme.accentBlue
                        : AppTheme.groupColor(t.category!);
                    final due = t.dueAt!;
                    final hh = due.hour.toString().padLeft(2, '0');
                    final mm = due.minute.toString().padLeft(2, '0');
                    final isToday =
                        due.year == todayOnly.year &&
                        due.month == todayOnly.month &&
                        due.day == todayOnly.day;
                    final subtitle = isToday
                        ? '$hh:$mm'
                        : '${DateFormat('EEE d MMM', strings.locale).format(due)} · $hh:$mm';
                    return EventCard(
                      title: t.title,
                      subtitle: subtitle,
                      color: color,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskEditScreen(task: t),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// Компактная версия дашборда для телефона.
class _NarrowDashboard extends StatefulWidget {
  const _NarrowDashboard();

  @override
  State<_NarrowDashboard> createState() => _NarrowDashboardState();
}

class _NarrowDashboardState extends State<_NarrowDashboard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final tasks = state.filteredTasks;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _scrollToBottom();

    return Column(
      children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              ChoiceChip(
                label: Text(strings.t('allTasks')),
                selected: state.categoryFilter == null,
                onSelected: (_) => state.setCategoryFilter(null),
              ),
              for (final group in state.groups) ...[
                const SizedBox(width: 8),
                ChoiceChip(
                  label: Text(group),
                  selected: state.categoryFilter == group,
                  avatar: Icon(
                    Icons.circle,
                    size: 10,
                    color: AppTheme.groupColor(group),
                  ),
                  onSelected: (_) => state.setCategoryFilter(group),
                ),
              ],
            ],
          ),
        ),
        const _PriorityFilterRow(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: _NarrowFilter(
                  icon: Icons.star,
                  label: strings.t('today'),
                  selected: state.selectedDate == today,
                  onTap: () => state.selectDate(today),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NarrowFilter(
                  icon: Icons.calendar_month,
                  label: strings.t('tomorrow'),
                  selected:
                      state.selectedDate == today.add(const Duration(days: 1)),
                  onTap: () =>
                      state.selectDate(today.add(const Duration(days: 1))),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _DayStrip(
          selected: state.selectedDate,
          strings: strings,
          onSelect: state.selectDate,
        ),
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              if (tasks.isNotEmpty)
                for (final task in tasks)
                  TaskTile(
                    task: task,
                    strings: strings,
                    onToggle: (v) => state.toggleCompleted(task),
                    onTap: () {
                      state.selectTask(task);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TaskEditScreen(task: task),
                        ),
                      );
                    },
                    onDelete: () => state.deleteTask(task),
                  ),
              const SizedBox(height: 12),
              const QuickAddBar(),
              const SizedBox(height: 8),
              const _EventsSection(height: 120),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      TaskEditScreen(defaultDate: state.selectedDate),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(strings.t('addTaskShort')),
            ),
          ),
        ),
      ],
    );
  }
}

class _NarrowFilter extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NarrowFilter({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.14)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriorityFilterRow extends StatelessWidget {
  const _PriorityFilterRow();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final p = state.priorityFilter;
    Widget chip(String label, int? value, {IconData? icon, Color? color}) {
      return ChoiceChip(
        label: Text(label),
        selected: p == value,
        visualDensity: VisualDensity.compact,
        avatar: icon == null
            ? null
            : Icon(icon, size: 12, color: p == value ? null : color),
        onSelected: (_) => state.setPriorityFilter(value),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          chip(strings.t('all'), null),
          const SizedBox(width: 8),
          chip(
            strings.t('priorityHigh'),
            2,
            icon: Icons.flag,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 8),
          chip(
            strings.t('priorityMedium'),
            1,
            icon: Icons.flag,
            color: Colors.amber,
          ),
          const SizedBox(width: 8),
          chip(
            strings.t('priorityLow'),
            0,
            icon: Icons.flag,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }
}

class _DayStrip extends StatelessWidget {
  final DateTime selected;
  final AppStrings strings;
  final ValueChanged<DateTime> onSelect;

  const _DayStrip({
    required this.selected,
    required this.strings,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = selected.subtract(Duration(days: selected.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: days.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          if (i == 0) {
            final isToday = selected == today;
            return _Chip(
              label: strings.t('today'),
              selected: isToday,
              onTap: () => onSelect(today),
            );
          }
          final day = days[i - 1];
          final dateFormat = DateFormat('d', strings.locale);
          final weekdayFormat = DateFormat('E', strings.locale);
          return _Chip(
            label: weekdayFormat.format(day),
            value: dateFormat.format(day),
            selected: selected == day,
            isToday: day == today,
            onTap: () => onSelect(day),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String? value;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    this.value,
    required this.selected,
    this.isToday = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !selected
              ? Border.all(color: scheme.primary)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
            ),
            if (value != null)
              Text(
                value!,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
