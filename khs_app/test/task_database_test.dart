import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/note.dart';
import 'package:khs/models/task.dart';
import 'package:khs/services/task_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _joinLike(String a, String b) {
  if (a.endsWith(r'\') || a.endsWith('/')) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    TaskDatabase.useStableDesktopPath = false;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khs_db_test');
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDown(() async {
    await databaseFactoryFfi.deleteDatabase(
      _joinLike(tempDir.path, 'taskforge.db'),
    );
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('схема v5: записи получают client_key', () async {
    final db = TaskDatabase();
    final taskId = await db.insertTask(
      Task(title: 'Тест', createdAt: DateTime(2026, 8, 15)),
    );
    final noteId = await db.insertNote(
      Note(
        title: 'Заметка',
        createdAt: DateTime(2026, 8, 15),
        updatedAt: DateTime(2026, 8, 15),
      ),
    );

    final tasks = await db.getAllTasks();
    final notes = await db.getAllNotes();

    expect(tasks.single['client_key'], isNotNull);
    expect(notes.single['client_key'], isNotNull);
    expect(tasks.single['client_key'], isNotEmpty);
    expect(tasks.single['updated_at'], isNotNull);
    expect(tasks.single['id'], taskId);
    expect(notes.single['id'], noteId);
  });

  test(
    'мягкое удаление: get исключает, getAll возвращает с deleted=1',
    () async {
      final db = TaskDatabase();
      final id = await db.insertTask(
        Task(title: 'Задача', createdAt: DateTime(2026, 8, 15)),
      );

      expect(await db.getTasks(), hasLength(1));

      await db.deleteTask(id);

      expect(await db.getTasks(), isEmpty);
      final all = await db.getAllTasks();
      expect(all.single['deleted'], 1);
      expect(all.single['updated_at'], isNotNull);
    },
  );

  test('updateTask: bump обновляет updated_at, bump:false сохраняет', () async {
    final db = TaskDatabase();
    final id = await db.insertTask(
      Task(title: 'Задача', createdAt: DateTime(2026, 8, 15)),
    );

    final before = await db.getAllTasks();
    final beforeUpdated = before.single['updated_at'] as int;

    await db.updateTask(
      Task(
        id: id,
        title: 'Задача 2',
        createdAt: DateTime(2026, 8, 15),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(beforeUpdated),
        clientKey: before.single['client_key'] as String,
      ),
      bumpUpdatedAt: false,
    );

    final after = await db.getAllTasks();
    expect(after.single['title'], 'Задача 2');
    expect(after.single['updated_at'], beforeUpdated);

    await db.updateTask(
      Task(
        id: id,
        title: 'Задача 3',
        createdAt: DateTime(2026, 8, 15),
        clientKey: after.single['client_key'] as String,
      ),
    );
    final bumped = await db.getAllTasks();
    expect(bumped.single['updated_at'], isNot(beforeUpdated));
  });

  test(
    'корзина заметок: удалить → в корзине, восстановить, удалить навсегда',
    () async {
      final db = TaskDatabase();
      final id = await db.insertNote(
        Note(
          title: 'Заметка',
          createdAt: DateTime(2026, 8, 15),
          updatedAt: DateTime(2026, 8, 15),
        ),
      );

      await db.deleteNote(id);
      var deleted = await db.getDeletedNotes();
      expect(deleted, hasLength(1));
      expect(deleted.single.id, id);
      expect(await db.getNotes(), isEmpty);

      await db.restoreNote(id);
      expect(await db.getDeletedNotes(), isEmpty);
      expect(await db.getNotes(), hasLength(1));

      await db.deleteNote(id);
      await db.purgeNote(id);
      expect(await db.getDeletedNotes(), isEmpty);
      expect(await db.getAllNotes(), isEmpty);
    },
  );

  test('notify: по умолчанию 1, сохраняется и читается из БД', () async {
    final db = TaskDatabase();
    await db.insertTask(
      Task(
        title: 'Задача без уведомления',
        notify: false,
        createdAt: DateTime(2026, 8, 15),
      ),
    );

    final rows = await db.getAllTasks();
    expect(rows.single['notify'], 0);

    final loaded = (await db.getTasks()).single;
    expect(loaded.notify, isFalse);

    await db.updateTask(loaded.copyWith(notify: true));
    final after = (await db.getTasks()).single;
    expect(after.notify, isTrue);
  });
}
