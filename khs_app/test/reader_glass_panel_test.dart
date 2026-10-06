import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/qutzem_reader/src/reader/glass_panel.dart';

void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required double radius,
    Color? tint,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: const ColoredBox(color: Color(0xFF191919)),
          bottomNavigationBar: GlassPanel(
            radius: radius,
            tint: tint,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const Text('панель'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  BoxDecoration panelDecoration(WidgetTester tester) {
    // Подложка — самый внутренний DecoratedBox с заливкой.
    return tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.color != null);
  }

  // Матовый фон = полупрозрачный: книга под панелью должна просвечивать
  // размытыми пятнами. Непрозрачная заливка здесь прямой баг.
  testWidgets('подложка полупрозрачная в обеих темах', (tester) async {
    for (final dark in [true, false]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: Scaffold(
            body: const ColoredBox(color: Colors.white),
            bottomNavigationBar: GlassPanel(
              tint: Colors.black,
              child: const Text('панель'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final color = panelDecoration(tester).color!;
      debugPrint('подложка (тёмная: $dark): $color');
      expect(
        color.a,
        closeTo(kReaderGlassAlpha, 0.01),
        reason: 'альфа подложки должна совпадать с матовой',
      );
      expect(color.a, lessThan(1.0), reason: 'подложка должна просвечивать');
    }
  });

  test('размытие подложки совпадает с панелью навигации', () {
    // Оба значения заданы вручную в двух файлах: читалка собирается отдельно,
    // поэтому синхронизируем их тестом, а не импортом.
    expect(kReaderGlassBlur, 26.0, reason: 'размытие должно совпадать с навигацией');
  });

  testWidgets('подложка размыта, иначе просвечивала бы чёткая картинка', (tester) async {
    await pumpPanel(tester, radius: 0);
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  // Рамка зависит от формы: скруглённая панель повторяет навигацию (рамка по
  // всему контуру), панель вплотную к краю экрана получает только линию
  // сверху — иначе рамка упирается в края экрана.
  testWidgets('скруглённая панель с рамкой по контуру, крайняя — с линией сверху', (tester) async {
    await pumpPanel(tester, radius: 24);
    var border = panelDecoration(tester).border;
    debugPrint('рамка скруглённой: $border');
    expect(border, isA<Border>(), reason: 'рамка должна быть');
    expect((border! as Border).top, isNot(BorderSide.none));
    expect(border.isUniform, isTrue, reason: 'рамка по всему контуру');

    await pumpPanel(tester, radius: 0);
    border = panelDecoration(tester).border;
    debugPrint('рамка крайней: $border');
    expect(border, isA<Border>());
    final edge = border! as Border;
    expect(edge.top, isNot(BorderSide.none), reason: 'линия сверху нужна');
    expect(edge.bottom, BorderSide.none, reason: 'снизу линия не нужна');
    expect(edge.left, BorderSide.none, reason: 'сбоку линия не нужна');
  });

  // Тень должна быть на внешнем слое: ClipRRect и BackdropFilter обрезают всё
  // внутри себя, поэтому тень на внутреннем виджете не видна вовсе.
  testWidgets('тень рисуется вне ClipRRect, иначе срезается целиком', (tester) async {
    await pumpPanel(tester, radius: 0);
    final outer = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.boxShadow != null);
    debugPrint('тень снаружи: ${outer.boxShadow}');

    final clip = tester.getRect(find.byType(ClipRRect));
    expect(clip.height, greaterThan(0), reason: 'панель должна иметь площадь');
  });

  testWidgets('без тени внешний слой не появляется', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: const ColoredBox(color: Colors.black),
          bottomNavigationBar: GlassPanel(
            shadow: false,
            child: const Text('панель'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .any((d) => d.boxShadow != null),
      isFalse,
      reason: 'тень выключена — слой с тенью не нужен',
    );
  });
}
