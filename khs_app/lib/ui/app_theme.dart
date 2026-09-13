import 'package:flutter/material.dart';

/// Дизайн-токены приложения KHS.
///
/// Здесь собраны все цвета, скругления, размеры шрифтов и отступы.
/// Меняй значения в этом файле и сохраняй — приложение сразу перестроится
/// (в терминале с `flutter run` сработает hot reload).
class AppTheme {
  // ---------- СВЕТЛАЯ ТЕМА («французский серый») ----------
  static const Color lightBackground = Color(0xFFC8C5B7);
  static const Color lightSurface = Color(0xFFD8D6CB);
  static const Color lightSurfaceHigh = Color(0xFFE6E4DA);
  static const Color lightOnSurface = Color(0xFF1F1F1F);
  static const Color lightOnSurfaceMuted = Color(0xFF6E6C62);
  static const Color lightDivider = Color(0xFFB3B0A4);
  static const Color lightError = Color(0xFFC62828);

  // ---------- ТЁМНАЯ ТЕМА («угольный») ----------
  static const Color darkBackground = Color(0xFF2A2A2A);
  static const Color darkSurface = Color(0xFF353535);
  static const Color darkSurfaceHigh = Color(0xFF424242);
  static const Color darkOnSurface = Color(0xFFF5F5F5);
  static const Color darkOnSurfaceMuted = Color(0xFF9E9E9E);
  static const Color darkDivider = Color(0xFF474747);
  static const Color darkError = Color(0xFFEF5350);

  // ---------- ОБЩИЕ ----------
  static const Color defaultAccent = Color(
    0xFF3D7BFD,
  ); // акцент по умолчанию (синий)
  static const Color onPrimary = Color(0xFFFFFFFF); // текст на акцентном

  // ---------- СКРУГЛЕНИЯ ----------
  static const double radiusCard = 20; // карточки
  static const double radiusField = 16; // поля ввода
  static const double radiusButton = 28; // кнопки (сильно закруглённые)
  static const double radiusChip = 12; // чипы дней

  // ---------- ШРИФТЫ ----------
  static const double fontSizeTitle = 20;
  static const double fontSizeBody = 16;
  static const double fontSizeSmall = 12;

  // ---------- ОТСТУПЫ ----------
  static const double spacing = 16;

  // ---------- ПАЛИТРА ДАШБОРДА ----------
  // Акцентные цвета групп/проектов (референс: синий, оранжевый, бирюза).
  static const Color accentBlue = Color(0xFF3D7BFD);
  static const Color accentOrange = Color(0xFFFF8A3D);
  static const Color accentTurquoise = Color(0xFF2DD4BF);
  static const Color accentPurple = Color(0xFFA855F7);
  static const Color accentPink = Color(0xFFFF6164);
  static const Color accentYellow = Color(0xFFFFD166);
  static const Color accentGreen = Color(0xFF34D399);

  static const List<Color> groupPalette = [
    accentBlue,
    accentOrange,
    accentTurquoise,
    accentPurple,
    accentPink,
    accentYellow,
    accentGreen,
  ];

  /// Детерминированный цвет группы по имени (одна и та же группа — один цвет).
  static Color groupColor(String name) {
    if (name.isEmpty) return accentBlue;
    final hash = name.toLowerCase().codeUnits.fold<int>(
      0,
      (h, c) => h * 31 + c,
    );
    return groupPalette[hash.abs() % groupPalette.length];
  }

  /// Светлая тема с заданным акцентным цветом.
  static ThemeData light(Color seed) => _build(
    brightness: Brightness.light,
    seed: seed,
    background: lightBackground,
    surface: lightSurface,
    surfaceHigh: lightSurfaceHigh,
    onSurface: lightOnSurface,
    onSurfaceMuted: lightOnSurfaceMuted,
    divider: lightDivider,
    error: lightError,
  );

  /// Тёмная тема с заданным акцентным цветом (пользователь может сменить его
  /// в настройках на любой цвет палитры).
  static ThemeData dark(Color seed) => _build(
    brightness: Brightness.dark,
    seed: seed,
    background: darkBackground,
    surface: darkSurface,
    surfaceHigh: darkSurfaceHigh,
    onSurface: darkOnSurface,
    onSurfaceMuted: darkOnSurfaceMuted,
    divider: darkDivider,
    error: darkError,
  );

  /// Кастомная тема — все цвета выводятся из seed.
  static ThemeData custom(Color seed, Color textColor) {
    final hsl = HSLColor.fromColor(seed);
    final brightness = hsl.lightness > 0.45 ? Brightness.light : Brightness.dark;

    final onSurfaceMuted = HSLColor.fromColor(textColor)
        .withLightness(0.65)
        .withSaturation(0.3)
        .toColor();
    final divider = hsl
        .withLightness((hsl.lightness * 0.45).clamp(0.2, 0.45))
        .withSaturation(0.15)
        .toColor();
    final surface = hsl.withLightness((hsl.lightness * 1.08).clamp(0.0, 1.0)).toColor();
    final surfaceHigh = hsl.withLightness((hsl.lightness * 1.16).clamp(0.0, 1.0)).toColor();

    return _build(
      brightness: brightness,
      seed: seed,
      background: seed,
      surface: surface,
      surfaceHigh: surfaceHigh,
      onSurface: textColor,
      onSurfaceMuted: onSurfaceMuted,
      divider: divider,
      error: brightness == Brightness.dark ? const Color(0xFFEF5350) : const Color(0xFFC62828),
    );
  }

  static ThemeData _build({
    required Brightness brightness,
    required Color seed,
    required Color background,
    required Color surface,
    required Color surfaceHigh,
    required Color onSurface,
    required Color onSurfaceMuted,
    required Color divider,
    required Color error,
  }) {
    final base = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final accentOn = seed.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    final scheme = base.copyWith(
      primary: seed,
      onPrimary: accentOn,
      secondary: seed,
      onSecondary: accentOn,
      surface: surface,
      onSurface: onSurface,
      error: error,
      onError: onPrimary,
      outline: divider,
      outlineVariant: divider,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
    );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radiusButton),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,

      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: fontSizeTitle,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: onSurface),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: accentOn,
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(
            fontSize: fontSizeBody,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed,
          side: BorderSide(color: seed),
          shape: buttonShape,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: seed, shape: buttonShape),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: accentOn,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusButton)),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
          side: BorderSide(color: divider),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusField),
          borderSide: BorderSide(color: seed, width: 1.5),
        ),
        hintStyle: TextStyle(color: onSurfaceMuted),
        labelStyle: TextStyle(color: onSurfaceMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: spacing,
          vertical: 16,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton),
            ),
          ),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusCard),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceHigh,
        contentTextStyle: TextStyle(color: onSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusField),
        ),
      ),

      dividerTheme: DividerThemeData(color: divider, thickness: 1),

      // Плавные фейды+слайды при переходах между экранами на всех платформах.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: _KhsPageTransitionsBuilder(),
          TargetPlatform.windows: _KhsPageTransitionsBuilder(),
          TargetPlatform.iOS: _KhsPageTransitionsBuilder(),
          TargetPlatform.linux: _KhsPageTransitionsBuilder(),
          TargetPlatform.macOS: _KhsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Переход экрана: лёгкий подъём + фейд (материал, но и на десктопе живой).
class _KhsPageTransitionsBuilder extends PageTransitionsBuilder {
  const _KhsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == Navigator.defaultRouteName ||
        route.isFirst) {
      return child;
    }
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
