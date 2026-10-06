import 'package:flutter/material.dart';

import 'src/screens/home_screen.dart';

/// Читалка внутри хаба.
///
/// Отдельного маршрута и своей шапки нет: экран подставляется в тело хаба,поэтому
/// верхнюю панель и заголовок рисует HubScreen. Снизу остаётся стеклянная
/// панель вкладок читалки.
///
/// Тему не переопределяем намеренно. Раньше здесь был
/// `ColorScheme.fromSeed(0xFF5B3A8E)`, из-за чего панель внизу и все
/// поверхности читалки были фиолетовыми, а в KHS Tasks — в акценте
/// пользователя. Теперь читалка наследует тему KHS, поэтому стеклянная
/// панель выглядит так же, как в задачах.
class ReaderHome extends StatelessWidget {
  const ReaderHome({super.key});

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
