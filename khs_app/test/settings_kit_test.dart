import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/settings_kit.dart';

/// Фон, который подставляет [_host]. Палитра настроек берёт фон из темы,
/// поэтому в тестах он должен быть известен точно.
const Color hostDarkBackground = Color(0xFF101014);
const Color hostLightBackground = Color(0xFFB9B6A8);

final ColorScheme hostDarkScheme = ColorScheme.fromSeed(
  seedColor: const Color(0xFFE11D48),
  brightness: Brightness.dark,
);

Widget _host(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFE11D48),
        brightness: brightness,
      ),
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? hostDarkBackground
          : hostLightBackground,
    ),
    home: Scaffold(body: child),
  );
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(_host(child));
  await tester.pumpAndSettle();
}

void main() {
  group('SettingsTokens', () {
    test('палитра тёмной темы совпадает с ТЗ', () {
      const p = SettingsPalette.darkPalette;
      expect(p.background, const Color(0xFF000000));
      expect(p.card, const Color(0xFF1C1C1E));
      expect(p.text, const Color(0xFFFFFFFF));
      expect(p.muted, const Color(0xFF8E8E93));
      expect(p.divider, const Color(0xFF2C2C2E));
    });

    test('геометрия из ТЗ', () {
      expect(SettingsTokens.margin, 16);
      expect(SettingsTokens.gap, greaterThanOrEqualTo(16));
      expect(SettingsTokens.gap, lessThanOrEqualTo(20));
      expect(SettingsTokens.radiusCard, 18);
      expect(SettingsTokens.padH, 16);
    });

    test('разделитель внутри карточки начинается на тексте, а не на краю', () {
      expect(
        SettingsTokens.dividerInset,
        SettingsTokens.padH + SettingsTokens.iconSize + SettingsTokens.iconGap,
      );
    });
  });

  group('SettingsPalette', () {
    testWidgets('берёт все цвета из темы, а не зашитые', (tester) async {
      // Схема задана явно, а не через fromSeed: у fromSeed в тёмной схеме
      // primary светлее seed, и проверять было бы не то самое.
      const scheme = ColorScheme.dark(
        primary: Color(0xFFE11D48),
        surfaceContainerHigh: Color(0xFF1C1C1E),
        onSurface: Color(0xFFFFFFFF),
        onSurfaceVariant: Color(0xFF8E8E93),
        outline: Color(0xFF2C2C2E),
      );
      const bg = Color(0xFF101014);
      late SettingsPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            colorScheme: scheme,
            scaffoldBackgroundColor: bg,
          ),
          home: Builder(
            builder: (context) {
              palette = SettingsPalette.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      // Раньше здесь стояли зашитые чёрный и тёмно-серый, из-за чего выбор
      // темы не доходил до настроек: при красной теме они оставались чёрными.
      expect(palette.accent, scheme.primary);
      expect(palette.background, bg);
      expect(palette.card, scheme.surfaceContainerHigh);
      expect(palette.text, scheme.onSurface);
      expect(palette.muted, scheme.onSurfaceVariant);
      expect(palette.divider, scheme.outline);
    });

    test('withAccent меняет только акцент', () {
      const base = SettingsPalette.darkPalette;
      final patched = base.withAccent(const Color(0xFF00FF00));
      expect(patched.accent, const Color(0xFF00FF00));
      expect(patched.card, base.card);
      expect(patched.background, base.background);
      expect(patched.text, base.text);
      expect(patched.muted, base.muted);
      expect(patched.divider, base.divider);
    });
  });

  group('SettingsView', () {
    testWidgets('фон экрана берётся из темы', (tester) async {
      await _pump(
        tester,
        const SettingsView(title: 'Настройки', children: [SizedBox.shrink()]),
      );
      final box = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(SettingsView),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(box.color, hostDarkBackground);
    });

    testWidgets('зазор между соседними карточками равен SettingsTokens.gap', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [SizedBox(height: 40), SizedBox(height: 40)],
        ),
      );
      final gaps = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(SizedBox),
            ),
          )
          .where((s) => s.height == SettingsTokens.gap);
      expect(gaps, isNotEmpty);
    });

    testWidgets('стрелки нет без onBack, и она кликабельна с onBack', (
      tester,
    ) async {
      await _pump(tester, const SettingsView(title: 'Настройки', children: []));
      expect(find.byIcon(Icons.arrow_back_ios_new), findsNothing);

      var tapped = 0;
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          onBack: () => tapped++,
          children: const [],
        ),
      );
      expect(find.byIcon(Icons.arrow_back_ios_new), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      expect(tapped, 1);
    });

    testWidgets('заголовок расположен под стрелкой', (tester) async {
      await _pump(
        tester,
        SettingsView(title: 'Настройки', onBack: () {}, children: const []),
      );
      final back = tester.getTopLeft(find.byIcon(Icons.arrow_back_ios_new));
      final title = tester.getTopLeft(find.text('Настройки'));
      final backBottom = tester.getBottomLeft(
        find.byIcon(Icons.arrow_back_ios_new),
      );
      expect(title.dy, greaterThan(backBottom.dy));
      expect(title.dx, closeTo(back.dx, 1.0));
    });

    testWidgets('пустой заголовок не рисуется', (tester) async {
      await _pump(
        tester,
        const SettingsView(title: '', children: [SizedBox.shrink()]),
      );
      // Заголовок пуст, когда экран уже подписан в нижней навигации: иначе
      // слово «Настройки» дублировалось на одном экране.
      expect(find.byType(SettingsHeader), findsOneWidget);
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(SettingsHeader),
                matching: find.byType(Text),
              ),
            )
            .where((t) => t.data?.trim().isNotEmpty ?? false),
        isEmpty,
      );
    });

    testWidgets('стрелка назад белая и не сливается с фоном', (tester) async {
      await _pump(
        tester,
        SettingsView(title: 'Настройки', onBack: () {}, children: []),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.arrow_back_ios_new));
      expect(icon.color, Colors.white);
    });

    testWidgets('поиск прокидывает введённый текст', (tester) async {
      String? value;
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          search: SettingsSearch(hint: 'Поиск', onChanged: (v) => value = v),
          children: const [],
        ),
      );
      await tester.enterText(find.byType(TextField), 'темa');
      await tester.pump();
      expect(value, 'темa');
    });
  });

  group('SettingsCard', () {
    testWidgets('разделитель соседних пунктов с отступом на тексте', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(
              children: [
                SettingsRow(title: 'Первый', icon: Icons.circle),
                SettingsRow(title: 'Второй', icon: Icons.square),
              ],
            ),
          ],
        ),
      );
      final divider = tester.widget<Divider>(find.byType(Divider));
      expect(divider.color, hostDarkScheme.outline);
      expect(divider.thickness, SettingsTokens.dividerThickness);
      final padding = tester.widget<Padding>(
        find
            .ancestor(of: find.byType(Divider), matching: find.byType(Padding))
            .first,
      );
      expect(
        padding.padding,
        const EdgeInsets.only(left: SettingsTokens.dividerInset),
      );
    });

    testWidgets(
      'разделитель перед произвольным содержимым идёт от поля карточки',
      (tester) async {
        await _pump(
          tester,
          const SettingsView(
            title: 'Настройки',
            children: [
              SettingsCard(
                children: [
                  SettingsRow(title: 'Пункт', icon: Icons.circle),
                  TextField(),
                ],
              ),
            ],
          ),
        );
        final padding = tester.widget<Padding>(
          find
              .ancestor(
                of: find.byType(Divider),
                matching: find.byType(Padding),
              )
              .first,
        );
        expect(
          padding.padding,
          const EdgeInsets.only(left: SettingsTokens.padH),
        );
      },
    );

    testWidgets('радиус карточки 18 и фон карточки', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(children: [Text('x')]),
          ],
        ),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(SettingsCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, hostDarkScheme.surfaceContainerHigh);
      expect(
        material.borderRadius,
        BorderRadius.circular(SettingsTokens.radiusCard),
      );
    });

    testWidgets('подзаголовок группы рисуется над карточкой', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(title: 'Группа', children: [Text('x')]),
          ],
        ),
      );
      expect(find.text('Группа'), findsOneWidget);
      final title = tester.getTopLeft(find.text('Группа'));
      final card = tester.getTopLeft(
        find
            .descendant(
              of: find.byType(SettingsCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.dy, greaterThan(title.dy));
    });
  });

  group('SettingsRow', () {
    testWidgets('подзаголовок рисуется под заголовком', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  title: 'Заголовок',
                  subtitle: 'Подзаголовок',
                  icon: Icons.circle,
                ),
              ],
            ),
          ],
        ),
      );
      expect(find.text('Подзаголовок'), findsOneWidget);
      final a = tester.getTopLeft(find.text('Заголовок'));
      final b = tester.getTopLeft(find.text('Подзаголовок'));
      expect(b.dy, greaterThan(a.dy));
      expect(b.dx, closeTo(a.dx, 0.5));
    });

    testWidgets('свой цвет иконки сохраняется', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  title: 'Пункт',
                  icon: Icons.circle,
                  iconColor: SettingsTokens.iconNotes,
                ),
              ],
            ),
          ],
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.circle));
      expect(icon.color, SettingsTokens.iconNotes);
    });

    testWidgets('шеврон появляется только у нажимаемых пунктов', (
      tester,
    ) async {
      void tap() {}
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(
              children: [
                const SettingsRow(title: 'Бит', icon: Icons.circle),
                SettingsRow(title: 'Клик', icon: Icons.circle, onTap: tap),
              ],
            ),
          ],
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('нажатие вызывает onTap', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  title: 'Пункт',
                  icon: Icons.circle,
                  onTap: () => taps++,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.tap(find.text('Пункт'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('собственный trailing отключает шеврон', (tester) async {
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  title: 'Пункт',
                  icon: Icons.circle,
                  trailing: Switch(value: true, onChanged: (_) {}),
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      );
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      expect(find.byType(Switch), findsOneWidget);
    });
  });

  group('SettingsProfileCard', () {
    testWidgets('иконка профиля красная по умолчанию', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [SettingsProfileCard(title: 'Профиль', subtitle: 'Вход')],
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.account_circle));
      expect(icon.color, SettingsTokens.iconProfile);
    });

    testWidgets('свой цвет иконки переопределяет красный', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SettingsProfileCard(
              title: 'Профиль',
              subtitle: 'Вход',
              iconColor: SettingsTokens.iconAccount,
            ),
          ],
        ),
      );
      final icon = tester.widget<Icon>(find.byIcon(Icons.account_circle));
      expect(icon.color, SettingsTokens.iconAccount);
    });
  });

  group('приглушённая прокрутка', () {
    test('шаг колеса приглушен, инерция не гасится', () {
      final c = SettingsScrollController();
      expect(c.stepScale, lessThan(1.0));
      expect(c.stepScale, greaterThan(0.0));
    });

    test('шаг колеса можно задать', () {
      final c = SettingsScrollController(stepScale: 0.9);
      expect(c.stepScale, 0.9);
    });

    testWidgets('перетаскивание пальцем идёт на полную скорость', (
      tester,
    ) async {
      // Приглушать applyUserOffset нельзя: на телефоне список ехал вполсилы
      // и казался «залипающим». Касание должно двигать список так же, как
      // обычный ScrollController.
      final plainController = ScrollController(keepScrollOffset: false);
      final kitController = SettingsScrollController(
        stepScale: 0.5,
        keepScrollOffset: false,
      );
      addTearDown(plainController.dispose);
      addTearDown(kitController.dispose);

      Widget listFor(ScrollController controller) => SizedBox(
        height: 300,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 3000, child: Text('x'))],
        ),
      );

      await tester.pumpWidget(
        _host(
          Column(children: [listFor(plainController), listFor(kitController)]),
        ),
      );
      await tester.pumpAndSettle();

      final lists = find.byType(ListView);
      await tester.drag(lists.at(0), const Offset(0, -200));
      await tester.pumpAndSettle();
      await tester.drag(lists.at(1), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(plainController.offset, greaterThan(0));
      expect(kitController.offset, closeTo(plainController.offset, 1));
    });

    testWidgets('инерция после броска такая же, как у обычного списка', (
      tester,
    ) async {
      final plainController = ScrollController(keepScrollOffset: false);
      final kitController = SettingsScrollController(
        stepScale: 0.5,
        keepScrollOffset: false,
      );
      addTearDown(plainController.dispose);
      addTearDown(kitController.dispose);

      Widget listFor(ScrollController controller) => SizedBox(
        height: 300,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 3000, child: Text('x'))],
        ),
      );

      await tester.pumpWidget(
        _host(
          Column(children: [listFor(plainController), listFor(kitController)]),
        ),
      );
      await tester.pumpAndSettle();

      final lists = find.byType(ListView);
      await tester.fling(lists.at(0), const Offset(0, -200), 1200);
      await tester.pumpAndSettle();
      await tester.fling(lists.at(1), const Offset(0, -200), 1200);
      await tester.pumpAndSettle();

      expect(plainController.offset, greaterThan(0));
      expect(kitController.offset, closeTo(plainController.offset, 1));
    });

    testWidgets('колесо прокручивает меньше, чем обычный список', (
      tester,
    ) async {
      // Два списка строим в одном дереве: пересоздание ListView на том же
      // месте передаёт новой позиции пиксели старой (oldPosition), и
      // второй замер вышел бы больше первого.
      final plainController = ScrollController(keepScrollOffset: false);
      final dampedController = SettingsScrollController(
        stepScale: 0.5,
        keepScrollOffset: false,
      );
      addTearDown(plainController.dispose);
      addTearDown(dampedController.dispose);

      Widget listFor(ScrollController controller) => SizedBox(
        height: 300,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 3000, child: Text('x'))],
        ),
      );

      await tester.pumpWidget(
        _host(
          Column(
            children: [listFor(plainController), listFor(dampedController)],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Событие колеса отправляем напрямую: так проверяется именно
      // масштабирование шага, а не поведение конкретного устройства.
      // Позиция обязана быть внутри нужного списка, иначе событие
      // перехватит соседний.
      void wheel(Finder target) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: tester.getCenter(target),
            scrollDelta: const Offset(0, 200),
          ),
        );
      }

      final lists = find.byType(ListView);
      wheel(lists.at(0));
      await tester.pumpAndSettle();
      wheel(lists.at(1));
      await tester.pumpAndSettle();

      expect(plainController.offset, greaterThan(0));
      expect(dampedController.offset, greaterThan(0));
      expect(dampedController.offset, lessThan(plainController.offset));
      // Половина от шага при stepScale 0.5.
      expect(dampedController.offset, closeTo(plainController.offset * 0.5, 1));
    });

    testWidgets(
      'SettingsView по умолчанию использует приглушённый контроллер',
      (tester) async {
        final controller = SettingsScrollController(stepScale: 0.5);
        await _pump(
          tester,
          SizedBox(
            height: 300,
            child: SettingsView(
              title: 'Настройки',
              controller: controller,
              children: const [SizedBox(height: 3000, child: Text('x'))],
            ),
          ),
        );
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(ListView)),
            scrollDelta: const Offset(0, 200),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.offset, greaterThan(0));
        expect(controller.offset, lessThan(200));
      },
    );

    testWidgets('внешний контроллер не диспозится настройками', (tester) async {
      final controller = ScrollController();
      await _pump(
        tester,
        SizedBox(
          height: 300,
          child: SettingsView(
            title: 'Настройки',
            controller: controller,
            children: const [Text('x')],
          ),
        ),
      );
      await _pump(tester, const SizedBox.shrink());
      // Экран не имеет права dispose'ить чужой контроллер: после его
      // освобождения повторный dispose бросил бы ошибку.
      expect(controller.dispose, returnsNormally);
    });
  });

  group('светлая тема', () {
    testWidgets('карточка светлее фона, фон не белый', (tester) async {
      await tester.pumpWidget(
        _host(
          const SettingsView(title: 'Настройки', children: [Text('x')]),
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();
      const light = SettingsPalette.lightPalette;
      expect(light.background, isNot(const Color(0xFFFFFFFF)));
      expect(
        light.card.computeLuminance(),
        greaterThan(light.background.computeLuminance()),
      );
    });
  });

  group('нижняя панель действий', () {
    testWidgets('скрыта, пока список не прокручен', (tester) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          actions: SettingsActionBarButton(label: 'Сохранить', onPressed: null),
          children: [Text('x')],
        ),
      );
      expect(_barOpacity(tester), 0);
      expect(
        _barOffset(tester),
        const Offset(0, 1),
        reason: 'скрытая панель уводится за нижний край',
      );
    });

    testWidgets('появляется при прокрутке вниз', (tester) async {
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          actions: SettingsActionBarButton(
            label: 'Сохранить',
            onPressed: () {},
          ),
          children: const [SizedBox(height: 2000, child: Text('x'))],
        ),
      );
      expect(_barOpacity(tester), 0);

      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();

      expect(_barOpacity(tester), 1);
      expect(_barOffset(tester), Offset.zero);
    });

    testWidgets('снова прячется при прокрутке наверх', (tester) async {
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          actions: SettingsActionBarButton(
            label: 'Сохранить',
            onPressed: () {},
          ),
          children: const [SizedBox(height: 2000, child: Text('x'))],
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(_barOpacity(tester), 1);

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(_barOpacity(tester), 0);
    });

    testWidgets('кнопка нажимается', (tester) async {
      var pressed = 0;
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          actions: SettingsActionBarButton(
            label: 'Сохранить',
            onPressed: () => pressed++,
          ),
          children: const [SizedBox(height: 2000, child: Text('x'))],
        ),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Сохранить'));
      expect(pressed, 1);
    });

    testWidgets('без actions панели нет вовсе', (tester) async {
      await _pump(
        tester,
        const SettingsView(title: 'Настройки', children: [Text('x')]),
      );
      expect(find.byType(SettingsActionBar), findsNothing);
    });

    testWidgets('список не уходит под панель', (tester) async {
      await _pump(
        tester,
        SettingsView(
          title: 'Настройки',
          actions: SettingsActionBarButton(
            label: 'Сохранить',
            onPressed: () {},
          ),
          children: const [SizedBox(height: 2000, child: Text('x'))],
        ),
      );
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(
        (list.padding! as EdgeInsets).bottom,
        greaterThanOrEqualTo(SettingsTokens.actionBarHeight),
      );
    });
  });

  group('счётчик символов', () {
    testWidgets('без лимита счётчика нет', (tester) async {
      await _pump(
        tester,
        const Scaffold(
          body: SettingsField(label: 'Поле', hint: ''),
        ),
      );
      expect(find.byType(SettingsFieldCounter), findsNothing);
    });

    testWidgets('показывает 0 из лимита и растёт при вводе', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SettingsField(label: 'Поле', maxLength: 100)),
      );
      expect(find.text('0 / 100'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump();
      expect(find.text('2 / 100'), findsOneWidget);
    });

    testWidgets('встроенный счётчик Material отключён', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SettingsField(label: 'Поле', maxLength: 100)),
      );
      // Свой счётчик рисуется один раз: если бы работал и встроенный,
      // текст «0 / 100» нашёлся бы дважды.
      expect(find.text('0 / 100'), findsOneWidget);
    });

    testWidgets('превысить лимит нельзя', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: SettingsField(label: 'Поле', maxLength: 5)),
      );
      await tester.enterText(find.byType(TextField), 'abcdefghij');
      await tester.pump();
      expect(find.text('5 / 5'), findsOneWidget);
    });

    testWidgets('счётчик учитывает начальное значение контроллера', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'привет');
      addTearDown(controller.dispose);
      await _pump(
        tester,
        Scaffold(
          body: SettingsField(
            label: 'Поле',
            controller: controller,
            maxLength: 10,
          ),
        ),
      );
      expect(find.text('6 / 10'), findsOneWidget);
      // Встроенный счётчик Material должен быть подавлен.
      expect(find.text('6/10'), findsNothing);
    });
  });

  group('появление карточек', () {
    /// Прозрачность карточки: 0 — скрыта, 1 — полностью видна.
    double opacityOfReveal(WidgetTester tester, SettingsReveal reveal) => tester
        .widgetList<Opacity>(
          find.descendant(
            of: find.byWidget(reveal),
            matching: find.byType(Opacity),
          ),
        )
        .first
        .opacity;

    double opacityOf(WidgetTester tester, int i) {
      final finder = find.byWidgetPredicate(
        (w) => w is SettingsReveal && w.index == i,
      );
      return tester
          .widgetList<Opacity>(
            find.descendant(of: finder, matching: find.byType(Opacity)),
          )
          .first
          .opacity;
    }

    testWidgets('SettingsView оборачивает карточки в SettingsReveal', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SizedBox(height: 40, child: Text('a')),
            SizedBox(height: 40, child: Text('b')),
            SizedBox(height: 40, child: Text('c')),
          ],
        ),
      );
      expect(find.byType(SettingsReveal), findsNWidgets(3));
      final keys = tester
          .widgetList<SettingsReveal>(find.byType(SettingsReveal))
          .map((w) => w.index)
          .toList();
      expect(keys, [0, 1, 2]);
    });

    testWidgets('карточки первого экрана проявляются без прокрутки', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SizedBox(height: 40, child: Text('a')),
            SizedBox(height: 40, child: Text('b')),
          ],
        ),
      );
      // Первый экран обязан быть виден сразу: иначе настройки открываются
      // полностью тёмными.
      expect(opacityOf(tester, 0), 1);
      expect(opacityOf(tester, 1), 1);
    });

    testWidgets('прокрутка проявляет карточки в кадре и не гасит верхние', (
      tester,
    ) async {
      // Окно задаём явно: порог появления зависит от его высоты, иначе
      // тест ломается вместе с вёрсткой заголовка.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _pump(
        tester,
        const SettingsView(
          title: 'Настройки',
          children: [
            SizedBox(height: 1700, child: Text('a')),
            SizedBox(height: 120, child: Text('b')),
          ],
        ),
      );
      // Порог появления — нижние 12% окна, поэтому вторая карточка
      // построена (список ленивый, но она входит в cacheExtent), и при
      // этом ещё скрыта.
      final before = tester
          .widgetList<SettingsReveal>(find.byType(SettingsReveal))
          .toList();
      expect(before.length, 2);
      expect(opacityOfReveal(tester, before.first), 1);
      expect(opacityOfReveal(tester, before.last), 0);

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Всё, что сейчас в списке, показано: и доехавшая до кадра нижняя
      // карточка, и уже показанная верхняя.
      for (final reveal in tester.widgetList<SettingsReveal>(
        find.byType(SettingsReveal),
      )) {
        expect(
          opacityOfReveal(tester, reveal),
          1,
          reason: 'карточка ${reveal.index} не проявилась',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('анимация не выскакивает за пределы разумного', (tester) async {
      // Сдвиг и длительность задают «мягкость»: слишком большое значение
      // читается как рывок.
      expect(SettingsTokens.revealShift, lessThanOrEqualTo(20));
      expect(
        SettingsTokens.revealDuration.inMilliseconds,
        greaterThanOrEqualTo(350),
      );
      expect(
        SettingsTokens.revealStagger.inMilliseconds,
        lessThanOrEqualTo(60),
      );
      expect(SettingsTokens.revealLeadIn, greaterThan(0));
      expect(SettingsTokens.revealLeadIn, lessThan(0.3));
    });
  });
}

/// Прозрачность анимированной панели: 0 — скрыта, 1 — показана.
double _barOpacity(WidgetTester tester) {
  final opacity = tester
      .widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first)
      .opacity;
  expect(opacity, isIn([0.0, 1.0]));
  return opacity;
}

/// Смещение анимированной панели.
Offset _barOffset(WidgetTester tester) =>
    tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;
