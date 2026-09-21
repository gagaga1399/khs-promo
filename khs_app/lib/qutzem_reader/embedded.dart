import 'package:flutter/material.dart';

import 'src/screens/home_screen.dart';

/// Встроенная в хаб читалка (Android): открывается внутри KHS, как KHS Tasks.
/// Шапка с кнопкой «назад», внутри — главный экран читалки с вкладками внизу.
class ReaderHome extends StatelessWidget {
  const ReaderHome({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: _readerTheme(dark),
      child: Builder(
        builder: (ctx) {
          final scheme = Theme.of(ctx).colorScheme;
          return Scaffold(
            backgroundColor: scheme.surface,
            body: Column(
              children: [
                Material(
                  color: scheme.surfaceContainerLow,
                  child: SafeArea(
                    bottom: false,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: MaterialLocalizations.of(ctx).backButtonTooltip,
                          onPressed: () => Navigator.of(ctx).maybePop(),
                        ),
                        Text(
                          'QutZem Reader',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                ),
                const Expanded(child: HomeScreen()),
              ],
            ),
          );
        },
      ),
    );
  }

  static ThemeData _readerTheme(bool dark) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5B3A8E),
      brightness: dark ? Brightness.dark : Brightness.light,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(backgroundColor: scheme.surfaceContainerLow),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
      ),
    );
  }
}