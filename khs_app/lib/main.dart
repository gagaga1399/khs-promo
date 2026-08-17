import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/khs_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // Прячем системную панель телефона (жест-бар внизу) — сама всплывает
    // при свайпе и снова убирается. На Windows/desktop не трогаем.
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
  await initializeDateFormatting('ru');
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const KhsApp()));
}
