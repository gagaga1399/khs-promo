import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:khs/state/app_state.dart';
import 'package:khs/ui/note_template_editor_screen.dart';
import 'package:khs/ui/vault_notes_panel.dart';
import 'package:khs/ui/vault_note_viewer_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  Widget wrap(AppState state) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: const Scaffold(body: VaultNotesPanel()),
      ),
    );
  }

  void setBigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Всё реальное IO (сканирование хранилища, запись файла, загрузка
  /// просмотрщика) живёт только внутри `runAsync`; кадры отрисовываются
  /// руками, чтобы будущее успевало резолвиться.
  Future<Directory> makeVault(WidgetTester tester, AppState state) async {
    late Directory dir;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('khs_vault');
      await state.setVaultPath(dir.path);
    });
    return dir;
  }

  Future<void> pumpVault(WidgetTester tester, AppState state) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(wrap(state));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });
  }

  Future<void> removeVault(WidgetTester tester, Directory dir) async {
    await tester.runAsync(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
  }

  testWidgets('панель без хранилища показывает подсказку и не падает', (
    tester,
  ) async {
    final state = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: Scaffold(body: VaultNotesPanel())),
      ),
    );
    await tester.pump();
    expect(find.text('Хранилище не указано'), findsOneWidget);
  });

  testWidgets('лист создания показывает название, шаблоны и кнопку создания', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);

    await pumpVault(tester, state);
    expect(find.text('В хранилище нет заметок'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Новая заметка'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });
    expect(find.text('Шаблон'), findsOneWidget);
    for (final name in ['Пустая', 'Дневник', 'Список дел', 'Идея', 'Встреча']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Создать заметку'), findsOneWidget);
    await removeVault(tester, dir);
  });

  testWidgets('создание заметки из шаблона пишет файл и открывает просмотрщик', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);

    await pumpVault(tester, state);

    await tester.runAsync(() async {
      await tester.tap(find.text('Новая заметка'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(find.byType(TextField), 'Поездка в горы');
      await tester.pump();
      await tester.tap(find.text('Дневник'));
      await tester.pump();
      await tester.tap(find.text('Создать заметку'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    final file = File(p.join(dir.path, 'Поездка в горы.md'));
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('# Поездка в горы'));
    expect(content, contains('**Дата:**'));
    expect(content, contains('## Сделано'));
    expect(find.byType(VaultNoteViewerScreen), findsOneWidget);
    await removeVault(tester, dir);
  });

  testWidgets('свой шаблон со свойствами пишется во frontmatter заметки', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);

    await pumpVault(tester, state);

    Finder byHint(String hint) => find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.hintText == hint,
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Новая заметка'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Свой шаблон'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(
        find.byKey(const ValueKey('note_template_name')),
        'Книга',
      );
      await tester.enterText(
        find.byKey(const ValueKey('note_template_body')),
        '# {{title}}\n\nАвтор: \n',
      );
      final editor = find.byType(NoteTemplateEditorScreen);
      await tester.tap(
        find.descendant(
          of: editor,
          matching: find.byTooltip('Добавить свойство'),
        ),
      );
      await tester.pump();
      await tester.enterText(
        find.descendant(of: editor, matching: byHint('Имя')),
        'tags',
      );
      await tester.enterText(
        find.descendant(of: editor, matching: byHint('Значение')),
        'книга',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Сохранить шаблон'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.enterText(find.byType(TextField).first, 'Моя книга');
      await tester.pump();
      await tester.tap(find.text('Создать заметку'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(state.noteTemplates.map((t) => t.name), contains('Книга'));
    final file = File(p.join(dir.path, 'Моя книга.md'));
    expect(file.existsSync(), isTrue);
    final content = file.readAsStringSync();
    expect(content, contains('---'));
    expect(content, contains('tags: книга'));
    expect(content, contains('# Моя книга'));
    expect(content, isNot(contains('{{title}}')));
    await removeVault(tester, dir);
  });

  testWidgets('удаление заметки удаляет файл и обновляет панель', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);
    final file = File(p.join(dir.path, 'Заметка.md'));
    await tester.runAsync(() async {
      await file.writeAsString('# Заметка\n');
    });

    await pumpVault(tester, state);
    expect(find.text('Заметка'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Действия с заметкой'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Удалить заметку'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Удалить'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(file.existsSync(), isFalse);
    expect(find.text('В хранилище нет заметок'), findsOneWidget);
    await removeVault(tester, dir);
  });

  testWidgets('перемещение заметки переносит файл в новую папку', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);
    final file = File(p.join(dir.path, 'Идея.md'));
    await tester.runAsync(() async {
      await file.writeAsString('# Идея\n');
    });

    await pumpVault(tester, state);
    expect(find.text('Идея'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('Действия с заметкой'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Переименовать или переместить'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final field = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Папка/Имя.md',
      );
      await tester.enterText(field, 'Папка/Идея2');
      await tester.pump();
      await tester.tap(find.text('ОК'));
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(file.existsSync(), isFalse);
    final moved = File(p.join(dir.path, 'Папка', 'Идея2.md'));
    expect(moved.existsSync(), isTrue);
    expect(moved.readAsStringSync(), contains('# Идея'));
    await removeVault(tester, dir);
  });

  testWidgets('перетаскивание заметки мышью переносит её в папку', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);
    await tester.runAsync(() async {
      await Directory(p.join(dir.path, 'Папка')).create();
      await File(
        p.join(dir.path, 'Папка', 'Внутри.md'),
      ).writeAsString('# Внутри\n');
      await File(p.join(dir.path, 'Идея.md')).writeAsString('# Идея\n');
    });

    await pumpVault(tester, state);
    expect(find.text('Идея'), findsOneWidget);
    expect(find.text('Папка'), findsOneWidget);

    await tester.runAsync(() async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Идея')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(find.text('Папка')));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(File(p.join(dir.path, 'Идея.md')).existsSync(), isFalse);
    expect(File(p.join(dir.path, 'Папка', 'Идея.md')).existsSync(), isTrue);
    await removeVault(tester, dir);
  });

  testWidgets('перетаскивание папки мышью вкладывает её в другую папку', (
    tester,
  ) async {
    setBigScreen(tester);
    final state = AppState();
    final dir = await makeVault(tester, state);
    await tester.runAsync(() async {
      await Directory(p.join(dir.path, 'Альфа')).create();
      await File(p.join(dir.path, 'Альфа', 'а.md')).writeAsString('# а\n');
      await Directory(p.join(dir.path, 'Бета')).create();
      await File(p.join(dir.path, 'Бета', 'б.md')).writeAsString('# б\n');
    });

    await pumpVault(tester, state);
    expect(find.text('Альфа'), findsOneWidget);
    expect(find.text('Бета'), findsOneWidget);

    await tester.runAsync(() async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Альфа')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(tester.getCenter(find.text('Бета')));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
      }
    });

    expect(Directory(p.join(dir.path, 'Альфа')).existsSync(), isFalse);
    expect(Directory(p.join(dir.path, 'Бета', 'Альфа')).existsSync(), isTrue);
    expect(
      File(p.join(dir.path, 'Бета', 'Альфа', 'а.md')).existsSync(),
      isTrue,
    );
    await removeVault(tester, dir);
  });
}