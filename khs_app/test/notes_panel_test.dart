import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/notes_editor_screen.dart';
import 'package:khs/ui/notes_screen.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  Widget wrap(AppState state) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: Scaffold(body: NotesPanel())),
    );
  }

  testWidgets('NotesPanel shows "Сделать новую заметку" on top', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(wrap(state));
    expect(find.text('Сделать новую заметку'), findsOneWidget);
    expect(find.text('Нет заметок. Создай первую!'), findsOneWidget);
  });

  testWidgets('NotesPanel button opens the editor', (tester) async {
    final state = AppState();
    await tester.pumpWidget(wrap(state));
    await tester.tap(find.text('Сделать новую заметку'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesEditorScreen), findsOneWidget);
  });

  testWidgets('new note from a date defaults to daily note', (tester) async {
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: NotesEditorScreen(date: DateTime(2026, 8, 14)),
        ),
      ),
    );
    expect(find.text('Заметка дня'), findsOneWidget);
    expect(find.text('Отдельная заметка'), findsOneWidget);
    expect(find.text('14 августа 2026'), findsOneWidget);
  });
}
