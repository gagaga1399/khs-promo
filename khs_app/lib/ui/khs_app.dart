import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'app_theme.dart';
import 'home_screen.dart';

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
      themeMode: state.isDarkTheme ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.light(state.accentColor),
      darkTheme: AppTheme.dark(state.accentColor),
      home: const HomeScreen(),
    );
  }
}
