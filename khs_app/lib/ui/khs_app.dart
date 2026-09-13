import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'app_theme.dart';
import 'home_screen.dart';
import 'splash_screen.dart';

class KhsApp extends StatelessWidget {
  const KhsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final locale = state.isRussian ? 'ru' : 'en';
    return MaterialApp(
      title: state.strings.t('appTitle'),
      debugShowCheckedModeBanner: false,
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: state.resolvedThemeMode,
      theme: AppTheme.light(state.accentColor),
      darkTheme: state.themeMode == 'custom'
          ? AppTheme.custom(state.accentColor, state.customTextColor)
          : AppTheme.dark(state.accentColor),
      home: state.showSplashAnimation
          ? const SplashGate()
          : const HomeScreen(),
    );
  }
}
