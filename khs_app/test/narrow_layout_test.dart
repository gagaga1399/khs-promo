import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:khs/models/task.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/notes_screen.dart';
import 'package:khs/ui/widgets/task_tile.dart';

/// Ширина телефона: увеличенные отступы не должны ронять разметку в брак.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  void narrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget host(Widget child) {
    return ChangeNotifierProvider<AppState>.value(
      value: AppState(),
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('заметки: заголовок, кнопка и список живут в 360px', (
    tester,
  ) async {
    narrow(tester);
    await tester.pumpWidget(host(const NotesPanel()));
    await tester.pumpAndSettle();

    expect(find.text('Новая заметка'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('карточка задачи не вылезает за 360px', (tester) async {
    narrow(tester);
    final state = AppState();
    final strings = state.strings;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [
                TaskTile(
                  task: Task(
                    title:
                        'Очень длинное название задачи, которое точно '
                        'не поместится в одну строку на узком экране',
                    dueAt: DateTime.now(),
                    priority: 2,
                    createdAt: DateTime.now(),
                  ),
                  strings: strings,
                  onToggle: (_) {},
                  onTap: () {},
                  onDelete: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(TaskTile), findsOneWidget);
  });
}
