import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../services/app_info.dart';
import '../services/releases.dart';
import '../services/update_checker.dart';
import '../state/app_state.dart';
import 'package:url_launcher/url_launcher.dart';
import 'widgets/color_picker_dialog.dart';
import 'widgets/time_wheel_picker.dart';

class SettingsScreen extends StatefulWidget {
  /// [embedded] — вкладка нижней навигации на телефоне (без собственного
  /// Scaffold и шапки). Иначе экран открывается отдельным окном (ПК).
  const SettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _vaultController;
  late final TextEditingController _addressController;
  late final TextEditingController _tokenController;
  late final TextEditingController _portController;
  bool _inited = false;
  bool _checking = false;
  bool _checkingServer = false;
  bool _showPcAddresses = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _vaultController = TextEditingController();
    _addressController = TextEditingController();
    _tokenController = TextEditingController();
    _portController = TextEditingController();
    AppInfo.version().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  void _initText(AppState state) {
    if (_inited) return;
    _inited = true;
    _vaultController.text = state.obsidian.vaultPath;
    _addressController.text = state.syncAddress;
    _tokenController.text = state.syncToken;
    _portController.text = '${state.syncPort}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initText(context.read<AppState>());
  }

  @override
  void dispose() {
    _vaultController.dispose();
    _addressController.dispose();
    _tokenController.dispose();
    _portController.dispose();
    super.dispose();
  }

