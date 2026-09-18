import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/launcher_shortcut.dart';
import '../state/app_state.dart';
import 'home_screen.dart';
import 'hub_settings_screen.dart';

/// Экран-центр KHS: плитки приложений. Стартует после сплэша, если не
/// задан флаг запуска (--tasks). Настройки хаба — иконка в шапке.
class HubScreen extends StatefulWidget {
  const HubScreen({super.key});

  @override
  State<HubScreen> createState() => _HubScreenState();
}

class _HubScreenState extends State<HubScreen> {
  static const _qutzemExe =
      'C:\\Users\\user\\Projects\\qutzem-reader\\dist\\windows\\qutzem_reader.exe';
  static const _qutzemPackage = 'dev.qutzem.qutzem_reader';
  static const _qutzemFallbackUrl =
      'https://github.com/gagaga1399/khs-promo/raw/main/qutzem-reader.apk';

  bool _shortcutBusy = false;

  @override
  void initState() {
    super.initState();
    LauncherShortcut.listenStartTasks(_openTasksFromShortcut);
  }

  void _openTasksFromShortcut() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) return;
    _openTasks();
  }

  void _openTasks() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HubSettingsScreen()),
    );
  }

  Future<void> _openQutzem() async {
    if (Platform.isAndroid) {
      final installed =
          await LauncherShortcut.isPackageInstalled(_qutzemPackage);
      if (!mounted) return;
      if (installed) {
        await LauncherShortcut.launchPackage(_qutzemPackage);
      } else {
        _promptQutzemInstall();
      }
      return;
    }
    if (File(_qutzemExe).existsSync()) {
      unawaited(Process.start(_qutzemExe, []));
    }
  }

  Future<void> _promptQutzemInstall() async {
    final strings = context.read<AppState>().strings;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QutZem Reader'),
        content: const Text('Читалка не установлена на устройстве.\nСкачать APK?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Скачать'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final uri = Uri.parse(_qutzemFallbackUrl);
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${strings.t('shortcutError')} $_qutzemFallbackUrl'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pinTasksShortcut() async {
    final strings = context.read<AppState>().strings;
    final ok = await LauncherShortcut.createTasksShortcut(
      strings.t('hubTasksTitle'),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? strings.t('shortcutCreated') : strings.t('shortcutError'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createTasksShortcut() async {
    final strings = context.read<AppState>().strings;
    final exe = Platform.resolvedExecutable;
    await _createShortcut(
      name: strings.t('hubTasksTitle'),
      target: exe,
      args: '--tasks',
      icon: '${File(exe).parent.path}\\tasks_icon.ico',
      busyText: strings.t('shortcutCreated'),
      errorText: strings.t('shortcutError'),
    );
  }

  Future<void> _createQutzemShortcut() async {
    final strings = context.read<AppState>().strings;
    if (Platform.isAndroid) {
      final ok = await LauncherShortcut.createAppShortcut(
        _qutzemPackage,
        'QutZem Reader',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? strings.t('shortcutCreated') : strings.t('shortcutError'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    await _createShortcut(
      name: 'QutZem Reader',
      target: _qutzemExe,
      args: '',
      icon: '${File(Platform.resolvedExecutable).parent.path}\\qutzem_icon.ico',
      busyText: strings.t('shortcutCreated'),
      errorText: strings.t('shortcutError'),
    );
  }

  Future<void> _createShortcut({
    required String name,
    required String target,
    required String args,
    required String icon,
    required String busyText,
    required String errorText,
  }) async {
    if (_shortcutBusy) return;
    setState(() => _shortcutBusy = true);
    final exe = target;
    final dir = File(exe).parent.path;
    final script = '''
\$ErrorActionPreference = 'Stop'
try {
  \$shell = New-Object -ComObject WScript.Shell
  \$desktop = [Environment]::GetFolderPath('Desktop')
  \$lnk = \$shell.CreateShortcut((Join-Path \$desktop '$name.lnk'))
  \$lnk.TargetPath = '$exe'
  \$lnk.Arguments = '$args'
  \$lnk.WorkingDirectory = '$dir'
  \$lnk.IconLocation = '$icon,0'
  \$lnk.Description = '$name'
  \$lnk.Save()
  Write-Output 'OK: created'
} catch {
  Write-Error \$_
}
''';
    try {
      final ps = File('${Directory.systemTemp.path}\\khs_shortcut.ps1');
      await ps.writeAsString(script);
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        ps.path,
      ]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.exitCode == 0
              ? busyText
              : '$errorText ${result.stderr}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$errorText $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _shortcutBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;

    final hasQutzem =
        Platform.isAndroid || (Platform.isWindows && File(_qutzemExe).existsSync());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.t('hubTitle'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: strings.t('settings'),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          const _HubBackdrop(),
          SafeArea(
            child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            final cols = compact ? 2 : 4;
            const spacing = 16.0;

            final items = <({Widget tile, List<_Feature> desc})>[];
            void addTile(Widget tile, List<_Feature> desc) {
              items.add((tile: tile, desc: desc));
            }

            if (state.showHubTasksTile) {
              addTile(
                _HubTile(
                  iconAsset: 'assets/hubs/tasks-icon.png',
                  title: strings.t('hubTasksTitle'),
                  subtitle: strings.t('hubTasksSubtitle'),
                  onTap: _openTasks,
                  onShortcut: Platform.isWindows
                      ? _createTasksShortcut
                      : (Platform.isAndroid ? _pinTasksShortcut : null),
                  shortcutTooltip: strings.t('shortcutCreate'),
                  shortcutBusy: _shortcutBusy,
                ),
                [
                  _Feature(Icons.task_alt, strings.t('tasks')),
                  _Feature(Icons.edit_note, strings.t('notes')),
                  _Feature(Icons.calendar_month_outlined, strings.t('calendar')),
                ],
              );
            }
            if (state.showHubQutzemTile && hasQutzem) {
              addTile(
                _HubTile(
                  iconAsset: 'assets/hubs/qutzem-icon.png',
                  title: 'QutZem Reader',
                  subtitle: strings.t('hubQutzemSubtitle'),
                  onTap: _openQutzem,
                  onShortcut: (Platform.isWindows || Platform.isAndroid)
                      ? _createQutzemShortcut
                      : null,
                  shortcutTooltip: strings.t('shortcutCreate'),
                  shortcutBusy: _shortcutBusy,
                ),
                const [
                  _Feature(Icons.menu_book, 'EPUB'),
                  _Feature(Icons.article_outlined, 'FB2'),
                  _Feature(Icons.picture_as_pdf_outlined, 'PDF'),
                  _Feature(Icons.description_outlined, 'TXT'),
                ],
              );
            }
            if (state.showHubSoonTiles) {
              var i = 0;
              while (items.length < 4) {
                addTile(
                  _HubTile(
                    icon: i.isEven
                        ? Icons.rocket_launch_outlined
                        : Icons.widgets_outlined,
                    title: strings.t('hubSoon'),
                    subtitle: strings.t('hubSoonSubtitle'),
                    dimmed: true,
                  ),
                  const [],
                );
                i++;
              }
            }

            final blocks = <Widget>[];
            for (var i = 0; i < items.length; i += cols) {
              final slice = items.sublist(
                i,
                (i + cols) < items.length ? i + cols : items.length,
              );
              final hasDesc = slice.any((it) => it.desc.isNotEmpty);

              blocks.add(
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = 0; j < cols; j++) ...[
                        if (j > 0) const SizedBox(width: spacing),
                        Expanded(
                          child: j < slice.length
                              ? slice[j].tile
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              );

              if (hasDesc) {
                blocks.add(const SizedBox(height: 12));
                blocks.add(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var j = 0; j < cols; j++) ...[
                        if (j > 0) const SizedBox(width: spacing),
                        Expanded(
                          child: (j < slice.length && slice[j].desc.isNotEmpty)
                              ? Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: _Descriptions(
                                    features: slice[j].desc,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                );
              }
              blocks.add(const SizedBox(height: 24));
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.t('hubKicker').toUpperCase(),
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                color: scheme.onSurfaceVariant,
                                letterSpacing: 1.5,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          strings.t('hubTitle'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  ...blocks,
                ],
              ),
            );
          },
        ),
      ),
      ],
    ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final String? iconAsset;
  final IconData? icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onShortcut;
  final String? shortcutTooltip;
  final bool shortcutBusy;
  final bool dimmed;

  const _HubTile({
    this.iconAsset,
    this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onShortcut,
    this.shortcutTooltip,
    this.shortcutBusy = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: InkWell(
          onTap: onTap,
          child: Stack(
            children: [
              if (onTap != null)
                Positioned(
                  top: 14,
                  right: 14,
                  child: Icon(
                    Icons.arrow_outward,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (iconAsset != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          iconAsset!,
                          width: 76,
                          height: 76,
                          fit: BoxFit.cover,
                        ),
                      )
                    else if (icon != null)
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(icon, size: 34, color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (onShortcut != null)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Tooltip(
                    message: shortcutTooltip ?? '',
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: scheme.surface,
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      icon: shortcutBusy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_link, size: 18),
                      onPressed: shortcutBusy ? null : onShortcut,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Descriptions extends StatelessWidget {
  final List<_Feature> features;

  const _Descriptions({required this.features});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in features) _FeatureBadge(feature: f),
      ],
    );
  }
}

class _Feature {
  final IconData icon;
  final String label;

  const _Feature(this.icon, this.label);
}

class _FeatureBadge extends StatelessWidget {
  final _Feature feature;

  const _FeatureBadge({required this.feature});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(feature.icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            feature.label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubBackdrop extends StatelessWidget {
  const _HubBackdrop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            top: 120,
            right: 96,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.tertiary.withValues(alpha: 0.25),
                  width: 3,
                ),
              ),
            ),
          ),
          Positioned(
            top: 178,
            right: 26,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiary.withValues(alpha: 0.5),
              ),
            ),
          ),
          Positioned(
            bottom: 70,
            left: -30,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.secondary.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 150,
            left: 36,
            child: Transform.rotate(
              angle: 0.4,
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: scheme.primary.withValues(alpha: 0.10),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            right: 80,
            child: Transform.rotate(
              angle: 0.7,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  color: scheme.secondary.withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}