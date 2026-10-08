import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khs/models/task.dart';
import 'package:khs/services/task_database.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/notes_editor_screen.dart';
import 'package:khs/ui/notes_screen.dart';
import 'package:khs/ui/notes_tasks_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    sqfliteFfiInit();
    TaskDatabase.useStableDesktopPath = false;
  });

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khs_notes_files_test');
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<AppState> makeState(WidgetTester tester) async {
    // Реальный IO (sqflite) внутри testWidgets выполняется через runAsync,
    // иначе фейковый цикл событий теста подвисает навсегда.
    final state = await tester.runAsync(() async {
      final s = AppState();
      await s.addNote('Корневая', 'текст');
      await s.addNote('В папке', 'текст', folder: 'Работа/Идеи');
      return s;
    });
    return state!;
  }

  Widget wrap(AppState state) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: const Scaffold(body: NotesPanel()),
      ),
    );
  }

  void setBigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('папки: создание, вложенность, переименование, удаление', () async {
    final state = AppState();
    await state.createFolder('Работа');
    await state.createFolder('Работа/Идеи');
    expect(state.childFolders(''), ['Работа']);
    expect(state.childFolders('Работа'), ['Работа/Идеи']);
    expect(state.folderHasContent('Работа'), isTrue);

    await state.renameFolder('Работа', 'Проекты');
    expect(state.noteFolderPaths, containsAll(['Проекты', 'Проекты/Идеи']));
    expect(state.noteFolderPaths.contains('Работа'), isFalse);

    expect(await state.deleteFolder('Проекты'), isFalse);
    expect(await state.deleteFolder('Проекты/Идеи'), isTrue);
    expect(await state.deleteFolder('Проекты'), isTrue);
    expect(state.noteFolderPaths, isEmpty);
  });

  test('путь папки собирается и разбирается', () {
    expect(AppState.joinFolder('', 'Работа'), 'Работа');
    expect(AppState.joinFolder('Работа', 'Идеи'), 'Работа/Идеи');
    expect(AppState.folderParent('Работа/Идеи'), 'Работа');
    expect(AppState.folderParent('Работа'), '');
    expect(AppState.folderName('Работа/Идеи'), 'Идеи');
  });

  testWidgets('в корне видны промежуточная папка и подстраница задач', (
    tester,
  ) async {
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));
    expect(find.text('Работа'), findsOneWidget);
    expect(find.text('Корневая'), findsOneWidget);
    expect(find.text('В папке'), findsNothing);
    expect(find.text('Задачи'), findsOneWidget);
  });

  testWidgets('переход по папкам показывает её содержимое', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.text('Работа'));
    await tester.pumpAndSettle();
    // Заголовок и крошка с одним именем.
    expect(find.text('Работа'), findsNWidgets(2));
    expect(find.text('Идеи'), findsOneWidget);
    expect(find.text('Корневая'), findsNothing);

    await tester.tap(find.text('Идеи'));
    await tester.pumpAndSettle();
    expect(find.text('В папке'), findsOneWidget);
    expect(find.text('Корневая'), findsNothing);
  });

  testWidgets('меню создаёт новую папку и открывает её', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Новая папка'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Черновики');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    expect(state.noteFolderPaths, contains('Черновики'));
    // Открылись в свежесозданной папке: корневые элементы не видны.
    // Заголовок и крошка с одним именем.
    expect(find.text('Черновики'), findsNWidgets(2));
    expect(find.text('Задачи'), findsNothing);
    expect(find.text('Корневая'), findsNothing);
    expect(find.text('Нет заметок. Создай первую!'), findsOneWidget);
  });

  testWidgets('кнопка «Сделать новую заметку» открывает редактор в папке', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));
    await tester.tap(find.text('Работа'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Идеи'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сделать новую заметку'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesEditorScreen), findsOneWidget);
  });

  testWidgets('из корня открывается подстраница задач', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.runAsync(() async {
      await state.addTask(
        Task(title: 'Сделать отчёт', createdAt: DateTime.now(), notify: false),
      );
    });
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.text('Задачи'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesTasksScreen), findsOneWidget);
    expect(find.text('Сделать отчёт'), findsOneWidget);
  });
}
