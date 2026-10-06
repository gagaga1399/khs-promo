import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/glass_bottom_bar.dart';

const List<GlassNavItem> _items = [
  GlassNavItem(
    icon: Icons.home_outlined,
    activeIcon: Icons.home,
    label: 'Главная',
  ),
  GlassNavItem(
    icon: Icons.calendar_month_outlined,
    activeIcon: Icons.calendar_month,
    label: 'Календарь',
  ),
  GlassNavItem(
    icon: Icons.book_outlined,
    activeIcon: Icons.book,
    label: 'Заметки',
  ),
  GlassNavItem(
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    label: 'Настройки',
  ),
];

/// Индекс вкладки настроек: на ней панель уезжает вниз.
const int _settingsIndex = 3;

Widget _host({
  required int index,
  ValueChanged<int>? onTap,
  bool hidden = false,
  VoidCallback? onBack,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: const SizedBox(height: 400),
        bottomNavigationBar: GlassBottomBar(
          currentIndex: index,
          onTap: onTap ?? (_) {},
          items: _items,
          hidden: hidden,
          onBack: onBack,
        ),
      ),
    ),
  );
}

/// Смещение капсулы по вертикали. Без [Finder.hitTestable]: уехавшая капсула
/// вне области нажатия, и такой поиск вернул бы ноль элементов вместо нулевой
/// позиции — проверка смещения молча прошла бы.
double _capsuleOffset(WidgetTester tester) =>
    tester.getRect(find.byKey(kGlassNavCapsuleKey)).top;

/// Прозрачность самой капсулы: ищем её Opacity среди потомков виджета.
double _capsuleOpacity(WidgetTester tester) {
  final opacity = tester.widgetList<Opacity>(
    find.descendant(
      of: find.byType(GlassBottomBar),
      matching: find.byType(Opacity),
    ),
  );
  // Внешняя прозрачность — первая в дереве: она отвечает за уход, внутренние
  // принадлежат подложке капсулы.
  return opacity.first.opacity;
}

void main() {
  testWidgets('на обычной вкладке капсула на месте и видима', (tester) async {
    await tester.pumpWidget(_host(index: 0));
    await tester.pumpAndSettle();

    expect(_capsuleOpacity(tester), 1.0);
    expect(find.byKey(kGlassNavCapsuleKey), findsOneWidget);
  });

  testWidgets('в настройках капсула уезжает вниз и гаснет', (tester) async {
    await tester.pumpWidget(_host(index: 0, onBack: () {}));
    await tester.pumpAndSettle();
    final resting = _capsuleOffset(tester);

    // Переключаемся на настройки: та же панель, но уехавшая.
    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () {}),
    );
    await tester.pumpAndSettle();

    expect(_capsuleOffset(tester), greaterThan(resting));
    expect(_capsuleOpacity(tester), 0.0);
  });

  testWidgets('назад капсула поднимается на прежнее место', (tester) async {
    await tester.pumpWidget(_host(index: 0, onBack: () {}));
    await tester.pumpAndSettle();
    final resting = _capsuleOffset(tester);

    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () {}),
    );
    await tester.pumpAndSettle();
    final away = _capsuleOffset(tester);

    await tester.pumpWidget(_host(index: 0, hidden: false, onBack: () {}));
    await tester.pumpAndSettle();

    expect(_capsuleOffset(tester), closeTo(resting, 0.5));
    expect(_capsuleOffset(tester), lessThan(away));
    expect(_capsuleOpacity(tester), 1.0);
  });

  testWidgets('уезжает именно вниз, а не вверх', (tester) async {
    await tester.pumpWidget(_host(index: 0, onBack: () {}));
    await tester.pumpAndSettle();
    final resting = _capsuleOffset(tester);

    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () {}),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // На середине анимации капсула ещё в кадре и уже сместилась вниз.
    final mid = _capsuleOffset(tester);
    expect(mid, greaterThan(resting));
    expect(_capsuleOpacity(tester), greaterThan(0.0));
    expect(_capsuleOpacity(tester), lessThan(1.0));

    await tester.pumpAndSettle();
    expect(_capsuleOffset(tester), greaterThan(mid));
  });

  testWidgets('на месте ушедшей капсулы появляется кнопка назад', (
    tester,
  ) async {
    var back = 0;
    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () => back++),
    );
    await tester.pumpAndSettle();

    final pill = find.byIcon(Icons.arrow_back);
    expect(pill, findsOneWidget);
    await tester.tap(pill);
    expect(back, 1);
  });

  testWidgets('кнопки назад нет, пока капсула на месте', (tester) async {
    await tester.pumpWidget(_host(index: 0, onBack: () {}));
    await tester.pumpAndSettle();

    // Прозрачность 0, но виджет в дереве есть: появление должно быть
    // плавным, а не появлением нового элемента.
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(_capsuleOpacity(tester), 1.0);
  });

  testWidgets('без onBack панель просто уходит вниз', (tester) async {
    await tester.pumpWidget(_host(index: 0));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_host(index: _settingsIndex, hidden: true));
    await tester.pumpAndSettle();

    expect(_capsuleOpacity(tester), 0.0);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('высота панели не меняется: тело экрана не дёргается', (
    tester,
  ) async {
    await tester.pumpWidget(_host(index: 0));
    await tester.pumpAndSettle();
    final before = tester.getSize(find.byType(GlassBottomBar)).height;

    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () {}),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(GlassBottomBar)).height, before);
  });

  testWidgets('при уменьшенной анимации переход мгновенный', (tester) async {
    await tester.pumpWidget(_host(index: 0, onBack: () {}));
    await tester.pumpAndSettle();
    final resting = _capsuleOffset(tester);

    await tester.pumpWidget(
      _host(
        index: _settingsIndex,
        hidden: true,
        onBack: () {},
        reduceMotion: true,
      ),
    );
    // Один кадр — и уже на месте, без промежуточного состояния.
    await tester.pump();

    expect(_capsuleOpacity(tester), 0.0);
    expect(_capsuleOffset(tester), greaterThan(resting));
  });

  testWidgets('прерывание на лету не оставляет панель в промежутке', (
    tester,
  ) async {
    await tester.pumpWidget(_host(index: 0, onBack: () {}));
    await tester.pumpAndSettle();

    // Уезжает, но не доехал — и сразу возвращается.
    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () {}),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(_host(index: 0, hidden: false, onBack: () {}));
    await tester.pumpAndSettle();

    expect(_capsuleOpacity(tester), 1.0);
    expect(find.byKey(kGlassNavCapsuleKey), findsOneWidget);
  });

  testWidgets('в настройках сразу при открытии панель не проезжает мимо', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(index: _settingsIndex, hidden: true, onBack: () {}),
    );

    // Уже на первом кадре капсула уехала: иначе при запуске прямо в
    // настройках панель промелькнула бы снизу вверх.
    await tester.pump();
    expect(_capsuleOpacity(tester), 0.0);
  });
}
