import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../app_theme.dart';
import '../statistics_screen.dart';
import '../task_edit_screen.dart';

Future<void> showCreateGroupDialog(BuildContext context, AppState state) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(state.strings.t('createGroup')),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: state.strings.t('groupName')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(state.strings.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(state.strings.t('create')),
        ),
      ],
    ),
  );
  if (name != null && name.isNotEmpty) await state.createGroup(name);
}

Future<void> showGroupActions(
  BuildContext context,
  AppState state,
  String group,
) async {
  final controller = TextEditingController(text: group);
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(group),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: state.strings.t('groupName')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'delete'),
          child: Text(
            state.strings.t('delete'),
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(state.strings.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(state.strings.t('rename')),
        ),
      ],
    ),
  );
  if (action == null) return;
  if (action == 'delete') {
    await state.deleteGroup(group);
  } else if (action.isNotEmpty && action != group) {
    await state.renameGroup(group, action);
  }
}

class DashboardSidebar extends StatelessWidget {
  const DashboardSidebar({super.key});

  void _selectToday(AppState state) {
    final now = DateTime.now();
    state.selectDate(DateTime(now.year, now.month, now.day));
  }

  void _selectTomorrow(AppState state) {
    final now = DateTime.now();
    state.selectDate(
      DateTime(now.year, now.month, now.day).add(const Duration(days: 1)),
    );
  }

  /// Диалог с запланированными напоминаниями о задачах.
  Future<void> _showReminders(BuildContext context, AppState state) async {
    final strings = state.strings;
    final now = DateTime.now();
    final upcoming =
        state.tasks
            .where(
              (t) =>
                  !t.completed &&
                  t.notify &&
                  t.reminderAt != null &&
                  t.reminderAt!.isAfter(now),
            )
            .toList()
          ..sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('upcomingReminders')),
        content: SizedBox(
          width: double.maxFinite,
          child: upcoming.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(strings.t('noReminders')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: upcoming.length,
                  itemBuilder: (context, i) {
                    final t = upcoming[i];
                    final format = DateFormat('d MMMM, HH:mm', strings.locale);
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.alarm),
                      title: Text(t.title),
                      subtitle: Text(format.format(t.reminderAt!)),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskEditScreen(task: t),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.t('ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    return Container(
      width: 260,
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 18,
                  backgroundImage: AssetImage('assets/avatar.png'),
                ),
                const SizedBox(width: 10),
                Text(
                  strings.t('appTitle'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              strings.t('groups').toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _GroupTile(
                  label: strings.t('allTasks'),
                  color: AppTheme.accentBlue,
                  count: state.tasks.length,
                  selected: state.categoryFilter == null,
                  onTap: () => state.setCategoryFilter(null),
                  progress:
                      state.barEnabled(AppState.barSidebar)
                      ? state.progressPercent(null) / 100
                      : null,
                ),
                for (final group in state.groups)
                  _GroupTile(
                    label: group,
                    color: AppTheme.groupColor(group),
                    count: state.countFor(group),
                    selected: state.categoryFilter == group,
                    onTap: () => state.setCategoryFilter(group),
                    onEdit: () => showGroupActions(context, state, group),
                    progress:
                        state.barEnabled(AppState.barSidebar)
                        ? state.progressPercent(group) / 100
                        : null,
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => showCreateGroupDialog(context, state),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(
                      strings.t('createGroup').toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _FilterTile(
                  icon: Icons.star,
                  label: strings.t('today'),
                  selected: state.selectedDate == todayOnly,
                  onTap: () => _selectToday(state),
                ),
                _FilterTile(
                  icon: Icons.calendar_month,
                  label: strings.t('tomorrow'),
                  selected:
                      state.selectedDate ==
                      todayOnly.add(const Duration(days: 1)),
                  onTap: () => _selectTomorrow(state),
                ),
                _FilterTile(
                  icon: Icons.insert_chart_outlined,
                  label: strings.t('statistics'),
                  selected: false,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StatisticsScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _IconButton(
                      icon: Icons.notifications_none,
                      tooltip: strings.t('reminders'),
                      onTap: () => _showReminders(context, state),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'design',
                      label: Text(strings.t('design')),
                    ),
                    ButtonSegment(
                      value: 'home',
                      label: Text(strings.t('home')),
                    ),
                  ],
                  selected: {state.isDesignMode ? 'design' : 'home'},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (s) => state.setMode(s.first),
                ),
                const SizedBox(height: 10),
                _TagField(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final String label;
  final Color color;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final double? progress; // 0..1 — линейный бар под группой

  const _GroupTile({
    required this.label,
    required this.color,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? color.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 4,
                      height: 22,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (onEdit != null)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        tooltip: '$label · edit',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit,
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      color: color,
                      backgroundColor: scheme.surfaceContainerHigh,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(label, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        onPressed: onTap,
      ),
    );
  }
}

class _TagField extends StatefulWidget {
  @override
  State<_TagField> createState() => _TagFieldState();
}

class _TagFieldState extends State<_TagField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final messenger = ScaffoldMessenger.of(context);
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final ok = await state.attachTagToSelected(text);
    if (!mounted) return;
    if (ok) {
      _controller.clear();
      messenger.showSnackBar(
        SnackBar(content: Text('${strings.t('tagAdded')}: $text')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('selectTaskFirst'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<AppState>().strings;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppTheme.radiusField),
      ),
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: strings.t('addTag'),
          prefixIcon: const Icon(Icons.tag, size: 18),
          suffixIcon: IconButton(
            icon: const Icon(Icons.arrow_forward, size: 18),
            onPressed: _submit,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
        ),
      ),
    );
  }
}
