import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/glass_bottom_bar.dart';

void main() {
  testWidgets('пилюля перелетает цель по пружине, не телепортируясь', (
    tester,
  ) async {
    int index = 0;
    late StateSetter setter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(height: 400),
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) {
              setter = setState;
              return GlassBottomBar(
                currentIndex: index,
                onTap: (i) => setState(() => index = i),
                items: const [
                  GlassNavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Один',
                  ),
                  GlassNavItem(
                    icon: Icons.calendar_month_outlined,
                    activeIcon: Icons.calendar_month,
                    label: 'Два',
                  ),
                  GlassNavItem(
                    icon: Icons.book_outlined,
                    activeIcon: Icons.book,
                    label: 'Три',
                  ),
                  GlassNavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Четыре',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pill = find.byKey(kGlassNavPillKey);
    final start = tester.getTopLeft(pill).dx;

    // Цель — средний пункт: у края перелёт срезается ограничением диапазона,
    // и перелёт видно только в середине панели.
    setter(() => index = 2);
    await tester.pumpAndSettle();
    final target = tester.getTopLeft(pill).dx;
    expect(
      target,
      greaterThan(start + 100),
      reason: 'переход через два пункта',
    );

    // Тот же переход, но покадрово.
    setter(() => index = 0);
    await tester.pumpAndSettle();
    setter(() => index = 2);
    await tester.pump();

    // Первый кадр после нажатия — это телепорт, если пилюля уже у цели.
    final firstFrame = tester.getTopLeft(pill).dx;
    expect(
      (firstFrame - target).abs(),
      greaterThan((target - start) * 0.5),
      reason: 'после первого кадра пилюля ещё должна быть в пути',
    );

    final samples = <double>[];
    final overshoots = <String>[];
    var peak = start;
    var maxStep = 0.0;
    var prev = firstFrame;
    for (var frame = 0; frame < 60; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final x = tester.getTopLeft(pill).dx;
      samples.add(x);
      maxStep = [maxStep, (x - prev).abs()].reduce((a, b) => a > b ? a : b);
      if (x > peak) {
        peak = x;
      } else if (prev > target && prev - x > 0.5) {
        // Откат допустим только после перелёта и только в осаждении.
        overshoots.add(
          'кадр $frame: ${prev.toStringAsFixed(1)} -> ${x.toStringAsFixed(1)}',
        );
      }
      prev = x;
    }
    await tester.pumpAndSettle();

    debugPrint(
      'старт: ${start.toStringAsFixed(2)} цель: ${target.toStringAsFixed(2)}',
    );
    debugPrint('пик: ${peak.toStringAsFixed(2)}');
    debugPrint(
      'выборки: ${samples.map((e) => e.toStringAsFixed(1)).join(' ')}',
    );
    debugPrint('максимальный шаг кадра: ${maxStep.toStringAsFixed(1)}');
    debugPrint('откаты после перелёта: ${overshoots.length}');

    // Пружина перелетает цель, но коротко.
    expect(peak, greaterThan(target), reason: 'пружина должна перелететь цель');
    expect(
      peak - target,
      lessThanOrEqualTo(13.0),
      reason: 'перелёт должен остаться в пределах капсулы',
    );

    // Откат назад — это осаждение пружины, а не возврат к прежнему пункту.
    expect(
      prev,
      closeTo(target, 1.0),
      reason: 'в конце пилюля должна осесть ровно на цели',
    );

    // Ни один кадр не перемещает пилюлю через всю панель: это был бы скачок.
    expect(
      maxStep,
      lessThan((target - start) * 0.8),
      reason: 'ни один кадр не должен протаскивать пилюлю через всю ширину',
    );
  });

  // Переход, прерванный на лету: пилюля уже едет к последнему пункту, и
  // пользователь жмёт назад. Анимация стартует заново, и пилюля не должна
  // скачком возвращаться к прежнему пункту.
  testWidgets('пилюля не скачет при прерывании перехода', (tester) async {
    int index = 0;
    late StateSetter setter;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(height: 400),
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) {
              setter = setState;
              return GlassBottomBar(
                currentIndex: index,
                onTap: (i) => setState(() => index = i),
                items: const [
                  GlassNavItem(
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Один',
                  ),
                  GlassNavItem(
                    icon: Icons.calendar_month_outlined,
                    activeIcon: Icons.calendar_month,
                    label: 'Два',
                  ),
                  GlassNavItem(
                    icon: Icons.book_outlined,
                    activeIcon: Icons.book,
                    label: 'Три',
                  ),
                  GlassNavItem(
                    icon: Icons.settings_outlined,
                    activeIcon: Icons.settings,
                    label: 'Четыре',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pill = find.byKey(kGlassNavPillKey);

    setter(() => index = 3);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final beforeInterrupt = tester.getTopLeft(pill).dx;

    // Прерываем на лету.
    setter(() => index = 1);
    await tester.pump();
    final afterInterrupt = tester.getTopLeft(pill).dx;

    final jumps = <String>[];
    var prev = afterInterrupt;
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final x = tester.getTopLeft(pill).dx;
      if ((x - prev).abs() > 0.5 && prev > afterInterrupt + 1) {
        jumps.add('кадр $frame: $prev -> $x');
      }
      prev = x;
    }

    debugPrint('ДО прерывания: ${beforeInterrupt.toStringAsFixed(1)}');
    debugPrint('СРАЗУ ПОСЛЕ:   ${afterInterrupt.toStringAsFixed(1)}');
    debugPrint('откаты: ${jumps.length}');
    for (final j in jumps.take(8)) {
      debugPrint('  $j');
    }

    // Пилюля была по дороге к 4-му пункту и должна продолжить движение к 2-му,
    // а не прыгнуть назад к прежней цели. Смещение в момент прерывания —
    // меньше пикселя, то есть пилюля продолжает движение без разрыва.
    expect(
      (afterInterrupt - beforeInterrupt).abs(),
      lessThan(1.0),
      reason: 'пилюля не должна телепортироваться при прерывании',
    );
  });
}
