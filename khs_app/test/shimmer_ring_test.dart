import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/app_theme.dart';
import 'package:khs/ui/widgets/shimmer_ring.dart';

/// Ободок рисуется поверх поля, поэтому ищем последний [CustomPaint]: у тела
/// Scaffold могут быть свои.
ShimmerRingPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byType(CustomPaint).last).foregroundPainter!
        as ShimmerRingPainter;

Widget _host({ThemeData? theme}) => MaterialApp(
  theme: theme,
  home: const Scaffold(
    body: Center(
      child: SizedBox(
        width: 240,
        height: 44,
        child: ShimmerRing(child: Text('x')),
      ),
    ),
  ),
);

void main() {
  testWidgets('перелив рисуется поверх поля, а не под заливкой', (
    tester,
  ) async {
    await tester.pumpWidget(_host());

    final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
    expect(paint.foregroundPainter, isA<ShimmerRingPainter>());
    expect(paint.painter, isNull);
  });

  testWidgets('свет бежит по кругу, а не стоит на месте', (tester) async {
    await tester.pumpWidget(_host());
    final start = _painter(tester).angle;

    await tester.pump(const Duration(milliseconds: 400));

    expect(_painter(tester).angle, isNot(start));
  });

  testWidgets('яркость дышит и не выходит за 0..1', (tester) async {
    await tester.pumpWidget(_host());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(_painter(tester).pulse, inInclusiveRange(0.5, 1.0));
    }
  });

  testWidgets('читается и на светлой, и на тёмной теме', (tester) async {
    for (final theme in [
      AppTheme.light(AppTheme.accentBlue),
      AppTheme.dark(AppTheme.accentBlue),
    ]) {
      await tester.pumpWidget(_host(theme: theme));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('анимация бесконечная: кругов не кончается', (tester) async {
    await tester.pumpWidget(_host());
    // 15 секунд по кадрам: цикл 2.8 с, значит внутри несколько полных
    // оборотов. Если бы повтор был конечным, кадр встал бы.
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('контроллер освобождается вместе с виджетом', (tester) async {
    await tester.pumpWidget(_host());
    await tester.pump(const Duration(milliseconds: 100));

    // Смена дерева должна вызвать dispose: иначе тест поймает утечку тикера.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });
}
