import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/qutzem_reader/src/glass_bottom_bar.dart';
import 'package:khs/qutzem_reader/src/screens/home_screen.dart';

void main() {
  // Регрессия: главный экран читалки внутри KHS раньше ставил внизу Material
  // NavigationBar с непрозрачной заливкой, из-за чего читался не так, как
  // KHS Tasks. Тест падает, если вернётся любой Material-навигатор.
  testWidgets('на главном экране читалки стеклянная панель', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.byType(GlassBottomBar), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  // Читалка открывается внутри хаба, поэтому своей шапки у неё быть не
  // должно: верхнюю панель рисует HubScreen. Если вернуть AppBar внутрь
  // читалки, у пользователя будет две шапки подряд.
  testWidgets('у читалки нет своей шапки', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('подписи четырёх вкладок на месте', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

    for (final label in ['Библиотека', 'Заметки', 'Поиск', 'Файлы']) {
      expect(find.text(label), findsOneWidget, reason: 'подпись «$label»');
    }
  });

  // pumpAndSettle здесь не годится: все вкладки собраны сразу в IndexedStack,
  // а в поле поиска мигает курсор, поэтому анимация не заканчивается.
  testWidgets('нажатие переключает вкладку', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pump(const Duration(milliseconds: 100));

    final bar = find.byType(GlassBottomBar);
    expect(tester.widget<GlassBottomBar>(bar).currentIndex, 0);

    await tester.tap(find.text('Заметки'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.widget<GlassBottomBar>(bar).currentIndex, 1);
  });
}