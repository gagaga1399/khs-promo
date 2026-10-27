import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/khs_app.dart';
import 'services/auth_service.dart';
import 'services/launcher_shortcut.dart';
import 'services/tracker_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _applyLaunchArgs();
  if (Platform.isAndroid) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final start = await LauncherShortcut.initialStart();
    if (start != null) LauncherShortcut.startTasks = true;
  }
  // Вход в аккаунт поднимаем параллельно с остальным стартом: без сети
  // приложение всё равно должно открыться, поэтому ждать не блокируемся.
  final authReady = AuthService.instance.start();
  await initializeDateFormatting('ru');
  final state = AppState();
  await state.init();
  final tracker = TrackerService(
    vaultPathProvider: () => state.obsidian.vaultPath,
  );
  unawaited(authReady);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<TrackerService>.value(value: tracker),
      ],
      child: const KhsApp(),
    ),
  );
}

/// Разбор аргументов командной строки для ярлыков рабочего стола.
/// Windows передаёт их через .lnk, поэтому читать `Platform.executableArguments`.
void _applyLaunchArgs() {
  for (final arg in Platform.executableArguments) {
    if (arg == '--tasks') {
      LauncherShortcut.startTasks = true;
    } else if (arg == '--reader') {
      LauncherShortcut.startReader = true;
    } else if (arg == '--tracker') {
      LauncherShortcut.startTracker = true;
    }
  }
}
