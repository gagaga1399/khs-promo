import 'package:flutter_test/flutter_test.dart';

import 'package:khs/ui/tracker_accent.dart';

void main() {
  group('trackerAccent', () {
    test('стабилен: одно и то же имя всегда одного цвета', () {
      const names = ['чтение', 'продуктивность', 'сон с 22:30', 'какой-то ключ'];
      for (final name in names) {
        expect(trackerAccent(name), trackerAccent(name));
        expect(trackerAccent(name), trackerAccent(name));
      }
    });

    test('соседние свойста не выглядят одинаково в палитре из 11 цветов', () {
      const names = [
        'чтение',
        'тренировка',
        'творог',
        'зарядка',
        'сон с 22:30',
        'Английский',
        'подготовка',
        'бег',
        'желание действовать',
        'продуктивность',
        'самоощущение',
        'русский',
      ];
      final colors = {for (final n in names) trackerAccent(n)};
      expect(colors.length, greaterThanOrEqualTo(8),
          reason: '11 привычек/метрик должны давать разнообразие, а не 1-2 цвета');
    });

    test('все цвета берутся из палитры', () {
      for (var i = 0; i < 40; i++) {
        expect(
          trackerAccentPalette,
          contains(trackerAccent('свойство №$i')),
        );
      }
    });
  });
}