  static String _timeLabel(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Список записей «KHS vX · дата» с изменениями.
  List<Widget> _releaseTiles(List<ReleaseInfo> releases, AppStrings strings) {
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
            child: Text('• $change'),
          ),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// История «Что нового». [cachedInfo] — уже полученный ответ ПК
  /// (передаётся, чтобы не делать повторный запрос после неудачи).
  /// Если [alreadyFetched] — повторно на ПК не ходим (используем
  /// [cachedInfo] или локальную историю).
  Future<void> _showChangelog(
    AppStrings strings, {
    UpdateInfo? cachedInfo,
    bool alreadyFetched = false,
  }) async {
    final state = context.read<AppState>();
    var releases = khsReleases;
    var fromServer = false;
    // На телефоне история берётся с ПК-сервера: так она не застревает
    // на версии, с которой установлено приложение.
    if (!state.isPc) {
      final info = alreadyFetched
          ? cachedInfo
          : (cachedInfo ?? await state.checkForUpdate());
      if (info != null && info.history.isNotEmpty) {
        releases = info.history;
        fromServer = true;
      }
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('versionHistory')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!state.isPc && !fromServer)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    strings.t('historyOfflineNote'),
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
              ..._releaseTiles(releases, strings),
            ],
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

  Future<void> _checkUpdates(BuildContext context, AppStrings strings) async {
    final state = context.read<AppState>();
    if (!state.isPc) {
      await _checkRemoteUpdate(state, strings);
      return;
    }
    final current = _version;
    final latest = latestRelease;
    if (latest == null) return;

    final upToDate =
        current != null && compareVersions(current, latest.version) >= 0;
    final updates = current == null
        ? khsReleases
        : khsReleases
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
                if (current != null)
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

  /// На телефоне: спрашивает ПК про более новую версию и предлагает скачать.
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
    if (info == null || info.version.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(strings.t('updateConnectFail')),
          duration: const Duration(seconds: 4),
        ),
      );
      await _showChangelog(strings, cachedInfo: info, alreadyFetched: true);
      return;
    }
    final current = _version;
    final newer = current == null || compareVersions(current, info.version) < 0;
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
    await _showUpdateDialog(state, strings, info);
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
                    changes: info.notes.split('\n'),
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
    final file = Platform.isAndroid ? info.androidFile : info.windowsFile;
    if (file == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('noUpdateFile'))),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    messenger.showSnackBar(SnackBar(content: Text(strings.t('downloading'))));
    File saved;
    try {
      saved = await state.downloadUpdate(file, dir);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${strings.t('downloadFailed')}: ${_shortError(e)}'),
        ),
      );
      return;
    }
    if (!mounted) return;
    if (Platform.isAndroid) {
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
      try {
        final result = await OpenFilex.open(
          saved.path,
          type: 'application/vnd.android.package-archive',
        );
        if (!mounted) return;
        if (result.type != ResultType.done) {
          messenger.showSnackBar(
            SnackBar(content: Text(strings.t('openFileFailed'))),
          );
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text(strings.t('installPrompt'))),
          );
        }
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text('${strings.t('openFileFailed')}: ${_shortError(e)}'),
          ),
        );
      }
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text('${strings.t('savedTo')}: ${saved.path}')),
      );
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    final idx = s.indexOf('\n');
    return (idx == -1 ? s : s.substring(0, idx)).trim();
  }

  Future<void> _pickVaultFolder(AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = state.strings;
    if (!await state.hasAllFilesAccess()) {
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(strings.t('allFilesAccessTitle')),
          content: Text(strings.t('allFilesAccessBody')),
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
      await state.requestAllFilesAccess();
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('grantThenPickVault'))),
      );
      return;
    }
    final picked = await state.pickVaultFolder();
    if (!mounted) return;
    if (picked == null || picked.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('vaultNotPicked'))),
      );
      return;
    }
    _vaultController.text = picked;
    await state.setVaultPath(picked);
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(strings.t('vaultPicked'))));
  }

  Future<void> _savePath(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    await state.setVaultPath(_vaultController.text);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(state.strings.t('vaultPathSaved'))),
    );
  }

  Future<void> _sync(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = state.strings;
    final result = await state.syncWithObsidian();
    if (!mounted) return;
    final message = result.error != null
        ? strings
              .t('syncFailed')
              .replaceFirst('{1}', strings.t(result.error ?? 'noVaultPath'))
        : strings
              .t('syncDone')
              .replaceFirst('{1}', '${result.added}')
              .replaceFirst('{2}', '${result.updated}')
              .replaceFirst('{3}', '${result.written}');
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testConnection(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = state.strings;
    setState(() => _checking = true);
    final ok = await state.checkPcConnection();
    if (!mounted) return;
    setState(() => _checking = false);
    if (ok) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('connectionOk'))),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('connectionFail'))),
      );
      _showConnectionHelp(this.context, strings);
    }
  }

  void _showConnectionHelp(BuildContext context, AppStrings strings) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('connectionFailHelpTitle')),
        content: Text(strings.t('connectionFailHelpBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.t('ok')),
          ),
        ],
      ),
    );
  }

  Future<void> _checkServer(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = state.strings;
    setState(() => _checkingServer = true);
    final ok = await state.checkLocalServer();
    if (!mounted) return;
    setState(() => _checkingServer = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? strings.t('serverOk') : strings.t('serverFail')),
      ),
    );
  }

  Future<void> _openFirewall(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await state.openFirewallPort();
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _syncWithPc(BuildContext context, AppState state) async {
    final messenger = ScaffoldMessenger.of(context);
    final strings = state.strings;
    messenger.showSnackBar(SnackBar(content: Text(strings.t('syncBusy'))));
    final result = await state.syncWithPc();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (result.status) {
          'ok' => strings.t('syncStatusOk'),
          'offline' => strings.t('syncStatusOffline'),
          _ => strings.t('syncStatusError'),
        }),
      ),
    );
  }

  void _savePort(AppState state, String value) {
    final port = int.tryParse(value.trim());
    if (port == null || port <= 0 || port > 65535) return;
    if (port != state.syncPort) state.setSyncPort(port);
  }

  String _syncStatusLabel(AppState state, AppStrings strings) {
    if (state.lastSyncTime == null) return strings.t('neverSynced');
    return switch (state.lastSyncStatus) {
      'ok' => strings.t('syncStatusOk'),
      'offline' => strings.t('syncStatusOffline'),
      'error' => strings.t('syncStatusError'),
      _ => strings.t('neverSynced'),
    };
  }

  Future<void> _pickNoteReminderTime(AppState state) async {
    final minutes = state.noteReminderMinutes;
    final picked = await showTimeWheelPicker(
      context,
      initial: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      strings: state.strings,
    );
    if (picked == null) return;
    await state.setNoteReminderMinutes(picked.hour * 60 + picked.minute);
  }

  Widget _syncSection(AppState state, AppStrings strings) {
    final isPc = state.isPc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.t('syncTitle'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            isPc ? strings.t('pcAccessHelp') : strings.t('syncPhoneHelp'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (isPc)
          SwitchListTile(
            secondary: const Icon(Icons.dns_outlined),
            title: Text(strings.t('pcAccess')),
            value: state.syncServerEnabled,
            onChanged: (v) => state.setSyncServerEnabled(v),
          ),
        if (isPc && state.syncServerEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _portController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: strings.t('syncPort'),
                prefixIcon: const Icon(Icons.power),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (v) => _savePort(state, v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _tokenController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: strings.t('syncToken'),
                hintText: strings.t('syncTokenHint'),
                prefixIcon: const Icon(Icons.key_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              onChanged: (v) => state.setSyncToken(v),
            ),
          ),
          if (state.localAddresses.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.t('pcAddresses'),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(
                          () => _showPcAddresses = !_showPcAddresses,
                        ),
                        icon: Icon(
                          _showPcAddresses
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        label: Text(
                          _showPcAddresses
                              ? strings.t('hideAddresses')
                              : strings.t('showAddresses'),
                        ),
                      ),
                    ],
                  ),
                  if (_showPcAddresses) ...[
                    for (final addr in state.localAddresses)
                      SelectableText('http://$addr:${state.syncPort}'),
                    const SizedBox(height: 4),
                    Text(
                      strings.t('pcAddressesNote'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    state.syncServerRunning
                        ? '● ${strings.t('syncStatusOk')}'
                        : '○ ${strings.t('syncStatusError')}',
                    style: TextStyle(
                      color: state.syncServerRunning
                          ? Colors.green
                          : Colors.red,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checkingServer
                        ? null
                        : () => _checkServer(context, state),
                    icon: _checkingServer
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.healing_outlined),
                    label: Text(strings.t('checkServer')),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openFirewall(context, state),
                    icon: const Icon(Icons.shield_outlined),
                    label: Text(strings.t('firewallOpen')),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (!isPc) ...[
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync_outlined),
            title: Text(strings.t('syncEnabled')),
            value: state.syncEnabled,
            onChanged: (v) => state.setSyncEnabled(v),
          ),
          if (state.syncEnabled) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _addressController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: strings.t('syncAddress'),
                  hintText: strings.t('syncAddressHint'),
                  prefixIcon: const Icon(Icons.router_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onChanged: (v) => state.setSyncAddress(v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: TextField(
                controller: _tokenController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: strings.t('syncToken'),
                  hintText: strings.t('syncTokenHint'),
                  prefixIcon: const Icon(Icons.key_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onChanged: (v) => state.setSyncToken(v),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _checking
                          ? null
                          : () => _testConnection(context, state),
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: Text(strings.t('checkConnection')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: state.syncing
                          ? null
                          : () => _syncWithPc(context, state),
                      icon: const Icon(Icons.sync),
                      label: Text(strings.t('syncNow')),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              '${strings.t('lastSync')}: ${_syncStatusLabel(state, strings)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }

  Widget _noteReminderSection(AppState state, AppStrings strings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.edit_note_outlined),
          title: Text(strings.t('noteReminder')),
          subtitle: Text(strings.t('noteReminderHelp')),
          value: state.noteReminderEnabled,
          onChanged: (v) => state.setNoteReminderEnabled(v),
        ),
        if (state.noteReminderEnabled)
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(strings.t('reminder')),
            subtitle: Text(_timeLabel(state.noteReminderMinutes)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickNoteReminderTime(state),
          ),
      ],
    );
  }

  /// «Работа в фоне», «Точный будильник» и «Проверить уведомление».
  Widget _notificationReliabilitySection(AppState state, AppStrings strings) {
    final okColor = Colors.green;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<bool>(
          future: state.isIgnoringBatteryOptimizations(),
          builder: (context, snapshot) {
            final ok = snapshot.data ?? true;
            return ListTile(
              leading: const Icon(Icons.battery_saver_outlined),
              title: Text(strings.t('backgroundWork')),
              subtitle: Text(
                ok
                    ? strings.t('backgroundWorkOk')
                    : strings.t('backgroundWorkWarn'),
              ),
              trailing: ok
                  ? Icon(Icons.check_circle, color: okColor)
                  : const Icon(Icons.chevron_right),
              onTap: ok
                  ? null
                  : () async {
                      await state.requestIgnoreBatteryOptimizations();
                      if (mounted) setState(() {});
                    },
            );
          },
        ),
        FutureBuilder<bool>(
          future: state.canScheduleExactAlarms(),
          builder: (context, snapshot) {
            final ok = snapshot.data ?? true;
            return ListTile(
              leading: const Icon(Icons.alarm),
              title: Text(strings.t('exactAlarm')),
              subtitle: Text(
                ok ? strings.t('exactAlarmOk') : strings.t('exactAlarmWarn'),
              ),
              trailing: ok
                  ? Icon(Icons.check_circle, color: okColor)
                  : const Icon(Icons.chevron_right),
              onTap: ok
                  ? null
                  : () async {
                      await state.notifications.requestPermissions();
                      if (mounted) setState(() {});
                    },
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.notification_important_outlined),
          title: Text(strings.t('testNotification')),
          subtitle: Text(strings.t('testNotificationHelp')),
          trailing: const Icon(Icons.send_outlined),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await state.sendTestNotification();
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(strings.t('testNotificationSent'))),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final isRu = state.isRussian;

    final body = ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.t('language'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(strings.t('russian')),
          trailing: isRu ? const Icon(Icons.check, color: Colors.green) : null,
          onTap: () => state.setLocale('ru'),
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(strings.t('english')),
          trailing: !isRu ? const Icon(Icons.check, color: Colors.green) : null,
          onTap: () => state.setLocale('en'),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.t('appearance'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SwitchListTile(
          secondary: Icon(
            state.isDarkTheme ? Icons.dark_mode : Icons.light_mode,
          ),
          title: Text(
            strings.t(state.isDarkTheme ? 'darkTheme' : 'lightTheme'),
          ),
          value: state.isDarkTheme,
          onChanged: (v) => state.setDarkTheme(v),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.t('progressBars'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.t('progressBarsSubtitle'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        for (final bar in [
          AppState.barGoal,
          AppState.barPriorities,
          AppState.barWeek,
          AppState.barMonth,
          AppState.barOverdue,
          AppState.barSidebar,
        ])
          CheckboxListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(strings.t(bar)),
            value: state.barEnabled(bar),
            onChanged: (v) => state.setBarEnabled(bar, v ?? false),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.t('dailyGoal'),
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${state.dailyGoal}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => state.setDailyGoal(state.dailyGoal - 1),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => state.setDailyGoal(state.dailyGoal + 1),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
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
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.t('notifications'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            strings.t('notificationsHelp'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_active_outlined),
          title: Text(strings.t('notificationsEnabled')),
          value: state.notificationsEnabled,
          onChanged: (v) => state.setNotificationsEnabled(v),
        ),
        if (!state.isPc) ...[
          const Divider(),
          _noteReminderSection(state, strings),
        ],
        if (!state.isPc) ...[
          const Divider(),
          _notificationReliabilitySection(state, strings),
        ],
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            strings.t('obsidian'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            strings.t('obsidianHelp'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (state.savedVaultPaths.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              key: ValueKey('vault_switch_${state.obsidian.vaultPath}'),
              initialValue: state.obsidian.vaultPath.isEmpty
                  ? null
                  : (state.savedVaultPaths.contains(state.obsidian.vaultPath)
                        ? state.obsidian.vaultPath
                        : null),
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.t('vaultQuickSwitch'),
                prefixIcon: const Icon(Icons.swap_horiz),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              items: [
                for (final path in state.savedVaultPaths)
                  DropdownMenuItem(
                    value: path,
                    child: Text(path, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (path) {
                if (path == null) return;
                _vaultController.text = path;
                _savePath(context, state);
              },
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _vaultController,
            decoration: InputDecoration(
              labelText: strings.t('vaultPath'),
              hintText: strings.t('vaultPathHint'),
              prefixIcon: const Icon(Icons.folder),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _savePath(context, state),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(strings.t('saveVaultPath')),
                ),
              ),
              if (!state.isPc) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickVaultFolder(state),
                    icon: const Icon(Icons.folder_open),
                    label: Text(strings.t('chooseFolder')),
                  ),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sync(context, state),
                  icon: const Icon(Icons.sync),
                  label: Text(strings.t('syncNow')),
                ),
              ),
            ],
          ),
        ),
        const Divider(),
        _syncSection(state, strings),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(strings.t('about')),
          subtitle: Text(_version == null ? 'KHS' : 'KHS v$_version'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'KHS',
            applicationVersion: _version == null ? null : 'v$_version',
            applicationLegalese: '${strings.t('developer')}: QutZem',
          ),
        ),
        ListTile(
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
        ListTile(
          leading: const Icon(Icons.new_releases_outlined),
          title: Text(strings.t('whatsNew')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showChangelog(strings),
        ),
        ListTile(
          leading: const Icon(Icons.public),
          title: Text(strings.t('site')),
          subtitle: Text(strings.t('siteSubtitle')),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => _openSite(state),
        ),
      ],
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(strings.t('settings'))),
      body: body,
    );
  }

  /// Спрашивает подтверждение и открывает публичную промо-страницу KHS.
  Future<void> _openSite(AppState state) async {
    final strings = state.strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(strings.t('siteConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(strings.t('siteOpen')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    const url = 'https://gagaga1399.github.io/khs-promo/';
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(url)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(url)),
        );
      }
    }
  }
}
