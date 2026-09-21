import 'package:flutter/widgets.dart';

/// Ограниченный масштаб системного шрифта для читалки.
///
/// Встроенные ридеры используют свой кегль (12–34), поэтому огромный
/// системный «размер шрифта» из настроек доступности Android/Windows
/// не должен умножаться поверх вёрстки — иначе страницы «рассыпаются»
/// (по одному слову в строку) и разъезжаются с пагинатором.
TextScaler readerTextScaler(BuildContext context, {double max = 1.15}) {
  final raw = MediaQuery.textScalerOf(context);
  final k = (raw.scale(16) / 16).clamp(0.9, max);
  return TextScaler.linear(k);
}