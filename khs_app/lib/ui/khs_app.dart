import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:provider/provider.dart';

import '../services/launcher_shortcut.dart';
import '../state/app_state.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'hub_screen.dart';
import 'splash_screen.dart';

class KhsApp extends StatelessWidget {
  const KhsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final locale = state.isRussian ? 'ru' : 'en';
    final directTasks =
        Platform.environment['KHS_START_TASKS'] == '1' ||
            LauncherShortcut.startTasks;
    return MaterialApp(
      title: state.strings.t('appTitle'),
      debugShowCheckedModeBanner: false,
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      themeMode: state.resolvedThemeMode,
      theme: AppTheme.light(state.accentColor),
      darkTheme: state.themeMode == 'custom'
          ? AppTheme.custom(state.accentColor, state.customTextColor)
          : AppTheme.dark(state.accentColor),
      home: directTasks
          ? const HomeScreen()
          : (state.showSplashAnimation
              ? const SplashGate()
              : const HubScreen()),
    );
  }
}
