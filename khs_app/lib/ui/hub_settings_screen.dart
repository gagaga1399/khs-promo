import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../services/releases.dart';
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