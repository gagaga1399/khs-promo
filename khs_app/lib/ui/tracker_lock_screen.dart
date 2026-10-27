import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'hub_settings_screen.dart';

/// Экран блокировки раздела «Трекеры»: показывается, пока не введён ключ
/// лицензии. Отсюда можно перейти в настройки хаба и ввести ключ.
class TrackerLockScreen extends StatelessWidget {
  const TrackerLockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final strings = state.strings;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('hubTrackerTile'))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 80, color: scheme.onSurfaceVariant),
              const SizedBox(height: 24),
              Text(
                strings.t('licenseLockedTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.t('licenseLockedHelp'),
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.settings_outlined),
                label: Text(strings.t('openSettings')),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HubSettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
