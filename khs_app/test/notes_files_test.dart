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
    // иначе фейковый цикл событий теста подвиснет навсегда.
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

  testWidgets('в корне: папка, заметка и подстраница задач', (tester) async {
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    expect(find.text('Работа'), findsOneWidget);
    expect(find.text('Корневая'), findsOneWidget);
    expect(find.text('В папке'), findsNothing, reason: 'папка свёрнута');
    expect(find.text('Задачи'), findsOneWidget);
    expect(find.text('Новая заметка'), findsOneWidget);
  });

  testWidgets('тап по папке раскрывает её содержимое', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.text('Работа'));
    await tester.pumpAndSettle();
    expect(find.text('Идеи'), findsOneWidget);
    expect(find.text('Корневая'), findsOneWidget);
    expect(find.text('В папке'), findsNothing);

    await tester.tap(find.text('Идеи'));
    await tester.pumpAndSettle();
    expect(find.text('В папке'), findsOneWidget);
    // Выбранная папка видна в крошках: строка дерева + сегмент.
    expect(find.text('Идеи'), findsNWidgets(2));
  });

  testWidgets('кнопка новой папки создаёт папку в текущей', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Черновики');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();

    expect(state.noteFolderPaths, contains('Черновики'));
    expect(find.text('Черновики'), findsOneWidget);
    expect(find.text('Нет заметок. Создай первую!'), findsNothing);
  });

  testWidgets('кнопка «Новая заметка» открывает редактор', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.text('Новая заметка'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesEditorScreen), findsOneWidget);
  });

  testWidgets('тап по заметке открывает её, долгий — меню', (tester) async {
    setBigScreen(tester);
    final state = await makeState(tester);
    await tester.pumpWidget(wrap(state));

    await tester.tap(find.text('Корневая'));
    await tester.pumpAndSettle();
    expect(find.byType(NotesEditorScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Корневая'));
    await tester.pumpAndSettle();
    expect(find.text('Переместить в папку'), findsOneWidget);
    expect(find.text('Удалить'), findsOneWidget);
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
