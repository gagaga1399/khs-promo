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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  unawaited(authReady);

  runApp(
    ChangeNotifierProvider.value(value: state, child: const KhsApp()),
  );
}
