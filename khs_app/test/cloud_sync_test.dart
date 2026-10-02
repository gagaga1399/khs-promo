import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/task.dart';
import 'package:khs/services/cloud_sync_service.dart';
import 'package:khs/services/task_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Облачная синхронизация задач и заметок: два устройства смотрят в одну базу
/// Firestore под одним uid и должны видеть правки друг друга, при этом под
/// чужим uid ничего не смешивается.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TaskDatabase.useStableDesktopPath = false;
    databaseFactory = databaseFactoryFfi;
  });

  final dirs = <Directory>[];

  /// Отдельная «машина»: своя папка с базой. Путь общий для процесса, поэтому
  /// открываем базу сразу, пока путь указывает на нужную папку.
  Future<TaskDatabase> device(String name) async {
    final dir = await Directory.systemTemp.createTemp('khs_cloud_$name');
    dirs.add(dir);
    databaseFactoryFfi.setDatabasesPath(dir.path);
    final db = TaskDatabase();
    await db.database;
    return db;
  }

  tearDownAll(() async {
    for (final d in dirs) {
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  test('без входа синхронизация ничего не делает', () async {
    final db = await device('no-auth');
    final result = await (CloudSyncService(
      db: db,
      uidProvider: () => null,
      firestore: FakeFirebaseFirestore(),
    )).run();

    expect(result.status, 'skipped');
    expect(result.pushed, 0);
  });

  test('задача с телефона доходит до облака и обратно на ПК', () async {
    final cloud = FakeFirebaseFirestore();
    final phone = await device('phone');
    final pc = await device('pc');

    await phone.insertTask(Task(title: 'Купить хлеб', createdAt: DateTime.now()));

    final onPhone = CloudSyncService(
      db: phone,
      uidProvider: () => 'uid-1',
      firestore: cloud,
    );
    final pushed = await onPhone.run();
    expect(pushed.status, 'ok');
    expect(pushed.pushed, greaterThan(0));

    final onPc = CloudSyncService(
      db: pc,
      uidProvider: () => 'uid-1',
      firestore: cloud,
    );
    expect((await onPc.run()).status, 'ok');

    final pcTasks = await pc.getTasks();
    expect(pcTasks.map((t) => t.title), contains('Купить хлеб'));

    // Правка на ПК должна уехать обратно на телефон.
    final edited = pcTasks.first;
    await pc.updateTask(edited.copyWith(title: 'Купить молоко'));
    await onPc.run();

    final pulledAgain = await onPhone.run();
    expect(pulledAgain.status, 'ok');

    final phoneTitles = (await phone.getTasks()).map((t) => t.title).toList();
    expect(phoneTitles, contains('Купить молоко'));
    expect(phoneTitles, isNot(contains('Купить хлеб')));
  });

  test('удаление на одном устройстве переносится на другое', () async {
    final cloud = FakeFirebaseFirestore();
    final a = await device('dev-a');
    final b = await device('dev-b');

    await a.insertTask(Task(title: 'Задача', createdAt: DateTime.now()));
    final syncA = CloudSyncService(db: a, uidProvider: () => 'uid-2', firestore: cloud);
    await syncA.run();

    final task = (await a.getTasks()).first;
    await a.deleteTask(task.id!);
    await syncA.run();

    final syncB = CloudSyncService(db: b, uidProvider: () => 'uid-2', firestore: cloud);
    await syncB.run();

    expect((await b.getTasks()).map((t) => t.title), isNot(contains('Задача')));
  });

  test('под чужим uid ничего не смешивается', () async {
    final cloud = FakeFirebaseFirestore();
    final mine = await device('mine');
    final theirs = await device('theirs');

    await mine.insertTask(Task(title: 'Моя задача', createdAt: DateTime.now()));
    await theirs.insertTask(Task(title: 'Чужая задача', createdAt: DateTime.now()));

    await (CloudSyncService(db: mine, uidProvider: () => 'uid-mine', firestore: cloud)).run();
    await (CloudSyncService(db: theirs, uidProvider: () => 'uid-theirs', firestore: cloud)).run();

    expect((await mine.getTasks()).map((t) => t.title), isNot(contains('Чужая задача')));
    expect((await theirs.getTasks()).map((t) => t.title), isNot(contains('Моя задача')));

    final mineDocs =
        await cloud.collection('users').doc('uid-mine').collection('tasks').get();
    expect(mineDocs.docs, hasLength(1));
  });

  test('после выхода из аккаунта данные остаются на устройстве', () async {
    final cloud = FakeFirebaseFirestore();
    final db = await device('logged-out');

    await db.insertTask(Task(title: 'Локальная', createdAt: DateTime.now()));

    final result = await (CloudSyncService(
      db: db,
      uidProvider: () => null,
      firestore: cloud,
    )).run();

    expect(result.status, 'skipped');
    expect((await cloud.collection('users').get()).docs, isEmpty);
    expect((await db.getTasks()).map((t) => t.title), contains('Локальная'));
  });
}
