import 'dart:io';
import 'dart:math';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/note.dart';
import '../models/task.dart';

class TaskDatabase {
  static const _dbName = 'taskforge.db';
  static const _dbVersion = 6;

  /// Если true (приложение), БД на ПК живёт в стабильной папке приложения.
  /// Тесты выключают, чтобы задавать свой каталог.
  static bool useStableDesktopPath = true;

  static final Random _rand = Random();

  /// Случайный стабильный ключ записи для синхронизации между устройствами.
  static String newKey() {
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(_rand.nextInt(16).toRadixString(16));
    }
    return sb.toString();
  }

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  /// Стабильный каталог для БД на ПК — чтобы данные не «терялись» при
  /// запуске приложения из другой папки (раньше база создавалась в рабочем
  /// каталоге и зависела от того, откуда запущен KHS.exe).
  static String desktopDataDir() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return join(appData, 'khs');
      }
    }
    if (Platform.isLinux) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return join(home, '.local', 'share', 'khs');
      }
    }
    return join(Directory.current.path, '.khs-data');
  }

  Future<void> _prepareDesktopDbPath() async {
    if (!useStableDesktopPath) return;
    final dir = desktopDataDir();
    await Directory(dir).create(recursive: true);
    // Перенос старой базы (рабочий каталог), если новая ещё не существует.
    final target = join(dir, _dbName);
    if (!File(target).existsSync()) {
      final legacyDir = join(
        Directory.current.path,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
      );
      final legacy = File(join(legacyDir, _dbName));
      if (legacy.existsSync()) {
        try {
          await legacy.copy(target);
          for (final suffix in ['-wal', '-shm']) {
            final f = File('$legacy$suffix');
            if (f.existsSync()) await f.copy('$target$suffix');
          }
        } catch (_) {}
      }
    }
    databaseFactoryFfi.setDatabasesPath(dir);
  }

  Future<Database> _open() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await _prepareDesktopDbPath();
    }
    final dir = await getDatabasesPath();
    final path = join(dir, _dbName);
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE tasks(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              notes TEXT,
              due_at INTEGER,
              priority INTEGER NOT NULL DEFAULT 1,
              completed INTEGER NOT NULL DEFAULT 0,
              recurrence TEXT NOT NULL DEFAULT '',
              reminder_at INTEGER,
              created_at INTEGER NOT NULL,
              completed_at INTEGER,
              category TEXT,
              client_key TEXT,
              deleted INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER,
              notify INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await db.execute('''
            CREATE TABLE notes(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              content TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              note_date INTEGER,
              client_key TEXT,
              deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE tasks ADD COLUMN category TEXT');
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE notes(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                content TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 4) {
            await db.execute('ALTER TABLE notes ADD COLUMN note_date INTEGER');
          }
          if (oldVersion < 5) {
            await db.execute('ALTER TABLE tasks ADD COLUMN client_key TEXT');
            await db.execute(
              'ALTER TABLE tasks ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute('ALTER TABLE tasks ADD COLUMN updated_at INTEGER');
            await db.execute('ALTER TABLE notes ADD COLUMN client_key TEXT');
            await db.execute(
              'ALTER TABLE notes ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              "UPDATE tasks SET client_key = lower(hex(randomblob(16))) "
              "WHERE client_key IS NULL OR client_key = ''",
            );
            await db.execute(
              "UPDATE notes SET client_key = lower(hex(randomblob(16))) "
              "WHERE client_key IS NULL OR client_key = ''",
            );
            await db.execute(
              'UPDATE tasks SET updated_at = created_at WHERE updated_at IS NULL',
            );
          }
          if (oldVersion < 6) {
            await db.execute(
              'ALTER TABLE tasks ADD COLUMN notify INTEGER NOT NULL DEFAULT 1',
            );
          }
        },
      ),
    );
  }

  Future<List<Task>> getTasks() async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(Task.fromMap).toList();
  }

  /// Все записи, включая удалённые — для синхронизации.
  Future<List<Map<String, dynamic>>> getAllTasks() async {
    final db = await database;
    return db.query('tasks', orderBy: 'created_at DESC');
  }

  Future<List<Task>> getTasksForDate(DateTime date) async {
    final day = DateTime(date.year, date.month, date.day);
    final nextDay = day.add(const Duration(days: 1));
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'deleted = 0 AND completed = 0 AND due_at >= ? AND due_at < ?',
      whereArgs: [day.millisecondsSinceEpoch, nextDay.millisecondsSinceEpoch],
      orderBy: 'priority DESC, due_at ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<List<Task>> getTodayTasks(DateTime now) async {
    return getTasksForDate(now);
  }

  Future<List<Task>> getUpcomingTasks() async {
    final db = await database;
    final rows = await db.query(
      'tasks',
      where: 'deleted = 0 AND completed = 0',
      orderBy: 'due_at ASC',
    );
    return rows.map(Task.fromMap).toList();
  }

  Future<int> insertTask(Task task) async {
    final map = task.toMap();
    map['client_key'] = task.clientKey ?? newKey();
    map['updated_at'] =
        task.updatedAt?.millisecondsSinceEpoch ??
        task.createdAt.millisecondsSinceEpoch;
    final db = await database;
    return db.insert('tasks', map);
  }

  Future<void> updateTask(Task task, {bool bumpUpdatedAt = true}) async {
    final map = task.toMap();
    if (bumpUpdatedAt) {
      map['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    }
    final db = await database;
    await db.update('tasks', map, where: 'id = ?', whereArgs: [task.id]);
  }

  Future<void> deleteTask(int id) async {
    final db = await database;
    await db.update(
      'tasks',
      {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Note>> getNotes() async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'deleted = 0',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  /// Все заметки, включая удалённые — для синхронизации.
  Future<List<Map<String, dynamic>>> getAllNotes() async {
    final db = await database;
    return db.query('notes', orderBy: 'updated_at DESC');
  }

  Future<int> insertNote(Note note) async {
    final map = note.toMap();
    map['client_key'] = note.clientKey ?? newKey();
    final db = await database;
    return db.insert('notes', map);
  }

  Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update(
      'notes',
      note.toMap(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  Future<void> deleteNote(int id) async {
    final db = await database;
    await db.update(
      'notes',
      {'deleted': 1, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Удалённые заметки — для корзины.
  Future<List<Note>> getDeletedNotes() async {
    final db = await database;
    final rows = await db.query(
      'notes',
      where: 'deleted = 1',
      orderBy: 'updated_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<void> restoreNote(int id) async {
    final db = await database;
    await db.update(
      'notes',
      {'deleted': 0, 'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Полное удаление записи из базы (без возможности восстановить).
  Future<void> purgeNote(int id) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> purgeTask(int id) async {
    final db = await database;
    await db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
}
