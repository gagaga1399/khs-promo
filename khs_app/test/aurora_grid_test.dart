import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/app_theme.dart';
import 'package:khs/ui/widgets/aurora_grid.dart';

/// Контроллер внутри [AuroraGrid] свой, поэтому в тестах он и не нужен: виджет
/// освобождает его в dispose сам. Проверять движение декора можно по фазе
/// painter'ов: если бы анимация не шла, фаза осталась бы на нуле.
Widget _host({
  ThemeData? theme,
  Color accent = AppTheme.accentBlue,
  Widget? child,
}) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        height: 240,
        child: AuroraGrid(accent: accent, child: child ?? const Text('сетка')),
      ),
    ),
  ),
);

/// Оба слоя AuroraGrid лежат в painter (блик рисуется мимо сетки и клипается
/// по скруглению), а не в foregroundPainter.
final _painters = find.byType(CustomPaint);

AuroraFrontPainter _front(WidgetTester tester) => tester
    .widgetList<CustomPaint>(_painters)
    .map((p) => p.painter)
    .whereType<AuroraFrontPainter>()
    .single;

AuroraBackPainter _back(WidgetTester tester) => tester
    .widgetList<CustomPaint>(_painters)
    .map((p) => p.painter)
    .whereType<AuroraBackPainter>()
    .single;

void main() {
  testWidgets('оба слоя декора на месте', (tester) async {
    await tester.pumpWidget(_host());

    expect(_back(tester).accent, AppTheme.accentBlue);
    expect(_front(tester).radius, 18);
    expect(tester.takeException(), isNull);
  });

  testWidgets('фаза идёт: декор не застывает', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 200));
    final backT0 = _back(tester).t;
    final frontT0 = _front(tester).t;

    await tester.pump(const Duration(seconds: 3));

    expect(_back(tester).t, isNot(backT0));
    expect(_front(tester).t, isNot(frontT0));
  });

  testWidgets('фаза ходит по кругу, а не уезжает за 1', (tester) async {
    await tester.pumpWidget(_host());
    final seen = <double>{};
    // 14 секунд при цикле 12 — почти полный круг плюс заход за ноль.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      seen.add(_back(tester).t);
    }
    expect(seen.every((v) => v >= 0 && v <= 1), isTrue);
    expect(seen.length, greaterThan(5));
  });

  testWidgets('содержимое не перестраивается каждый кадр', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      _host(
        child: Builder(
          builder: (_) {
            builds++;
            return const Text('сетка');
          },
        ),
      ),
    );
    final afterMount = builds;

    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(builds, afterMount);
  });

  testWidgets('сияние берёт переданный цвет, а не дефолтный синий', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        theme: AppTheme.dark(AppTheme.accentOrange),
        accent: AppTheme.accentOrange,
      ),
    );

    expect(_back(tester).accent, AppTheme.accentOrange);
  });

  testWidgets('рисуется в обеих темах без ошибок', (tester) async {
    for (final theme in [
      AppTheme.light(AppTheme.accentBlue),
      AppTheme.dark(AppTheme.accentBlue),
    ]) {
      await tester.pumpWidget(_host(theme: theme));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('панель не раздувается и декор не вылезает наружу', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.getSize(find.byType(AuroraGrid)).width, 320);
    expect(tester.getSize(find.byType(AuroraGrid)).height, 240);
    expect(tester.takeException(), isNull);
  });

  testWidgets('контроллер освобождается при смене дерева', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 100));

    // Виджет с бесконечной анимацией обязан уметь уйти в dispose: если бы
    // тикер не освобождался, тест упал бы с «A Ticker was active at the end».
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
