import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../models/tracker_entry.dart';
import '../services/tracker_service.dart';
import '../state/app_state.dart';
import 'app_theme.dart';
import 'glass_bottom_bar.dart';
import 'widgets/add_tracker_dialog.dart';
import 'widgets/color_picker_dialog.dart';

/// Настройки приложения «Трекеры» — свои, отдельно от настроек хаба.
/// Сейчас здесь только собственный акцентный цвет, который трекеры
/// используют вместо цвета KHS.
class TrackerSettingsScreen extends StatelessWidget {
  const TrackerSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final accent = state.trackerAccent;

    return ColoredBox(
      color: scheme.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          20,
          16,
          20,
          40 + kGlassNavHeight + kGlassNavMarginBottom,
        ),
        children: [
          _section(
            context,
            strings.t('trackerSettingsAppearance'),
            strings.t('trackerSettingsAppearanceHelp'),
          ),
          const SizedBox(height: 10),
          _card(
            context,
            children: [
              _row(
                context,
                icon: Icons.palette_outlined,
                iconColor: accent,
                title: strings.t('trackerSettingsColor'),
                subtitle: strings.t('trackerSettingsColorHelp'),
                trailing: _swatch(context, accent),
                onTap: () async {
                  final picked = await showColorPickerDialog(
                    context,
                    initial: accent,
                    title: strings.t('trackerSettingsColor'),
                    cancelLabel: strings.t('cancel'),
                    okLabel: strings.t('ok'),
                  );
                  if (picked != null) await state.setTrackerAccent(picked);
                },
              ),
              _divider(scheme),
              _row(
                context,
                icon: Icons.restart_alt,
                iconColor: AppTheme.accentTurquoise,
                title: strings.t('trackerSettingsReset'),
                subtitle: strings.t('trackerSettingsResetHelp'),
                onTap: () => state.setTrackerAccent(AppTheme.accentTurquoise),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            context,
            strings.t('trackerLifeTitle'),
            strings.t('trackerSettingsLifeHelp'),
          ),
          const SizedBox(height: 10),
          _card(
            context,
            children: [
              _row(
                context,
                icon: Icons.cake_outlined,
                iconColor: accent,
                title: strings.t('trackerSettingsBirthday'),
                subtitle: state.birthday == null
                    ? strings.t('trackerSettingsBirthdayHelp')
                    : _fmtDay(state.birthday!),
                trailing: state.birthday == null
                    ? null
                    : IconButton(
                        tooltip: strings.t('delete'),
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        color: scheme.onSurfaceVariant,
                        icon: const Icon(Icons.close),
                        onPressed: () => state.setBirthday(null),
                      ),
                onTap: () async {
                  final today = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: state.birthday ?? DateTime(2000, 1, 1),
                    firstDate: DateTime(1920),
                    lastDate: today,
                    locale: Locale(state.locale),
                    helpText: strings.t('trackerSettingsBirthday'),
                  );
                  if (picked != null) await state.setBirthday(picked);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            context,
            strings.t('trackerMarathon'),
            strings.t('trackerMarathonHelp'),
          ),
          const SizedBox(height: 10),
          _card(
            context,
            children: [
              _row(
                context,
                icon: Icons.flag_outlined,
                iconColor: accent,
                title: strings.t('trackerMarathonStart'),
                subtitle: _fmtDay(state.marathonStart),
                onTap: () async {
                  final today = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: state.marathonStart,
                    firstDate: DateTime(2020),
                    lastDate: today,
                    locale: Locale(state.locale),
                    helpText: strings.t('trackerMarathonStart'),
                  );
                  if (picked != null) await state.setMarathonStart(picked);
                },
              ),
              _divider(scheme),
              _row(
                context,
                icon: Icons.emoji_events_outlined,
                iconColor: accent,
                title: strings.t('trackerMarathonGoal'),
                subtitle: state.marathonGoal <= 0
                    ? strings.t('trackerMarathonGoalNone')
                    : '${state.marathonGoal}',
                onTap: () async {
                  final value = await _askDays(
                    context,
                    title: strings.t('trackerMarathonGoal'),
                    initial: state.marathonGoal,
                  );
                  if (value != null) await state.setMarathonGoal(value);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            context,
            strings.t('obsidian'),
            strings.t('obsidianHelp'),
          ),
          const SizedBox(height: 10),
          const _VaultCard(),
          const SizedBox(height: 16),
          _section(
            context,
            strings.t('trackerProfiles'),
            strings.t('trackerProfilesHelp'),
          ),
          const SizedBox(height: 10),
          const _ProfilesCard(),
          const SizedBox(height: 16),
          _section(
            context,
            strings.t('trackerManage'),
            strings.t('trackerManageHelp'),
          ),
          const SizedBox(height: 10),
          const _TrackersCard(),
          const SizedBox(height: 16),
          _card(
            context,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.t('trackerSettingsNote'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title, String subtitle) {
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

  Future<int?> _askDays(
    BuildContext context, {
    required String title,
    required int initial,
  }) async {
    final strings = context.read<AppState>().strings;
    final controller = TextEditingController(
      text: initial > 0 ? '$initial' : '',
    );
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: strings.t('trackerMarathonGoalHelp'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(strings.t('cancel')),
            ),
            TextButton(
              onPressed: () {
                final n = int.tryParse(controller.text.trim()) ?? 0;
                Navigator.of(dialogContext).pop(n);
              },
              child: Text(strings.t('ok')),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(children: children),
    );
  }

  Widget _divider(ColorScheme scheme) =>
      Divider(height: 1, indent: 58, color: scheme.outlineVariant);

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing],
          ],
        ),
      ),
    );
  }

  Widget _swatch(BuildContext context, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant),
      ),
    );
  }

