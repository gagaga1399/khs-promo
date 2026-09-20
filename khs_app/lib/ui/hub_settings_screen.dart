import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../services/releases.dart';
import '../services/update_checker.dart';
import '../state/app_state.dart';
import 'changelog_screen.dart';
import 'widgets/color_picker_dialog.dart';

/// Настройки хаба KHS: плитки, внешний вид, история версий, о приложении.
class HubSettingsScreen extends StatefulWidget {
  const HubSettingsScreen({super.key});

  @override
  State<HubSettingsScreen> createState() => _HubSettingsScreenState();
}

class _HubSettingsScreenState extends State<HubSettingsScreen> {
  static const _khsPackage = 'com.qutzem.khs';
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() =>
        _version = '${info.version}+${info.buildNumber}');
  }

  /// Версия без build-суффикса — для сравнения.
  String? get _baseVersion {
    final v = _version;
    if (v == null) return null;
    return v.split('+').first;
  }

  /// Плитка «Проверить обновления» как в KHS Tasks:
  /// на ПК — локальный статус и новое, на телефоне — обновление по Wi-Fi с ПК.
  Future<void> _checkUpdates(BuildContext context, AppStrings strings) async {
    final state = context.read<AppState>();
    if (!state.isPc) {
      await _checkRemoteUpdate(state, strings);
      return;
    }
    final current = _baseVersion;
    final latest = khsHubReleases.first;
    if (current == null || latest.version.isEmpty) return;
    final upToDate = compareVersions(current, latest.version) >= 0;
    final updates = khsHubReleases
        .where((r) => compareVersions(current, r.version) < 0)
        .toList();
    final showReleases = updates.isNotEmpty ? updates : <ReleaseInfo>[latest];

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(
            upToDate ? strings.t('upToDate') : strings.t('updateAvailable'),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${strings.t('currentVersion')}: v$current'),
                if (!upToDate) ...[
                  const SizedBox(height: 8),
                  Text(
                    strings.t('howToGetUpdate'),
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  upToDate
                      ? '${strings.t('whatsNewIn')} v${latest.version}:'
                      : strings.t('whatsNewIn'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._releaseTiles(showReleases, strings),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.t('ok')),
            ),
          ],
        );
      },
    );
  }

  /// На телефоне: спрашивает ПК про более новую версию хаба и предлагает скачать.
  Future<void> _checkRemoteUpdate(AppState state, AppStrings strings) async {
    final messenger = ScaffoldMessenger.of(context);
    if (state.syncAddress.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('updateNoAddress'))),
      );
      return;
    }
    final info = await state.checkForUpdate();
    if (!mounted) return;
    if (info.status != UpdateCheckStatus.ok || info.info == null) {
      final msg = info.status == UpdateCheckStatus.noUpdate
          ? strings.t('updateNotConfigured')
          : strings.t('updateConnectFail');
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final meta = info.info!;
    final current = _baseVersion;
    final newer = current == null || compareVersions(current, meta.version) < 0;
    if (!newer) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.t('upToDate')),
          content: Text(
            '${strings.t('currentVersion')}: v$current\n'
            '${strings.t('upToDateRemote')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(strings.t('ok')),
            ),
          ],
        ),
      );
      return;
    }
    await _showUpdateDialog(state, strings, meta);
  }

  Future<void> _showUpdateDialog(
    AppState state,
    AppStrings strings,
    UpdateInfo info,
  ) async {
    final releases = info.history.isNotEmpty
        ? info.history
        : (info.notes.isEmpty
              ? <ReleaseInfo>[]
              : [
                  ReleaseInfo(
                    version: info.version,
                    date: '',
                    changes: [
                      for (final line in info.notes.split('\n'))
                        if (line.trim().isNotEmpty) ChangeEntry(line.trim()),
                    ],
                  ),
                ]);
    final wantUpdate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          strings.t('updateRemoteTitle').replaceFirst('{1}', info.version),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: releases.isEmpty
                ? [Text(strings.t('whatsNewIn'))]
                : _releaseTiles(releases, strings),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.t('download')),
          ),
        ],
      ),
    );
    if (wantUpdate != true || !mounted) return;
    await _downloadAndInstall(state, strings, info);
  }

  Future<void> _downloadAndInstall(
    AppState state,
    AppStrings strings,
    UpdateInfo info,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = info.androidFile;
    if (file == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('noUpdateFile'))),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final progress = ValueNotifier<double?>(null);
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _DownloadProgressDialog(fileName: file, progress: progress),
      ),
    );
    File saved;
    try {
      saved = await state.downloadUpdate(
        file,
        dir,
        expectedSha256: info.androidSha256,
        onProgress: (received, total) =>
            progress.value = total > 0 ? received / total : null,
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      progress.dispose();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${strings.t('downloadFailed')}: $e')),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
    progress.dispose();
    if (!mounted) return;
    final expected = info.androidSize;
    if (expected != null && expected > 0 && saved.lengthSync() != expected) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('downloadFailed'))),
      );
      return;
    }
    final canInstall = await state.canInstallPackages();
    if (!mounted) return;
    if (!canInstall) {
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.t('allowInstallTitle')),
          content: Text(strings.t('allowInstallBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(strings.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(strings.t('openSettings')),
            ),
          ],
        ),
      );
      if (open != true || !mounted) return;
      await state.openInstallSourcesSettings();
    }
    var installed = await state.installApkSilent(saved.path, package: _khsPackage);
    if (!mounted) return;
    if (!installed) {
      try {
        final result = await OpenFilex.open(
          saved.path,
          type: 'application/vnd.android.package-archive',
        );
        installed = result.type == ResultType.done;
      } catch (_) {
        installed = false;
      }
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(installed ? strings.t('allUpdated') : strings.t('installPrompt')),
      ),
    );
  }

  /// Список записей «KHS vX · дата» с изменениями.
  static List<Widget> _releaseTiles(
    List<ReleaseInfo> releases,
    AppStrings strings,
  ) {
    return [
      for (final r in releases) ...[
        Text(
          'KHS v${r.version} · ${r.date}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (final change in r.changes)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 3),
            child: Text('• ${change.text}'),
          ),
        const SizedBox(height: 8),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('hubSettingsTitle'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionHeader(strings.t('hubSettingsSectionAppearance')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.movie_creation_outlined),
            title: Text(strings.t('splashAnimation')),
            subtitle: Text(strings.t('splashAnimationHelp')),
            value: state.showSplashAnimation,
            onChanged: (v) => state.setSplashAnimation(v),
          ),
          _themeOf(
            icon: Icons.phone_android,
            title: strings.t('themeSystem'),
            subtitle: strings.t('themeSystemHelp'),
            selected: state.themeMode == 'system',
            onTap: () => state.setThemeMode('system'),
          ),
          _themeOf(
            icon: Icons.light_mode_outlined,
            title: strings.t('themeLight'),
            subtitle: strings.t('themeLightHelp'),
            selected: state.themeMode == 'light',
            onTap: () => state.setThemeMode('light'),
          ),
          _themeOf(
            icon: Icons.dark_mode_outlined,
            title: strings.t('themeDark'),
            subtitle: strings.t('themeDarkHelp'),
            selected: state.themeMode == 'dark',
            onTap: () => state.setThemeMode('dark'),
          ),
          _themeOf(
            icon: Icons.palette_outlined,
            title: strings.t('themeCustom'),
            subtitle: strings.t('themeCustomHelp'),
            selected: state.themeMode == 'custom',
            onTap: () => state.setThemeMode('custom'),
          ),
          if (state.themeMode == 'custom')
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.palette_outlined),
              title: Text(strings.t('themeColor')),
              subtitle: Text(strings.t('themeColorSubtitle')),
              trailing: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: state.accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
              ),
              onTap: () async {
                final picked = await showColorPickerDialog(
                  context,
                  initial: state.accentColor,
                  title: strings.t('themeColor'),
                  cancelLabel: strings.t('cancel'),
                  okLabel: strings.t('ok'),
                );
                if (picked != null && mounted) {
                  await state.setAccentColor(picked);
                }
              },
            ),
          const Divider(height: 24),
          _sectionHeader(strings.t('hubSettingsSectionTiles')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.task_alt),
            title: Text(strings.t('hubTasksTile')),
            value: state.showHubTasksTile,
            onChanged: (v) => state.setShowHubTasksTile(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.menu_book_outlined),
            title: Text(strings.t('hubQutzemTile')),
            value: state.showHubQutzemTile,
            onChanged: (v) => state.setShowHubQutzemTile(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.widgets_outlined),
            title: Text(strings.t('hubSoonTiles')),
            subtitle: Text(strings.t('hubSoonTilesHelp')),
            value: state.showHubSoonTiles,
            onChanged: (v) => state.setShowHubSoonTiles(v),
          ),
          const Divider(height: 24),
          _sectionHeader(strings.t('hubSettingsSectionUpdate')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_alt),
            title: Text(strings.t('checkUpdates')),
            subtitle: Text(
              _version == null
                  ? strings.t('currentVersion')
                  : '${strings.t('currentVersion')}: v$_version',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _checkUpdates(context, strings),
          ),
          const Divider(height: 24),
          _sectionHeader(strings.t('hubSettingsSectionAbout')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(strings.t('developer')),
            subtitle: const Text('QutZem'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.info_outline),
            title: Text(strings.t('version')),
            subtitle: Text(
              _version == null ? 'Pre-release' : 'Pre-release v$_version',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const ChangelogScreen(releases: khsHubReleases),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1.2,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _themeOf({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: Icon(
        selected
            ? Icons.radio_button_checked
            : Icons.radio_button_unchecked,
        color: selected ? scheme.primary : null,
      ),
      onTap: onTap,
    );
  }
}

class _DownloadProgressDialog extends StatelessWidget {
  final String fileName;
  final ValueNotifier<double?> progress;
  const _DownloadProgressDialog({required this.fileName, required this.progress});

  @override
  Widget build(BuildContext context) {
    final strings = context.read<AppState>().strings;
    return AlertDialog(
      title: Text(strings.t('downloading')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fileName,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          ValueListenableBuilder<double?>(
            valueListenable: progress,
            builder: (context, value, _) {
              final pct = value == null
                  ? null
                  : (value.clamp(0.0, 1.0) * 100).round();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    value: value,
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      pct == null ? '…' : '$pct%',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}