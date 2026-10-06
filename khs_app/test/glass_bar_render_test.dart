import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/glass_bottom_bar.dart';

void main() {
  const items = [
    GlassNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'A'),
    GlassNavItem(icon: Icons.calendar_month, activeIcon: Icons.calendar_month, label: 'B'),
    GlassNavItem(icon: Icons.book_outlined, activeIcon: Icons.book, label: 'C'),
    GlassNavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'D'),
  ];

  testWidgets('панель видна в Scaffold и имеет ненулевой размер', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: GlassBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            items: items,
          ),
        ),
      ),
    );
    expect(find.byType(GlassBottomBar), findsOneWidget);

    final bar = tester.getRect(find.byType(GlassBottomBar));
    final screen = tester.getRect(find.byType(Scaffold));
    debugPrint('ПАНЕЛЬ: $bar');
    debugPrint('ЭКРАН:  $screen');

    expect(bar.height, greaterThan(40), reason: 'высота панели');
    expect(bar.width, greaterThan(100), reason: 'ширина панели');
    expect(bar.bottom, closeTo(screen.bottom, 1), reason: 'панель у низа экрана');
  });

  // Именно этот вариант стоит в home_screen: панель поверх содержимого.
  testWidgets('с extendBody панель остаётся у низа, а не по центру', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: GlassBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            items: items,
          ),
        ),
      ),
    );

    final screen = tester.getRect(find.byType(Scaffold));
    // Ищем именно нарисованную капсулу, а не виджет: SafeArea с Pad��ding
    // занимает всю доступную высоту, а сама полоса должна быть внизу.
    final capsule = tester.getRect(find.byKey(kGlassNavCapsuleKey));
    debugPrint('ЭКРАН:   $screen');
    debugPrint('КАПСУЛА: $capsule');
    debugPrint('зазор до низа экрана: ${screen.bottom - capsule.bottom}');

    // Капсула стоит над нижним полем, а не под ним: зазор равен сумме поля и
    // запаса под раздувающуюся пилюлю.
    expect(
      screen.bottom - capsule.bottom,
      closeTo(kGlassNavMarginBottom + kGlassNavOverflow, 1),
      reason: 'капсула должна стоять над нижним полем экрана',
    );
    expect(capsule.height, closeTo(kGlassNavHeight, 1), reason: 'высота капсулы');
  });

  // Панель ниже своего содержимого не должна перекрывать список: под ней
  // есть запас, иначе последний элемент не прокрутится в видимую часть.
  testWidgets('под панелью есть свободное место для содержимого', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: GlassBottomBar(
            currentIndex: 0,
            onTap: (_) {},
            items: items,
          ),
        ),
      ),
    );
    final capsule = tester.getRect(find.byKey(kGlassNavCapsuleKey));
    final screen = tester.getRect(find.byType(Scaffold));
    debugPrint('капсула: $capsule, низ экрана: ${screen.bottom}');
    expect(
      screen.bottom - capsule.bottom,
      greaterThanOrEqualTo(0),
      reason: 'капсула не должна уходить за нижний край окна',
    );
  });

  // Пилюля должна раздуваться во время перехода и выходить за рамку капсулы.
  testWidgets('пилюля раздувается при переходе и выходит за рамку', (tester) async {
    Widget build(int index) => MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            extendBody: true,
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassBottomBar(
              currentIndex: index,
              onTap: (_) {},
              items: items,
            ),
          ),
        );

    await tester.pumpWidget(build(0));
    await tester.pumpAndSettle();

    Rect pillRect() => tester.getRect(find.byKey(kGlassNavPillKey));

    final rest = pillRect();
    debugPrint('ПОКОЙ:   $rest (высота ${rest.height})');

    // Переключаем пункт и смотрим в середине анимации.
    await tester.pumpWidget(build(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));

    final moving = pillRect();
    debugPrint('ПЕРЕХОД: $moving (высота ${moving.height})');

    expect(
      moving.height,
      greaterThan(rest.height + 5),
      reason: 'пилюля должна раздуваться в переходе',
    );

    // Капсула — это SizedBox с высотой панели внутри ClipRRect.
    final capsule = tester.getRect(find.byKey(kGlassNavCapsuleKey));
    debugPrint('КАПСУЛА: $capsule');
    debugPrint(
      'вылет за рамку: сверху ${(capsule.top - moving.top).toStringAsFixed(1)}, '
      'снизу ${(moving.bottom - capsule.bottom).toStringAsFixed(1)}',
    );

    expect(
      moving.top,
      lessThan(capsule.top),
      reason: 'пилюля должна выходить за верхнюю рамку',
    );
    expect(
      moving.bottom,
      greaterThan(capsule.bottom),
      reason: 'пилюля должна выходить за нижнюю рамку',
    );

    await tester.pumpAndSettle();
    final settled = pillRect();
    debugPrint('ОСЕЛО:  $settled');
    expect(
      (settled.height - rest.height).abs(),
      lessThan(1.5),
      reason: 'после перехода пилюля возвращается в исходный размер',
    );
  });

