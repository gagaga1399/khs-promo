import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:khs/ui/app_theme.dart';

void main() {
  test('светлая тема использует «французский серый» фон и тёмный текст', () {
    final theme = AppTheme.light(const Color(0xFF3D7BFD));
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppTheme.lightBackground);
    expect(theme.appBarTheme.backgroundColor, AppTheme.lightBackground);
    expect(theme.colorScheme.onSurface, AppTheme.lightOnSurface);
  });

  test('тёмная тема использует «угольный» фон и светлый текст', () {
    final theme = AppTheme.dark(const Color(0xFF3D7BFD));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, AppTheme.darkBackground);
    expect(theme.appBarTheme.backgroundColor, AppTheme.darkBackground);
    expect(theme.colorScheme.onSurface, AppTheme.darkOnSurface);
  });

  test('акцент применяется как primary в обеих темах', () {
    const seed = Color(0xFFFF8A3D);
    final light = AppTheme.light(seed);
    final dark = AppTheme.dark(seed);
    expect(light.colorScheme.primary, seed);
    expect(dark.colorScheme.primary, seed);
  });

  test('чёрный акцент не сливается с фоном тёмной темы', () {
    // Чёрное на угольном — контраст 1.3: кнопки, рамки и выделение были
    // не видны, пока акцент оставался ровно тем же цветом, что и фон.
    final theme = AppTheme.dark(Colors.black);
    expect(
      AppTheme.contrast(theme.colorScheme.primary, theme.scaffoldBackgroundColor),
      greaterThanOrEqualTo(3),
    );
    expect(
      AppTheme.contrast(theme.scaffoldBackgroundColor, theme.colorScheme.primary),
      greaterThanOrEqualTo(3),
    );
  });

  test('белый акцент не сливается с фоном светлой темы', () {
    final theme = AppTheme.light(Colors.white);
    expect(
      AppTheme.contrast(
        theme.colorScheme.primary,
        theme.scaffoldBackgroundColor,
      ),
      greaterThanOrEqualTo(3),
    );
  });

  test('кастомная чёрная тема: уровни поверхности и текст разведены', () {
    final theme = AppTheme.custom(Colors.black, Colors.black);
    final bg = theme.scaffoldBackgroundColor;
    final card = theme.cardTheme.color!;
    final field = theme.colorScheme.surfaceContainerHigh;

    expect(card, isNot(equals(bg)), reason: 'карточка не должна быть фоном');
    expect(field, isNot(equals(card)), reason: 'поле не должно быть карточкой');
    expect(
      AppTheme.contrast(theme.colorScheme.onSurface, bg),
      greaterThanOrEqualTo(4.5),
      reason: 'чёрный текст по чёрному фону не читается',
    );
    expect(
      AppTheme.contrast(theme.colorScheme.primary, bg),
      greaterThanOrEqualTo(3),
      reason: 'кнопки на чёрном фоне должны быть видны',
    );
  });

  test('кастомная белая тема: уровни поверхности уходят вниз от фона', () {
    final theme = AppTheme.custom(Colors.white, Colors.white);
    final bg = theme.scaffoldBackgroundColor;
    final card = theme.cardTheme.color!;

    expect(card, isNot(equals(bg)));
    expect(
      AppTheme.contrast(theme.colorScheme.onSurface, bg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      AppTheme.contrast(theme.colorScheme.primary, bg),
      greaterThanOrEqualTo(3),
    );
  });
}