  static String _fmtDay(DateTime d) {
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day.$month.${d.year}';
  }
}

/// Выбор хранилища Obsidian прямо из настроек трекеров: путь можно ввести
/// вручную, сохранить или выбрать папку (на телефоне), плюс быстрый переход
/// между ранее сохранёнными хранилищами.
class _VaultCard extends StatefulWidget {
  const _VaultCard();

  @override
  State<_VaultCard> createState() => _VaultCardState();
}

class _VaultCardState extends State<_VaultCard> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = context.read<AppState>().obsidian.vaultPath;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String path) async {
    final state = context.read<AppState>();
    await state.setVaultPath(path);
    if (!mounted) return;
    await context.read<TrackerService>().refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(state.strings.t('vaultPathSaved'))),
    );
  }

  Future<void> _pick() async {
    final state = context.read<AppState>();
    final picked = await state.pickVaultFolder();
    if (picked == null || picked.trim().isEmpty) return;
    _controller.text = picked;
    await _apply(picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final accent = state.trackerAccent;
    final saved = state.savedVaultPaths;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (saved.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: DropdownButtonFormField<String>(
                key: ValueKey('tracker_vault_switch_${state.obsidian.vaultPath}'),
                initialValue: state.obsidian.vaultPath.isEmpty
                    ? null
                    : (saved.contains(state.obsidian.vaultPath)
                          ? state.obsidian.vaultPath
                          : null),
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: strings.t('vaultQuickSwitch'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.swap_horiz, size: 20),
                ),
                items: [
                  for (final path in saved)
                    DropdownMenuItem(
                      value: path,
                      child: Text(path, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (path) {
                  if (path == null) return;
                  _controller.text = path;
                  _apply(path);
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: strings.t('vaultPath'),
                hintText: strings.t('vaultPathHint'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.folder_outlined, size: 20),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _apply(_controller.text),
                    icon: const Icon(Icons.save_outlined),
                    label: Text(strings.t('saveVaultPath')),
                  ),
                ),
                if (!state.isPc) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pick,
                      icon: const Icon(Icons.folder_open),
                      label: Text(strings.t('chooseFolder')),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (state.obsidian.vaultPath.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      strings.t('trackerNoVaultHelp'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Диалог ввода имени профиля (создание или переименование).
Future<String?> _promptProfileName(
  BuildContext context,
  AppStrings strings,
  String title, {
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: const ValueKey('profile_name'),
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: strings.t('trackerProfileName')),
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
                SnackBar(
                  content: Text(strings.t('trackerProfileNameRequired')),
                ),
              );
              return;
            }
            Navigator.pop(dialogContext, name);
          },
          child: Text(strings.t('ok')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

/// Карточка профилей: выбор активного и действия над ним.
class _ProfilesCard extends StatelessWidget {
  const _ProfilesCard();

  Future<void> _add(BuildContext context) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final name = await _promptProfileName(
      context,
      strings,
      strings.t('trackerProfileNew'),
    );
    if (name == null) return;
    await state.addTrackerProfile(name);
  }

  Future<void> _rename(BuildContext context) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final profile = state.activeTrackerProfile;
    final name = await _promptProfileName(
      context,
      strings,
      strings.t('trackerProfileRename'),
      initial: profile.name,
    );
    if (name == null) return;
    await state.renameTrackerProfile(profile.id, name);
  }

  Future<void> _delete(BuildContext context) async {
    final state = context.read<AppState>();
    final strings = state.strings;
    final profile = state.activeTrackerProfile;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(
          strings
              .t('trackerProfileDeleteConfirm')
              .replaceFirst('{name}', profile.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(strings.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.deleteTrackerProfile(profile.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final profiles = state.trackerProfiles;
    final active = state.activeTrackerProfile;

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.person_outline, color: state.trackerAccent),
            title: Text(strings.t('trackerProfileActive')),
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: active.id,
                  isDense: true,
                  items: [
                    for (final profile in profiles)
                      DropdownMenuItem(
                        value: profile.id,
                        child: Text(profile.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (id) {
                    if (id != null) state.setActiveTrackerProfile(id);
                  },
                ),
              ),
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _add(context),
                  icon: const Icon(Icons.person_add_alt, size: 18),
                  label: Text(strings.t('trackerProfileAdd')),
                ),
                TextButton.icon(
                  onPressed: () => _rename(context),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(strings.t('trackerProfileRename')),
                ),
                if (profiles.length > 1)
                  TextButton.icon(
                    onPressed: () => _delete(context),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(strings.t('trackerProfileDelete')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка управления трекерами активного профиля: скрытие найденных и
/// удаление/добавление своих.
class _TrackersCard extends StatelessWidget {
  const _TrackersCard();

  Future<void> _add(BuildContext context) async {
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
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.t('trackerAddExists'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tracker = context.watch<TrackerService>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;
    final russian = strings.locale == 'ru';
    final profile = state.activeTrackerProfile;

    final discovered = [
      for (final prop in tracker.properties)
        if (prop.kind == TrackerPropertyKind.boolean ||
            prop.kind == TrackerPropertyKind.number)
          prop,
    ];

    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (discovered.isEmpty && profile.custom.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                strings.t('trackerNoDiscovered'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final prop in discovered)
            SwitchListTile(
              value: !profile.hidden.contains(prop.name),
              title: Text(prop.name),
              subtitle: Text(prop.kind.label(russian)),
              onChanged: (visible) =>
                  state.setTrackerHidden(prop.name, !visible),
            ),
          for (final custom in profile.custom)
            ListTile(
              leading: Icon(
                custom.kind == TrackerPropertyKind.boolean
                    ? Icons.check_circle_outline
                    : Icons.show_chart,
                color: state.trackerAccent,
              ),
              title: Text(custom.name),
              subtitle: Text(custom.kind.label(russian)),
              trailing: IconButton(
                tooltip: strings.t('delete'),
                icon: const Icon(Icons.delete_outline),
                onPressed: () => state.removeCustomTracker(custom.name),
              ),
            ),
          Divider(height: 1, color: scheme.outlineVariant),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: TextButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add, size: 18),
                label: Text(strings.t('trackerAdd')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
