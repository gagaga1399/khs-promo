import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

/// Палитра акцентов для карточек трекеров — чтоб вкладка не была «двухцветной».
const trackerAccentPalette = <Color>[
  Color(0xFFEF5350), // красный
  Color(0xFFFB8C00), // оранжевый
  Color(0xFFF9A825), // жёлтый
  Color(0xFF66BB6A), // зелёный
  Color(0xFF26A69A), // бирюзовый
  Color(0xFF42A5F5), // синий
  Color(0xFF5C6BC0), // индиго
  Color(0xFFAB47BC), // фиолетовый
  Color(0xFFEC407A), // розовый
  Color(0xFF8D6E63), // коричневый
  Color(0xFF26C6DA), // голубой
];

/// Стабильный акцент для строки/привычки — по имени свойства: одно и то же
/// свойство всегда одного цвета, соседние — разные.
Color trackerAccent(String key) {
  var hash = 0;
  for (final unit in key.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return trackerAccentPalette[hash % trackerAccentPalette.length];
}

/// Мягкая подложка под акцентный цвет (иконка/бейдж на карточке).
Color trackerAccentSoft(Color accent) => accent.withValues(alpha: 0.15);

/// Общий акцент раздела «Трекеры» — своя настройка, независимая от хаба.
/// Заменяет `scheme.primary` во всех виджетах трекеров.
Color trackerBaseAccent(BuildContext context) =>
    context.watch<AppState>().trackerAccent;

/// Мягкая подложка общего акцента трекеров.
Color trackerBaseAccentSoft(BuildContext context) =>
    trackerBaseAccent(context).withValues(alpha: 0.15);

/// Метрики-оценки 0–100 («продуктивность», «самоощущение»), которые красятся
/// по величине: до 50 — красные оттенки, от 50 — зелёные.
const Set<String> kScoreMetricNames = {'продуктивность', 'самоощущение'};

bool isScoreMetric(String name) =>
    kScoreMetricNames.contains(name.trim().toLowerCase());

/// Цвет оценки 0–100: до 50 — красный (чем ниже, тем насыщеннее), от 50 —
/// зелёный (чем выше, тем насыщеннее). Оттенки внутри диапазона различаются.
Color metricScoreColor(num value) {
  final v = value.clamp(0, 100).toDouble();
  if (v < 50) {
    return Color.lerp(
      const Color(0xFF9B1C1C),
      const Color(0xFFF87171),
      v / 50.0,
    )!;
  }
  return Color.lerp(
    const Color(0xFF4ADE80),
    const Color(0xFF15803D),
    (v - 50) / 50.0,
  )!;
}