// На телефоне слот уже самой капсулы, и раздувание до 132% превращало
  // пилюлю в вертикальный овал. Ограничение роста высотой слота.
  testWidgets('на узком экране пилюля не вытягивается в овал', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Widget build(int index) => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        extendBody: true,
        body: const SizedBox.expand(),
        bottomNavigationBar: GlassBottomBar(
          currentIndex: index,
          onTap: (_) {},
          items: items,
        ),
      ),
    );

    await tester.pumpWidget(build(0));
    await tester.pumpAndSettle();

    Rect pillRect() => tester.getRect(find.byKey(kGlassNavPillKey));
    final rest = pillRect();
    debugPrint('ТЕЛЕФОН, ПОКОЙ:   $rest (${rest.width}×${rest.height})');

    var worst = 0.0;
    for (var index = 1; index < 4; index++) {
      await tester.pumpWidget(build(index));
      await tester.pump();
      // Обегаем всю анимацию: раздувание достигает максимума в середине.
      for (var step = 0; step < 8; step++) {
        await tester.pump(const Duration(milliseconds: 40));
        final r = pillRect();
        debugPrint('шаг $step: ${r.width}×${r.height}');
        expect(
          r.height,
          lessThanOrEqualTo(r.width + 0.5),
          reason: 'пилюля не должна быть выше своей ширины: '
              'иначе на телефоне она выглядит вертикальным овалом',
        );
        expect(r.height, greaterThan(0));
        worst = math.max(worst, r.height);
      }
      await tester.pumpAndSettle();
      final settled = pillRect();
      expect(
        (settled.height - rest.height).abs(),
        lessThan(1.5),
        reason: 'после перехода пилюля возвращается в исходный размер',
      );
    }
    debugPrint('ТЕЛЕФОН, максимум роста: $worst');
  });

  // Панель должна оставаться на месте на всех четырёх страницах оболочки,
  // включая календарь и заметки: раньше она пропадала при переходе.
  testWidgets('панель на месте на каждой странице оболочки', (tester) async {
    for (var page = 0; page < 4; page++) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            extendBody: true,
            body: SizedBox.expand(child: Text('страница $page')),
            bottomNavigationBar: GlassBottomBar(
              currentIndex: page,
              onTap: (_) {},
              items: items,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byType(GlassBottomBar),
        findsOneWidget,
        reason: 'панель пропала на странице $page',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'ошибка вёрстки на странице $page',
      );
    }
  });

  testWidgets('таблетка активного пункта отрисовывается', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: GlassBottomBar(
            currentIndex: 2,
            onTap: (_) {},
            items: items,
          ),
        ),
      ),
    );
    // Ищем именно картинку-таблетку, а не сам виджет панели.
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  // Подложка панели всегда полупрозрачная: сквозь неё должны просвечивать
  // элементы под панелью. Непрозрачная заливка здесь — прямой баг, поэтому
  // альфу проверяем явно в обеих темах.
  testWidgets('подложка полупрозрачная: сквозь неё видно содержимое', (tester) async {
    Future<Color> barColor(Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: const ColoredBox(color: Colors.black),
            bottomNavigationBar: GlassBottomBar(
              currentIndex: 0,
              onTap: (_) {},
              items: items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(kGlassNavCapsuleKey),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    final darkColor = await barColor(Brightness.dark);
    final lightColor = await barColor(Brightness.light);
    debugPrint('подложка: тёмная $darkColor, светлая $lightColor');

    for (final entry in {'тёмная': darkColor, 'светлая': lightColor}.entries) {
      expect(
        entry.value.a,
        lessThan(1.0),
        reason: 'подложка в ${entry.key} теме должна просвечивать',
      );
      expect(
        entry.value.a,
        closeTo(kGlassNavMatteAlpha, 0.01),
        reason: 'альфа подложки в ${entry.key} теме',
      );
    }

    // Плюс размытие: без него под панелью просвечивала бы чёткая картинка, а
    // не мягкие матовые пятна.
    expect(find.byType(BackdropFilter), findsWidgets, reason: 'подложка размыта');
  });

  // Оттенок подложки: в тёмной теме светлее чёрного, в светлой темнее белого.
  testWidgets('оттенок подложки: в тёмной теме светлее, в светлой темнее', (tester) async {
    Future<Color> barColor(Brightness brightness) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: const ColoredBox(color: Colors.black),
            bottomNavigationBar: GlassBottomBar(
              currentIndex: 0,
              onTap: (_) {},
              items: items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(kGlassNavCapsuleKey),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      return (box.decoration as BoxDecoration).color!;
    }

    final darkColor = await barColor(Brightness.dark);
    final lightColor = await barColor(Brightness.light);
    debugPrint('оттенок: тёмная $darkColor, светлая $lightColor');

    expect(
      darkColor.computeLuminance(),
      greaterThan(Colors.black.computeLuminance()),
      reason: 'в тёмной теме подложка светлее фона',
    );
    expect(
      lightColor.computeLuminance(),
      lessThan(Colors.white.computeLuminance()),
      reason: 'в светлой теме подложка темнее фона',
    );
    expect(darkColor, isNot(lightColor), reason: 'подложка реагирует на тему');
  });

  // Акцентная обводка рисуется только на раздутой пилюле. Функция вынесена в
  // публичный API панели, поэтому тест проверяет ровно те числа, которые
  // уходят в canvas.
  test('обводка пилюли появляется только в переходе', () {
    const accent = Color(0xFF00B8D4);
    expect(
      kGlassNavPillOutline(0, accent),
      isNull,
      reason: 'в покое обводки быть не должно',
    );
    expect(
      kGlassNavPillOutline(0.0005, accent),
      isNull,
      reason: 'в покое обводки быть не должно',
    );

    final mid = kGlassNavPillOutline(0.5, accent)!;
    final peak = kGlassNavPillOutline(1, accent)!;
    debugPrint('обводка: на 0.5 -> $mid, на 1.0 -> $peak');

    expect(mid.color.a, greaterThan(0), reason: 'обводка видна в переходе');
    expect(
      peak.width,
      greaterThan(mid.width),
      reason: 'к пику раздувания обводка толще',
    );
    expect(
      peak.color.a,
      greaterThan(mid.color.a),
      reason: 'к пику раздувания обводка заметнее',
    );
    expect(
      peak.color.r,
      closeTo(accent.r, 0.01),
      reason: 'обводка должна быть акцентного цвета из темы',
    );
  });

  // Панель не должна держать свой собственный акцент: цвет берётся из темы,
  // поэтому смена темы перекрашивает иконку, подпись и обводку пилюли.
  testWidgets('акцент панели берётся из темы, а не зашит в код', (tester) async {
    Future<Color> activeIconColor(Color seed) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
          home: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: GlassBottomBar(
              currentIndex: 0,
              onTap: (_) {},
              items: items,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final icon = tester.widget<Icon>(find.byIcon(items.first.activeIcon));
      return icon.color!;
    }

    const redSeed = Color(0xFFD32F2F);
    const tealSeed = Color(0xFF00897B);
    final red = await activeIconColor(redSeed);
    final teal = await activeIconColor(tealSeed);
    debugPrint('иконка: при красной теме $red, при бирюзовой $teal');

    expect(red, isNot(teal), reason: 'иконка обязана реагировать на тему');
    expect(
      red.r,
      greaterThan(red.b),
      reason: 'при красном акценте иконка краснее, чем синяя',
    );
    expect(
      teal.b,
      greaterThan(teal.r),
      reason: 'при бирюзовом акценте иконка синее, чем красная',
    );

    // Под активной иконкой и в обводке пилюли должен стоять тот же акцент.
    // Круг — предок иконки, поэтому ищем вверх по дереву.
    final circle = tester.widget<DecoratedBox>(
      find
          .ancestor(
            of: find.byIcon(items.first.activeIcon),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final circleColor = (circle.decoration as BoxDecoration).color!;
    debugPrint('круг под иконкой: $circleColor');
    expect(
      circleColor.r,
      closeTo(teal.r, 0.02),
      reason: 'круг под иконкой должен быть акцентного цвета темы',
    );
  });
}

