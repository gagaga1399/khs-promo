import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../localization/app_strings.dart';
import '../services/app_info.dart';
import '../services/auth_service.dart';
import '../services/firebase_config.dart';
import '../services/releases.dart';
import '../services/update_checker.dart';
import '../state/app_state.dart';

import 'package:url_launcher/url_launcher.dart';

import 'account_screen.dart';
import 'widgets/color_picker_dialog.dart';
import 'widgets/time_wheel_picker.dart';
import 'widgets/version_folder_list.dart';
import 'changelog_screen.dart';
import 'download_progress.dart';
import 'settings_kit.dart';

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
  late final TextEditingController _bindHostController;
  late final TextEditingController _updateUrlController;
  bool _inited = false;
  bool _checking = false;
  bool _checkingServer = false;
  bool _showPcAddresses = false;
  bool _showToken = false;
  String? _version;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _vaultController = TextEditingController();
    _addressController = TextEditingController();
    _tokenController = TextEditingController();
    _portController = TextEditingController();
    _bindHostController = TextEditingController();
    _updateUrlController = TextEditingController();
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
    _bindHostController.text = state.syncBindHost;
    _updateUrlController.text = state.updateWebBaseUrl;
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
    _bindHostController.dispose();
    _updateUrlController.dispose();
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
            child: Text('• ${change.text}'),
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
      final result = alreadyFetched
          ? (cachedInfo == null
                ? const UpdateCheckResult(UpdateCheckStatus.noUpdate)
                : UpdateCheckResult(UpdateCheckStatus.ok, cachedInfo))
          : (cachedInfo != null
                ? UpdateCheckResult(UpdateCheckStatus.ok, cachedInfo)
                : await state.checkForUpdate());
      final info = result.info;
      if (result.status == UpdateCheckStatus.ok &&
          info != null &&
          info.history.isNotEmpty) {
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
              VersionFolderList(releases: releases),
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

  /// Проверяет, есть ли более новая версия: сначала интернет, при неудаче —
  /// ПК по Wi-Fi. Поэтому адрес ПК больше не обязателен.
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
      messenger.showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 4)),
      );
      await _showChangelog(
        strings,
        cachedInfo: info.info,
        alreadyFetched: true,
      );
      return;
    }
    final meta = info.info!;
    final current = _version;
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
    final file = Platform.isAndroid ? info.androidFile : info.windowsFile;
    if (file == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('noUpdateFile'))),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    // Пользователь мог уйти с экрана, пока искали папку: показывать диалог
    // уже нельзя, а progress нельзя забыть Dispose-ить.
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
      final expectedSha = Platform.isAndroid
          ? info.androidSha256
          : info.windowsSha256;
      saved = await state.downloadUpdate(
        file,
        dir,
        expectedSha256: expectedSha,
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
                : '${strings.t('downloadFailed')}: ${_shortError(e)}',
          ),
        ),
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
    progress.dispose();
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

  String _timestampName() {
    final d = DateTime.now();
    final ts =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}'
        '_${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}';
    return 'KHS-backup-$ts.json';
  }

  Future<Directory?> _backupDir() async {
    if (Platform.isAndroid) {
      try {
        final d = await getDownloadsDirectory();
        if (d != null) return d;
      } catch (_) {}
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> _exportBackup(
    BuildContext context,
    AppState state,
    AppStrings strings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await _backupDir();
    if (dir == null) return;
    final file = File(
      '${dir.path}${Platform.pathSeparator}${_timestampName()}',
    );
    try {
      await state.exportBackup(file);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${strings.t('backupExported')} ${file.path}'),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${strings.t('downloadFailed')}: $e')),
      );
    }
  }

  Future<void> _importBackup(
    BuildContext context,
    AppState state,
    AppStrings strings,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await _backupDir();
    // context здесь — чужой, переданный сверху, поэтому проверяем именно его
    // mounted, а не mounted состояния.
    if (!context.mounted) return;
    final defaultPath = dir == null
        ? '${Platform.pathSeparator}${_timestampName()}'
        : '${dir.path}${Platform.pathSeparator}${_timestampName()}';
    final controller = TextEditingController(text: defaultPath);
    final path = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(strings.t('backupImportTitle')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            hintText: 'C:\\...\\KHS-backup-2026-01-01_1230.json',
            prefixIcon: const Icon(Icons.file_open_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(strings.t('importBackup')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) {
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('backupFileNotFound'))),
      );
      return;
    }
    try {
      final result = await state.importBackup(file);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            strings
                .t('backupImported')
                .replaceFirst('{1}', '${result.tasks}')
                .replaceFirst('{2}', '${result.notes}'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(strings.t('backupBadFile'))),
      );
    }
  }

  Widget _backupSection(AppState state, AppStrings strings) {
    final muted = SettingsTokens.muted(context);
    return SettingsCard(
      title: strings.t('backup'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsTokens.padH,
            12,
            SettingsTokens.padH,
            10,
          ),
          child: Text(
            strings.t('backupHelp'),
            style: TextStyle(
              fontSize: SettingsTokens.rowSubtitleSize,
              color: muted,
              height: 1.35,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsTokens.padH,
            0,
            SettingsTokens.padH,
            14,
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _exportBackup(context, state, strings),
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(strings.t('exportBackup')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _importBackup(context, state, strings),
                  icon: const Icon(Icons.file_upload_outlined),
                  label: Text(strings.t('importBackup')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
    final muted = SettingsTokens.muted(context);

    final children = <Widget>[];

    children.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(
          SettingsTokens.padH,
          12,
          SettingsTokens.padH,
          10,
        ),
        child: Text(
          isPc ? strings.t('pcAccessHelp') : strings.t('syncPhoneHelp'),
          style: TextStyle(
            fontSize: SettingsTokens.rowSubtitleSize,
            color: muted,
            height: 1.35,
          ),
        ),
      ),
    );

    if (isPc) {
      children.add(
        SettingsRow(
          title: strings.t('pcAccess'),
          icon: Icons.dns_outlined,
          iconColor: SettingsTokens.iconNetwork,
          trailing: Switch(
            value: state.syncServerEnabled,
            onChanged: (v) => state.setSyncServerEnabled(v),
          ),
          onTap: () => state.setSyncServerEnabled(!state.syncServerEnabled),
          showChevron: false,
        ),
      );
      children.add(
        FutureBuilder<bool>(
          future: state.isAutoStartEnabled(),
          builder: (context, snapshot) {
            final enabled = snapshot.data ?? false;
            return SettingsRow(
              title: strings.t('autoStart'),
              subtitle: strings.t('autoStartHelp'),
              icon: Icons.rocket_launch_outlined,
              iconColor: SettingsTokens.iconUpdate,
              trailing: Switch(
                value: enabled,
                onChanged: (v) async {
                  // Messenger берём до await: после паузы к context уже не
                  // прикасаемся, остаётся только проверка mounted.
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await state.setAutoStartEnabled(v);
                  if (!mounted) return;
                  setState(() {});
                  if (!ok) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(strings.t('connectionFail'))),
                    );
                  }
                },
              ),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok = await state.setAutoStartEnabled(!enabled);
                if (!mounted) return;
                setState(() {});
                if (!ok) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(strings.t('connectionFail'))),
                  );
                }
              },
              showChevron: false,
            );
          },
        ),
      );
      children.add(
        SettingsField(
          controller: _updateUrlController,
          keyboardType: TextInputType.url,
          label: strings.t('updateWebUrl'),
          hint: kUpdateWebBaseUrl,
          maxLength: 300,
          prefixIcon: Icon(
            Icons.cloud_download_outlined,
            size: 20,
            color: SettingsTokens.iconNetwork,
          ),
          onChanged: (v) => state.setUpdateWebBaseUrl(v),
        ),
      );
      if (state.syncServerEnabled) {
        children.add(
          SettingsField(
            controller: _portController,
            keyboardType: TextInputType.number,
            label: strings.t('syncPort'),
            prefixIcon: Icon(
              Icons.power,
              size: 20,
              color: SettingsTokens.iconMetadata,
            ),
            onChanged: (v) => _savePort(state, v),
          ),
        );
        children.add(
          SettingsField(
            controller: _bindHostController,
            keyboardType: TextInputType.url,
            label: strings.t('syncBindHost'),
            hint: strings.t('syncBindHostHint'),
            maxLength: 100,
            prefixIcon: Icon(
              Icons.podcasts_outlined,
              size: 20,
              color: SettingsTokens.iconPlayback,
            ),
            onChanged: (v) => state.setSyncBindHost(v),
          ),
        );
        children.add(
          SettingsField(
            controller: _tokenController,
            obscureText: !_showToken,
            label: strings.t('syncToken'),
            hint: strings.t('syncTokenHint'),
            maxLength: 128,
            prefixIcon: Icon(
              Icons.key_outlined,
              size: 20,
              color: SettingsTokens.iconSecurity,
            ),
            suffix: IconButton(
              icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
            onChanged: (v) => state.setSyncToken(v),
          ),
        );
        if (state.localAddresses.isNotEmpty) {
          children.add(
            Padding(
              padding: const EdgeInsets.fromLTRB(
                SettingsTokens.padH,
                4,
                SettingsTokens.padH,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.t('pcAddresses'),
                          style: TextStyle(
                            fontSize: SettingsTokens.rowTitleSize,
                            color: SettingsTokens.text(context),
                          ),
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
                      SelectableText(
                        'http://$addr:${state.syncPort}',
                        style: TextStyle(
                          fontSize: SettingsTokens.rowSubtitleSize,
                          color: muted,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      strings.t('pcAddressesNote'),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      state.syncServerRunning
                          ? '● ${strings.t('syncStatusOk')}'
                          : '○ ${strings.t('syncStatusError')}',
                      style: TextStyle(
                        color: state.syncServerRunning
                            ? SettingsTokens.iconDownload
                            : SettingsTokens.iconSecurity,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Причина сбоя: без неё «сервер не запустился» бесполезно —
                  // например, опечатку в адресе прослушивания иначе не найти.
                  if (!state.syncServerRunning &&
                      state.syncServerError.isNotEmpty) ...[
                    Text(
                      state.syncServerError,
                      style: TextStyle(
                        fontSize: 12,
                        color: SettingsTokens.iconSecurity,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          );
        }
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              0,
              SettingsTokens.padH,
              12,
            ),
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
        );
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              0,
              SettingsTokens.padH,
              14,
            ),
            child: OutlinedButton.icon(
              onPressed: () => _openFirewall(context, state),
              icon: const Icon(Icons.shield_outlined),
              label: Text(strings.t('firewallOpen')),
            ),
          ),
        );
      }
    } else {
      children.add(
        SettingsRow(
          title: strings.t('syncEnabled'),
          icon: Icons.cloud_sync_outlined,
          iconColor: SettingsTokens.iconSync,
          trailing: Switch(
            value: state.syncEnabled,
            onChanged: (v) => state.setSyncEnabled(v),
          ),
          onTap: () => state.setSyncEnabled(!state.syncEnabled),
          showChevron: false,
        ),
      );
      if (state.syncEnabled) {
        children.add(
          SettingsField(
            controller: _addressController,
            keyboardType: TextInputType.url,
            label: strings.t('syncAddress'),
            hint: strings.t('syncAddressHint'),
            maxLength: 300,
            prefixIcon: Icon(
              Icons.router_outlined,
              size: 20,
              color: SettingsTokens.iconNetwork,
            ),
            onChanged: (v) => state.setSyncAddress(v),
          ),
        );
        children.add(
          SettingsField(
            controller: _tokenController,
            obscureText: !_showToken,
            label: strings.t('syncToken'),
            hint: strings.t('syncTokenHint'),
            maxLength: 128,
            prefixIcon: Icon(
              Icons.key_outlined,
              size: 20,
              color: SettingsTokens.iconSecurity,
            ),
            suffix: IconButton(
              icon: Icon(_showToken ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
            onChanged: (v) => state.setSyncToken(v),
          ),
        );
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              12,
              SettingsTokens.padH,
              14,
            ),
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
        );
      }
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SettingsTokens.padH,
            4,
            SettingsTokens.padH,
            14,
          ),
          child: Text(
            '${strings.t('lastSync')}: ${_syncStatusLabel(state, strings)}',
            style: TextStyle(
              fontSize: SettingsTokens.rowSubtitleSize,
              color: muted,
            ),
          ),
        ),
      );
    }

    return SettingsCard(title: strings.t('syncTitle'), children: children);
  }

  Widget _noteReminderSection(AppState state, AppStrings strings) {
    return SettingsCard(
      children: [
        SettingsRow(
          title: strings.t('noteReminder'),
          subtitle: strings.t('noteReminderHelp'),
          icon: Icons.edit_note_outlined,
          iconColor: SettingsTokens.iconNotes,
          trailing: Switch(
            value: state.noteReminderEnabled,
            onChanged: (v) => state.setNoteReminderEnabled(v),
          ),
          onTap: () => state.setNoteReminderEnabled(!state.noteReminderEnabled),
          showChevron: false,
        ),
        if (state.noteReminderEnabled)
          SettingsRow(
            title: strings.t('reminder'),
            subtitle: _timeLabel(state.noteReminderMinutes),
            icon: Icons.schedule_outlined,
            iconColor: SettingsTokens.iconMetadata,
            onTap: () => _pickNoteReminderTime(state),
          ),
      ],
    );
  }

  /// «Работа в фоне», «Точный будильник» и «Проверить уведомление».
  Widget _notificationReliabilitySection(AppState state, AppStrings strings) {
    return SettingsCard(
      children: [
        FutureBuilder<bool>(
          future: state.isIgnoringBatteryOptimizations(),
          builder: (context, snapshot) {
            final ok = snapshot.data ?? true;
            return SettingsRow(
              title: strings.t('backgroundWork'),
              subtitle: ok
                  ? strings.t('backgroundWorkOk')
                  : strings.t('backgroundWorkWarn'),
              icon: Icons.battery_saver_outlined,
              iconColor: SettingsTokens.iconMetadata,
              trailing: ok
                  ? Icon(Icons.check_circle, color: SettingsTokens.iconDownload)
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
            return SettingsRow(
              title: strings.t('exactAlarm'),
              subtitle: ok
                  ? strings.t('exactAlarmOk')
                  : strings.t('exactAlarmWarn'),
              icon: Icons.alarm,
              iconColor: SettingsTokens.iconSupport,
              trailing: ok
                  ? Icon(Icons.check_circle, color: SettingsTokens.iconDownload)
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
        SettingsRow(
          title: strings.t('testNotification'),
          subtitle: strings.t('testNotificationHelp'),
          icon: Icons.notification_important_outlined,
          iconColor: SettingsTokens.iconPlayback,
          trailing: const Icon(
            Icons.send_outlined,
            color: SettingsTokens.iconMedia,
          ),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            await state.sendTestNotification();
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(strings.t('testNotificationSent'))),
            );
          },
          showChevron: false,
        ),
      ],
    );
  }

  /// Группа видна, если запрос пуст или совпал с одним из её пунктов.
  bool _visible(List<String> haystack) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase().replaceAll('ё', 'е');
    return haystack.any(
      (raw) => raw.toLowerCase().replaceAll('ё', 'е').contains(q),
    );
  }

  /// Добавляет карточку в список только если она прошла поисковый фильтр
  /// и, при [enabled], доступна на текущей платформе.
  void _addVisible(
    List<Widget> children,
    List<String> keys,
    Widget child, {
    bool enabled = true,
  }) {
    if (!enabled || !_visible(keys)) return;
    children.add(child);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final isRu = state.isRussian;
    final palette = SettingsPalette.of(context);
    final children = <Widget>[];

    if (KhsFirebase.accountFeatureEnabled &&
        _visible(['Аккаунт', 'аккаунт', 'вход', 'войти', 'почте', 'google'])) {
      children.add(
        ListenableBuilder(
          listenable: AuthService.instance,
          builder: (context, _) {
            final auth = AuthService.instance;
            return SettingsProfileCard(
              icon: auth.signedIn ? Icons.account_circle : Icons.person_outline,
              iconColor: auth.signedIn
                  ? palette.accent
                  : SettingsTokens.iconAccount,
              title: auth.signedIn
                  ? (auth.displayName?.isNotEmpty == true
                        ? auth.displayName!
                        : (auth.email ?? 'Аккаунт'))
                  : 'Войти в аккаунт',
              subtitle: auth.signedIn
                  ? 'Задачи и читалка синхронизируются через интернет'
                  : 'Синхронизация между устройствами по почте или через '
                        'Google',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
              ),
            );
          },
        ),
      );
    }

    _addVisible(
      children,
      [strings.t('language'), strings.t('russian'), strings.t('english')],

      SettingsCard(
        title: strings.t('language'),
        children: [
          SettingsRow(
            title: strings.t('russian'),
            icon: Icons.translate,
            iconColor: SettingsTokens.iconMetadata,
            trailing: isRu
                ? Icon(Icons.check, color: SettingsTokens.iconDownload)
                : null,
            onTap: () => state.setLocale('ru'),
            showChevron: false,
          ),
          SettingsRow(
            title: strings.t('english'),
            icon: Icons.translate,
            iconColor: SettingsTokens.iconNetwork,
            trailing: !isRu
                ? Icon(Icons.check, color: SettingsTokens.iconDownload)
                : null,
            onTap: () => state.setLocale('en'),
            showChevron: false,
          ),
        ],
      ),
    );
    _addVisible(
      children,
      [
        strings.t('appearance'),
        strings.t('themeSystem'),
        strings.t('themeLight'),
        strings.t('themeDark'),
        strings.t('themeCustom'),
        strings.t('themeColor'),
        strings.t('themeBgColor'),
        strings.t('themeTextColor'),
      ],

      SettingsCard(
        title: strings.t('appearance'),
        children: [
          _themeOf(
            icon: Icons.brightness_auto,
            iconColor: SettingsTokens.iconFiles,
            title: strings.t('themeSystem'),
            subtitle: strings.t('themeSystemHelp'),
            selected: state.themeMode == 'system',
            onTap: () => state.setThemeMode('system'),
          ),
          _themeOf(
            icon: Icons.light_mode,
            iconColor: SettingsTokens.iconMetadata,
            title: strings.t('themeLight'),
            subtitle: strings.t('themeLightHelp'),
            selected: state.themeMode == 'light',
            onTap: () => state.setThemeMode('light'),
          ),
          _themeOf(
            icon: Icons.dark_mode,
            iconColor: SettingsTokens.iconPlayback,
            title: strings.t('themeDark'),
            subtitle: strings.t('themeDarkHelp'),
            selected: state.themeMode == 'dark',
            onTap: () => state.setThemeMode('dark'),
          ),
          _themeOf(
            icon: Icons.palette,
            iconColor: SettingsTokens.iconAppearance,
            title: strings.t('themeCustom'),
            subtitle: strings.t('themeCustomHelp'),
            selected: state.themeMode == 'custom',
            onTap: () => state.setThemeMode('custom'),
          ),
          if (state.themeMode == 'custom') ...[
            _swatchOf(
              color: state.accentColor,
              title: strings.t('themeBgColor'),
              subtitle: strings.t('themeBgColorTap'),
              onTap: () async {
                final picked = await showColorPickerDialog(
                  context,
                  initial: state.accentColor,
                  title: strings.t('themeBgColor'),
                  cancelLabel: strings.t('cancel'),
                  okLabel: strings.t('ok'),
                );
                if (picked != null && mounted) {
                  await state.setAccentColor(picked);
                }
              },
            ),
            _swatchOf(
              color: state.customTextColor,
              title: strings.t('themeTextColor'),
              subtitle: strings.t('themeTextColorTap'),
              onTap: () async {
                final picked = await showColorPickerDialog(
                  context,
                  initial: state.customTextColor,
                  title: strings.t('themeTextColor'),
                  cancelLabel: strings.t('cancel'),
                  okLabel: strings.t('ok'),
                );
                if (picked != null && mounted) {
                  await state.setCustomTextColor(picked);
                }
              },
            ),
          ] else
            SettingsRow(
              title: strings.t('themeColor'),
              subtitle: strings.t('themeColorSubtitle'),
              icon: Icons.palette_outlined,
              iconColor: SettingsTokens.iconAppearance,
              trailing: _swatch(state.accentColor),
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
    );
    _addVisible(
      children,
      [
        strings.t('notifications'),
        strings.t('notificationsEnabled'),
        strings.t('noteReminder'),
        strings.t('backgroundWork'),
        strings.t('exactAlarm'),
        strings.t('testNotification'),
      ],

      SettingsCard(
        title: strings.t('notifications'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              12,
              SettingsTokens.padH,
              4,
            ),
            child: Text(
              strings.t('notificationsHelp'),
              style: TextStyle(
                fontSize: SettingsTokens.rowSubtitleSize,
                color: SettingsTokens.muted(context),
                height: 1.35,
              ),
            ),
          ),
          SettingsRow(
            title: strings.t('notificationsEnabled'),
            icon: Icons.notifications_active_outlined,
            iconColor: SettingsTokens.iconSupport,
            trailing: Switch(
              value: state.notificationsEnabled,
              onChanged: (v) => state.setNotificationsEnabled(v),
            ),
            onTap: () =>
                state.setNotificationsEnabled(!state.notificationsEnabled),
            showChevron: false,
          ),
        ],
      ),
    );
    _addVisible(
      children,
      [
        strings.t('noteReminder'),
        strings.t('reminder'),
        strings.t('backgroundWork'),
        strings.t('exactAlarm'),
        strings.t('testNotification'),
      ],
      _noteReminderSection(state, strings),
      enabled: !state.isPc,
    );
    _addVisible(
      children,
      [
        strings.t('backgroundWork'),
        strings.t('exactAlarm'),
        strings.t('testNotification'),
      ],
      _notificationReliabilitySection(state, strings),
      enabled: !state.isPc,
    );
    _addVisible(
      children,
      [
        strings.t('obsidian'),
        strings.t('vaultPath'),
        strings.t('vaultQuickSwitch'),
        strings.t('saveVaultPath'),
        strings.t('syncNow'),
      ],

      SettingsCard(
        title: strings.t('obsidian'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              12,
              SettingsTokens.padH,
              10,
            ),
            child: Text(
              strings.t('obsidianHelp'),
              style: TextStyle(
                fontSize: SettingsTokens.rowSubtitleSize,
                color: SettingsTokens.muted(context),
                height: 1.35,
              ),
            ),
          ),
          if (state.savedVaultPaths.isNotEmpty)
            DropdownButtonFormField<String>(
              key: ValueKey('vault_switch_${state.obsidian.vaultPath}'),
              initialValue: state.obsidian.vaultPath.isEmpty
                  ? null
                  : (state.savedVaultPaths.contains(state.obsidian.vaultPath)
                        ? state.obsidian.vaultPath
                        : null),
              isExpanded: true,
              decoration: settingsInputDecoration(
                context,
                label: strings.t('vaultQuickSwitch'),
                prefixIcon: Icon(
                  Icons.swap_horiz,
                  size: 20,
                  color: SettingsTokens.iconFiles,
                ),
              ),
              dropdownColor: palette.card,
              borderRadius: BorderRadius.circular(SettingsTokens.radiusCard),
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
          SettingsField(
            controller: _vaultController,
            label: strings.t('vaultPath'),
            hint: strings.t('vaultPathHint'),
            maxLength: 500,
            prefixIcon: Icon(
              Icons.folder,
              size: 20,
              color: SettingsTokens.iconFiles,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              12,
              SettingsTokens.padH,
              14,
            ),
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
            padding: const EdgeInsets.fromLTRB(
              SettingsTokens.padH,
              0,
              SettingsTokens.padH,
              14,
            ),
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
        ],
      ),
    );
    _addVisible(children, [
      strings.t('syncTitle'),
      strings.t('syncNow'),
    ], _syncSection(state, strings));
    _addVisible(children, [
      strings.t('backup'),
      strings.t('exportBackup'),
    ], _backupSection(state, strings));
    _addVisible(
      children,
      [
        strings.t('about'),
        strings.t('checkUpdates'),
        strings.t('whatsNew'),
        strings.t('site'),
      ],

      SettingsCard(
        children: [
          SettingsRow(
            title: strings.t('about'),
            subtitle: _version == null ? 'KHS' : 'KHS v$_version',
            icon: Icons.info_outline,
            iconColor: SettingsTokens.iconMedia,
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'KHS',
              applicationVersion: _version == null ? null : 'v$_version',
              applicationLegalese: '${strings.t('developer')}: QutZem',
            ),
          ),
          SettingsRow(
            title: strings.t('checkUpdates'),
            subtitle: _version == null
                ? strings.t('currentVersion')
                : '${strings.t('currentVersion')}: v$_version',
            icon: Icons.system_update_alt,
            iconColor: SettingsTokens.iconUpdate,
            onTap: () => _checkUpdates(context, strings),
          ),
          SettingsRow(
            title: strings.t('whatsNew'),
            icon: Icons.new_releases_outlined,
            iconColor: SettingsTokens.iconMetadata,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChangelogScreen()),
            ),
          ),
          SettingsRow(
            title: strings.t('site'),
            subtitle: strings.t('siteSubtitle'),
            icon: Icons.public,
            iconColor: SettingsTokens.iconNetwork,
            trailing: const Icon(Icons.open_in_new),
            onTap: () => _openSite(state),
            showChevron: false,
          ),
        ],
      ),
    );

    final view = SettingsView(
      // Во вкладке Tasks экран уже подписан в нижней навигации, поэтому
      // крупный заголовок был вторым словом «Настройки» на одном экране.
      title: widget.embedded ? '' : strings.t('settings'),
      // Во вкладке хаба своя шапка со стрелкой «назад» есть, а окно на ПК само
      // себе шапку не рисует — там стрелка нужна.
      onBack: widget.embedded ? null : () => Navigator.maybePop(context),
      search: SettingsSearch(
        hint: strings.t('settingsSearchHint'),
        onChanged: (v) => setState(() => _query = v.trim()),
      ),
      children: children,
    );
    if (widget.embedded) return view;
    return Scaffold(
      backgroundColor: SettingsTokens.background(context),
      body: view,
    );
  }

  /// Пункт выбора темы с переключателем-кружком.
  SettingsRow _themeOf({
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

  /// Кружок с выбранным цветом.
  Widget _swatch(Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: SettingsTokens.divider(context)),
      ),
    );
  }

  /// Отдельный пункт «выбрать цвет» с кружком слева от текста.
  SettingsRow _swatchOf({
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SettingsRow(
      title: title,
      subtitle: subtitle,
      icon: Icons.circle,
      iconColor: color,
      trailing: const SizedBox.shrink(),
      onTap: onTap,
      showChevron: false,
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(url)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(url)));
      }
    }
  }
}
