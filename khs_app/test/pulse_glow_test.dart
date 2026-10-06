import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/app_theme.dart';
import 'package:khs/ui/widgets/pulse_glow.dart';

/// Свечение рисуется поверх содержимого, поэтому берём последний [CustomPaint].
PulseGlowPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(find.byType(CustomPaint).last).foregroundPainter!
        as PulseGlowPainter;

Widget _glow(Animation<double> pulse, {double min = 0.08, double max = 0.28}) =>
    PulseGlow(
      animation: pulse,
      min: min,
      max: max,
      child: const SizedBox(width: 38, height: 38),
    );

/// Контроллер создаётся внутри теста и обязательно с [AnimationController.repeat]:
/// без повтора он стоит на нуле, синус всегда даёт 0.5, прозрачность не
/// меняется — и проверка прошла бы вхолостую. Создавать его в setUp нельзя:
/// тикер запустился бы до первого кадра и остался висеть после разбора дерева,
/// а `addTearDown(dispose)` срабатывает слишком поздно — «A Ticker was active at
/// the end of the test». Поэтому dispose() стоит последним предложением тела.
AnimationController _breathing(WidgetTester tester) => AnimationController(
  vsync: tester,
  duration: const Duration(milliseconds: 2600),
)..repeat();

void main() {
  testWidgets('прозрачность дышит, а не стоит', (tester) async {
    final pulse = _breathing(tester);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _glow(pulse))));
    final start = _painter(tester).alpha;

    await tester.pump(const Duration(milliseconds: 650));

    expect(_painter(tester).alpha, isNot(start));
    pulse.dispose();
  });

  testWidgets('дыхание не выходит за заданные границы', (tester) async {
    final pulse = _breathing(tester);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: _glow(pulse, min: 0.08, max: 0.28))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 90));
      expect(_painter(tester).alpha, inInclusiveRange(0.08, 0.28));
    }
    pulse.dispose();
  });

  testWidgets('пять ячеек делят один контроллер', (tester) async {
    final pulse = _breathing(tester);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(children: [for (var i = 0; i < 5; i++) _glow(pulse)]),
        ),
      ),
    );
    final start = _painter(tester).alpha;

    await tester.pump(const Duration(milliseconds: 400));

    final paints = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .where((p) => p.foregroundPainter is PulseGlowPainter)
        .toList();
    expect(paints, hasLength(5));
    // Тикер один на все ячейки, и он двигает их все сразу.
    expect(_painter(tester).alpha, isNot(start));
    pulse.dispose();
  });

  testWidgets('рисуется без ошибок в обеих темах', (tester) async {
    for (final theme in [
      AppTheme.light(AppTheme.accentBlue),
      AppTheme.dark(AppTheme.accentBlue),
    ]) {
      final pulse = _breathing(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(body: _glow(pulse)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      pulse.dispose();
    }
  });
}
