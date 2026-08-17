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
}
