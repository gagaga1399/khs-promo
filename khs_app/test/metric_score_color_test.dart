import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/tracker_accent.dart';

void main() {
  test('isScoreMetric распознаёт продуктивность и самоощущение', () {
    expect(isScoreMetric('продуктивность'), isTrue);
    expect(isScoreMetric('Продуктивность'), isTrue);
    expect(isScoreMetric(' самоощущение '), isTrue);
    expect(isScoreMetric('вес'), isFalse);
    expect(isScoreMetric(''), isFalse);
  });

  test('metricScoreColor: до 50 красный, от 50 зелёный', () {
    expect(metricScoreColor(0).r, greaterThan(metricScoreColor(0).g));
    expect(metricScoreColor(25).r, greaterThan(metricScoreColor(25).g));
    expect(metricScoreColor(49).r, greaterThan(metricScoreColor(49).g));
    expect(metricScoreColor(50).g, greaterThan(metricScoreColor(50).r));
    expect(metricScoreColor(75).g, greaterThan(metricScoreColor(75).r));
    expect(metricScoreColor(100).g, greaterThan(metricScoreColor(100).r));
  });

  test('оттенки внутри диапазонов различаются', () {
    expect(metricScoreColor(0), isNot(equals(metricScoreColor(25))));
    expect(metricScoreColor(25), isNot(equals(metricScoreColor(49))));
    expect(metricScoreColor(50), isNot(equals(metricScoreColor(75))));
    expect(metricScoreColor(75), isNot(equals(metricScoreColor(100))));
  });

  test('значения вне диапазона ограничиваются 0–100', () {
    expect(metricScoreColor(-10), metricScoreColor(0));
    expect(metricScoreColor(150), metricScoreColor(100));
  });
}
