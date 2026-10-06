import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../services/auth_service.dart';
import '../services/releases.dart';
import '../services/update_checker.dart';
import '../state/app_state.dart';
import 'account_screen.dart';
import 'changelog_screen.dart';
import 'download_progress.dart';
import 'settings_kit.dart';
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
  String _query = '';

  /// Группа видна, если запрос пуст или совпал с одним из её пунктов.
  bool _visible(List<String> haystack) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase().replaceAll('ё', 'е');
    return haystack.any(
      (raw) => raw.toLowerCase().replaceAll('ё', 'е').contains(q),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _version = '${info.version}+${info.buildNumber}');
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

  /// Проверяет обновление хаба: сначала интернет, при неудаче — ПК по Wi-Fi.
  Future<void> _checkRemoteUpdate(AppState state, AppStrings strings) async {
    final messenger = ScaffoldMessenger.of(context);
    if (state.syncAddress.trim().isEmpty &&
        state.updateWebBaseUrl.trim().isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('updateNoAddress'))),
      );
      return;
    }
    final info = await state.checkForUpdate();
    if (!mounted) return;
    if (info.status != UpdateCheckStatus.ok || info.info == null) {
      final msg = switch (info.status) {
        UpdateCheckStatus.badSignature => strings.t('updateBadSignature'),
        UpdateCheckStatus.noUpdate => strings.t('updateNotConfigured'),
        _ => strings.t('updateConnectFail'),
      };
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
    // Пользователь мог уйти с экрана, пока искали папку: диалог уже нельзя
    // показывать, а progress нельзя забыть Dispose-ить.
    if (!mounted) return;
    final progress = DownloadProgress();
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DownloadProgressDialog(
          fileName: file,
          progress: progress,
          title: strings.t('downloading'),
        ),
      ),
    );
    File saved;
    try {
      saved = await state.downloadUpdate(
        file,
        dir,
        expectedSha256: info.androidSha256,
        onProgress: progress.call,
      );
    } catch (e) {
      if (mounted) Navigator.of(context).pop();
      progress.dispose();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is TimeoutException
                ? strings.t('downloadStalled')
                : '${strings.t('downloadFailed')}: $e',
          ),
        ),
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
    var installed = await state.installApkSilent(
      saved.path,
      package: _khsPackage,
    );
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
        content: Text(
          installed ? strings.t('allUpdated') : strings.t('installPrompt'),
        ),
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
      backgroundColor: SettingsTokens.background(context),
      body: SettingsView(
        title: strings.t('hubSettingsTitle'),
        onBack: () => Navigator.maybePop(context),
        search: SettingsSearch(
          hint: strings.t('hubSettingsSearchHint'),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        children: [
          // Вход в аккаунт нужен и с плиточного экрана: без него синхронизацию
          // на ПК включить негде — экран задач тут не открывается.
          if (_visible([
            'аккаунт',
            'вход',
            'профил',
            'задач и заметки',
            'войти',
          ]))
            ListenableBuilder(
              listenable: AuthService.instance,
              builder: (context, _) {
                final auth = AuthService.instance;
                return SettingsProfileCard(
                  icon: auth.signedIn
                      ? Icons.account_circle
                      : Icons.person_outline,
                  iconColor: auth.signedIn
                      ? SettingsPalette.of(context).accent
                      : SettingsTokens.iconAccount,
                  title: auth.signedIn
                      ? (auth.displayName?.isNotEmpty == true
                            ? auth.displayName!
                            : (auth.email ?? 'Аккаунт'))
                      : 'Войти в аккаунт',
                  subtitle: auth.signedIn
                      ? 'Задачи и заметки синхронизируются через интернет'
                      : 'Синхронизация между устройствами по почте или через '
                            'Google',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountScreen(),
                    ),
                  ),
                );
              },
            ),
          if (_visible([
            strings.t('splashAnimation'),
            strings.t('themeSystem'),
            strings.t('themeLight'),
            strings.t('themeDark'),
            strings.t('themeCustom'),
            strings.t('themeColor'),
          ]))
            SettingsCard(
              title: strings.t('hubSettingsSectionAppearance'),
              children: [
                SettingsRow(
                  title: strings.t('splashAnimation'),
                  subtitle: strings.t('splashAnimationHelp'),
                  icon: Icons.movie_creation_outlined,
                  iconColor: SettingsTokens.iconPlayback,
                  trailing: Switch(
                    value: state.showSplashAnimation,
                    onChanged: (v) => state.setSplashAnimation(v),
                  ),
                  onTap: () =>
                      state.setSplashAnimation(!state.showSplashAnimation),
                  showChevron: false,
                ),
                _themeOf(
                  icon: Icons.phone_android,
                  iconColor: SettingsTokens.iconFiles,
                  title: strings.t('themeSystem'),
                  subtitle: strings.t('themeSystemHelp'),
                  selected: state.themeMode == 'system',
                  onTap: () => state.setThemeMode('system'),
                ),
                _themeOf(
                  icon: Icons.light_mode_outlined,
                  iconColor: SettingsTokens.iconMetadata,
                  title: strings.t('themeLight'),
                  subtitle: strings.t('themeLightHelp'),
                  selected: state.themeMode == 'light',
                  onTap: () => state.setThemeMode('light'),
                ),
                _themeOf(
                  icon: Icons.dark_mode_outlined,
                  iconColor: SettingsTokens.iconPlayback,
                  title: strings.t('themeDark'),
                  subtitle: strings.t('themeDarkHelp'),
                  selected: state.themeMode == 'dark',
                  onTap: () => state.setThemeMode('dark'),
                ),
                _themeOf(
                  icon: Icons.palette_outlined,
                  iconColor: SettingsTokens.iconAppearance,
                  title: strings.t('themeCustom'),
                  subtitle: strings.t('themeCustomHelp'),
                  selected: state.themeMode == 'custom',
                  onTap: () => state.setThemeMode('custom'),
                ),
                if (state.themeMode == 'custom')
                  SettingsRow(
                    title: strings.t('themeColor'),
                    subtitle: strings.t('themeColorSubtitle'),
                    icon: Icons.palette_outlined,
                    iconColor: SettingsTokens.iconAppearance,
                    trailing: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: state.accentColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: SettingsTokens.divider(context),
                        ),
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
              ],
            ),
          if (_visible([
            strings.t('hubTasksTile'),
            strings.t('hubQutzemTile'),
            strings.t('hubSoonTiles'),
          ]))
            SettingsCard(
              title: strings.t('hubSettingsSectionTiles'),
              children: [
                SettingsRow(
                  title: strings.t('hubTasksTile'),
                  icon: Icons.task_alt,
                  iconColor: SettingsTokens.iconTasks,
                  trailing: Switch(
                    value: state.showHubTasksTile,
                    onChanged: (v) => state.setShowHubTasksTile(v),
                  ),
                  onTap: () =>
                      state.setShowHubTasksTile(!state.showHubTasksTile),
                  showChevron: false,
                ),
                SettingsRow(
                  title: strings.t('hubQutzemTile'),
                  icon: Icons.menu_book_outlined,
                  iconColor: SettingsTokens.iconText,
                  trailing: Switch(
                    value: state.showHubQutzemTile,
                    onChanged: (v) => state.setShowHubQutzemTile(v),
                  ),
                  onTap: () =>
                      state.setShowHubQutzemTile(!state.showHubQutzemTile),
                  showChevron: false,
                ),
                SettingsRow(
                  title: strings.t('hubSoonTiles'),
                  subtitle: strings.t('hubSoonTilesHelp'),
                  icon: Icons.widgets_outlined,
                  iconColor: SettingsTokens.iconStorage,
                  trailing: Switch(
                    value: state.showHubSoonTiles,
                    onChanged: (v) => state.setShowHubSoonTiles(v),
                  ),
                  onTap: () =>
                      state.setShowHubSoonTiles(!state.showHubSoonTiles),
                  showChevron: false,
                ),
              ],
            ),
          if (_visible([
            strings.t('checkUpdates'),
            strings.t('currentVersion'),
          ]))
            SettingsCard(
              title: strings.t('hubSettingsSectionUpdate'),
              children: [
                SettingsRow(
                  title: strings.t('checkUpdates'),
                  subtitle: _version == null
                      ? strings.t('currentVersion')
                      : '${strings.t('currentVersion')}: v$_version',
                  icon: Icons.system_update_alt,
                  iconColor: SettingsTokens.iconUpdate,
                  onTap: () => _checkUpdates(context, strings),
                ),
              ],
            ),
          if (_visible([
            strings.t('developer'),
            strings.t('version'),
            'qutzem',
          ]))
            SettingsCard(
              title: strings.t('hubSettingsSectionAbout'),
              children: [
                SettingsRow(
                  title: strings.t('developer'),
                  subtitle: 'QutZem',
                  icon: Icons.person_outline,
                  iconColor: SettingsTokens.iconProfile,
                ),
                SettingsRow(
                  title: strings.t('version'),
                  subtitle: _version == null
                      ? 'Pre-release'
                      : 'Pre-release v$_version',
                  icon: Icons.info_outline,
                  iconColor: SettingsTokens.iconMedia,
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
        ],
      ),
    );
  }

  Widget _themeOf({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = SettingsPalette.of(context);
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: iconColor,
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? palette.accent : palette.muted,
      ),
      onTap: onTap,
      showChevron: false,
    );
  }
}
