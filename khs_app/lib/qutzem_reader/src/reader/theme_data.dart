import 'package:flutter/material.dart';

enum ReaderTheme { auto, dark, light, sepia, eink }

extension ReaderThemeExt on ReaderTheme {
  String get label {
    switch (this) {
      case ReaderTheme.auto:
        return 'Авто';
      case ReaderTheme.dark:
        return 'Тёмная';
      case ReaderTheme.light:
        return 'Светлая';
      case ReaderTheme.sepia:
        return 'Сепия';
      case ReaderTheme.eink:
        return 'E-ink';
    }
  }

  static ReaderTheme fromName(String? name) {
    return ReaderTheme.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ReaderTheme.auto,
    );
  }
}

class ReaderColors {
  final Color background;
  final Color text;
  final Color ui;
  final Color border;
  final Color accent;
  final Color muted;

  const ReaderColors({
    required this.background,
    required this.text,
    required this.ui,
    required this.border,
    required this.accent,
    required this.muted,
  });
}

const Map<ReaderTheme, ReaderColors> readerThemeColors = {
  ReaderTheme.dark: ReaderColors(
    background: Color(0xFF191919),
    text: Color(0xFFD8D8D8),
    ui: Color(0xFF232323),
    border: Color(0xFF333333),
    accent: Color(0xFF8AB4F8),
    muted: Color(0xFF9A9A9A),
  ),
  ReaderTheme.light: ReaderColors(
    background: Color(0xFFFAFAFA),
    text: Color(0xFF1F1F1F),
    ui: Color(0xFFFFFFFF),
    border: Color(0xFFE0E0E0),
    accent: Color(0xFF1A73E8),
    muted: Color(0xFF757575),
  ),
  ReaderTheme.sepia: ReaderColors(
    background: Color(0xFFF5EBDD),
    text: Color(0xFF4A3B2A),
    ui: Color(0xFFEFE2D0),
    border: Color(0xFFD8C9B4),
    accent: Color(0xFFA0703C),
    muted: Color(0xFF8A7A66),
  ),
  ReaderTheme.eink: ReaderColors(
    background: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    ui: Color(0xFFFFFFFF),
    border: Color(0xFF000000),
    accent: Color(0xFF000000),
    muted: Color(0xFF555555),
  ),
};

ReaderColors? resolveThemeColors(BuildContext context, ReaderTheme theme) {
  if (theme == ReaderTheme.auto) {
    final brightness = Theme.of(context).brightness;
    return readerThemeColors[
        brightness == Brightness.dark ? ReaderTheme.dark : ReaderTheme.light];
  }
  return readerThemeColors[theme];
}

const double readerMinFont = 12;
const double readerMaxFont = 34;

class ParagraphStyle {
  final bool isHeading;
  final bool isPageBreak;
  const ParagraphStyle({this.isHeading = false, this.isPageBreak = false});
}
