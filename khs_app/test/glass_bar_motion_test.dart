import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/glass_bottom_bar.dart';

List<GlassNavItem> _items() => const [
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
  GlassNavItem(icon: Icons.book_outlined, activeIcon: Icons.book, label: 'Три'),
  GlassNavItem(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    label: 'Четыре',
  ),
];

Widget _host({
  required int index,
  required ValueChanged<int> onTap,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: const SizedBox(height: 400),
        bottomNavigationBar: GlassBottomBar(
          currentIndex: index,
          onTap: onTap,
          items: _items(),
        ),
      ),
    ),
  );
}

void main() {
  group('пружина', () {
    test('перелетывает конечную точку и оседает в единице', () {
      final curve = SpringCurve(stiffness: 280, damping: 24);

      // Максимум выше единицы: это и есть перелёт.
      var peak = 0.0;
      for (var i = 0; i <= 200; i++) {
        final v = curve.transform(i / 200);
        if (v > peak) peak = v;
      }
      expect(
        peak,
        greaterThan(1.0),
        reason: 'пружина должна перелетывать цель',
      );
      expect(peak, lessThan(1.15), reason: 'перелёт должен быть коротким');

      // В начале ноль, в конце ровно единица.
      expect(curve.transform(0), closeTo(0, 0.001));
      expect(curve.transform(1), closeTo(1, 0.001));
    });

    test('разгоняется, перелетает цель и оседает без остатка', () {
      final curve = SpringCurve(stiffness: 280, damping: 24);

      var peak = 0.0;
      var peakAt = 0.0;
      for (var i = 0; i <= 200; i++) {
        final t = i / 200;
        final v = curve.transform(t);
        expect(
          v,
          greaterThanOrEqualTo(-0.001),
          reason: 'значение не уходит в минус',
        );
        if (v > peak) {
          peak = v;
          peakAt = t;
        }
      }

      // Перелёт есть и приходится на середину перехода, а не на конец.
      expect(
        peak,
        greaterThan(1.02),
        reason: 'пружина должна перелетывать цель',
      );
      expect(peak, lessThan(1.10), reason: 'перелёт должен быть коротким');
      expect(peakAt, inInclusiveRange(0.2, 0.8));

      // После перелёта пружина возвращается к единице, а не остаётся выше.
      expect(curve.transform(1), closeTo(1, 0.001));
      expect(curve.transform(0.9), lessThan(peak));
    });
  });

  testWidgets('пилюля не выходит за пределы пунктов на перелёте', (
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
                items: _items(),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Позиция пилюли на последнем пункте: от неё считаем вылет за капсулу.
    final pill = find.byKey(kGlassNavPillKey);
    double leftAtLast = 0;
    await tester.tap(find.text('Один'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Четыре'));
    await tester.pumpAndSettle();
    leftAtLast = tester.getTopLeft(pill).dx;

    setter(() => index = 0);
    await tester.pumpAndSettle();
    setter(() => index = 3);
    await tester.pump();

    var maxRight = double.negativeInfinity;
    for (var f = 0; f < 40; f++) {
      await tester.pump(const Duration(milliseconds: 16));
      maxRight = [
        maxRight,
        tester.getTopLeft(pill).dx,
      ].reduce((a, b) => a > b ? a : b);
    }
    await tester.pumpAndSettle();

    // На перелёте пилюля может чуть выйти за последний пункт, но не улететь
    // за капсулу: допуск в 12px — это запас kGlassNavOverflow.
    expect(
      maxRight - leftAtLast,
      lessThanOrEqualTo(13.0),
      reason: 'перелёт не должен выносить пилюлю за капсулу',
    );
  });

  testWidgets('при disableAnimations переход происходит мгновенно', (
    tester,
  ) async {
    int index = 0;
    late StateSetter setter;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: const SizedBox(height: 400),
            bottomNavigationBar: StatefulBuilder(
              builder: (context, setState) {
                setter = setState;
                return GlassBottomBar(
                  currentIndex: index,
                  onTap: (i) => setState(() => index = i),
                  items: _items(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pill = find.byKey(kGlassNavPillKey);
    final atFirst = tester.getTopLeft(pill).dx;

    setter(() => index = 3);
    // Один кадр — и пилюля уже на месте, без промежуточных положений.
    await tester.pump();

    final afterOneFrame = tester.getTopLeft(pill).dx;
    expect(
      afterOneFrame,
      greaterThan(atFirst + 50),
      reason: 'переход должен быть мгновенным, а не анимированным',
    );
    await tester.pumpAndSettle();
    final settled = tester.getTopLeft(pill).dx;
    expect((settled - afterOneFrame).abs(), lessThan(1.0));
  });

  testWidgets('наведение прорисовывает акцент в пункте', (tester) async {
    int index = 0;
    await tester.pumpWidget(_host(index: index, onTap: (i) => index = i));
    await tester.pumpAndSettle();

    // Ищем InkWell пункта, а не MouseRegion: последних в дереве несколько,
    // добавляет сам MaterialApp.
    final item = find.ancestor(
      of: find.text('Два'),
      matching: find.byType(InkWell),
    );
    expect(item, findsOneWidget);

    final accent = Theme.of(tester.element(find.byType(GlassBottomBar)))
        .colorScheme
        .primary;
    Icon iconOf() => tester.widget<Icon>(
      find
          .descendant(
            of: item,
            matching: find.byIcon(Icons.calendar_month_outlined),
          )
          .first,
    );

    expect(
      iconOf().color,
      Colors.black54,
      reason: 'до наведения иконка приглушённая',
    );
    expect(
      find.byKey(Key('${kGlassNavWipeKeyPrefix}1')),
      findsNothing,
      reason: 'до наведения слоя прорисовки нет вовсе',
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Два')));

    // В середине анимации прорисовка едет: маска уже в дереве.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(
      find.byKey(Key('${kGlassNavWipeKeyPrefix}1')),
      findsOneWidget,
      reason: 'во время наведения акцент прорисовывается по диагонали',
    );

    await tester.pumpAndSettle();
    expect(
      iconOf().color,
      accent,
      reason: 'после наведения иконка становится акцентной',
    );
    expect(
      find.byKey(Key('${kGlassNavWipeKeyPrefix}1')),
      findsNothing,
      reason: 'прорисовка завершилась, временный слой убран',
    );

    // Уход курсора возвращает приглушённый цвет.
    await gesture.removePointer();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(iconOf().color, Colors.black54);
  });
}
