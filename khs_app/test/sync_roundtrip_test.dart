import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/note.dart';
import 'package:khs/models/task.dart';
import 'package:khs/services/obsidian_service.dart';
import 'package:khs/services/sync_client.dart';
import 'package:khs/services/sync_server.dart';
import 'package:khs/services/task_database.dart';
import 'package:khs/services/update_checker.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<int> _freePort() async {
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = srv.port;
  await srv.close();
  return port;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    TaskDatabase.useStableDesktopPath = false;
  });

  test(
    'телефон -> ПК: данные сливаются в обе стороны, Obsidian пишется',
    () async {
      final dirServer = await Directory.systemTemp.createTemp('khs_srv');
      final dirClient = await Directory.systemTemp.createTemp('khs_cli');
      final vault = await Directory.systemTemp.createTemp('khs_vault');

      databaseFactory = databaseFactoryFfi;
      databaseFactoryFfi.setDatabasesPath(dirServer.path);
      final dbServer = TaskDatabase();
      await dbServer.insertNote(
        Note(
          title: 'С ПК',
          content: 'локальная заметка ПК',
          createdAt: DateTime(2026, 8, 15, 10),
          updatedAt: DateTime(2026, 8, 15, 10),
        ),
      );

      databaseFactoryFfi.setDatabasesPath(dirClient.path);
      final dbClient = TaskDatabase();
      await dbClient.insertTask(
        Task(
          title: 'С телефона',
          createdAt: DateTime(2026, 8, 15, 12),
          updatedAt: DateTime(2026, 8, 15, 12),
        ),
      );
      // Заметка создана на телефоне с датой — она должна уйти в Obsidian на ПК.
      await dbClient.insertNote(
        Note(
          title: 'Дневная',
          content: 'тело дневной заметки',
          date: DateTime(2026, 8, 15),
          createdAt: DateTime(2026, 8, 15, 11),
          updatedAt: DateTime(2026, 8, 15, 11),
        ),
      );

      final port = await _freePort();
      final server = SyncServer(
        db: dbServer,
        obsidian: ObsidianService(vault.path),
        port: port,
        token: '',
        onChanged: () async {},
      );
      await server.start();

      final client = SyncClient(
        db: dbClient,
        host: '127.0.0.1:$port',
        token: '',
      );

      final result = await client.sync();
      expect(result.ok, isTrue);

      // Телефон получил заметки ПК.
      final clientNotes = await dbClient.getAllNotes();
      final titles = clientNotes.map((m) => m['title']).toList();
      expect(titles, containsAll(['С ПК', 'Дневная']));

      // ПК получил задачу телефона.
      final serverTasks = await dbServer.getAllTasks();
      expect(serverTasks.map((m) => m['title']), contains('С телефона'));

      // Дневная заметка записана в Obsidian на ПК.
      final file = File(
        p.join(vault.path, 'даты', '2026', 'месяцы', 'август', '2026-08-15.md'),
      );
      expect(await file.exists(), isTrue);
      final content = await file.readAsString();
      expect(content, contains('## Заметка'));
      expect(content, contains('тело дневной заметки'));

      await server.stop();

      // Удаляем временные каталоги.
      for (final d in [dirServer, dirClient, vault]) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    },
  );

  test('удаление заметки на телефоне доходит до сервера', () async {
    final dirServer = await Directory.systemTemp.createTemp('khs_srv2');
    final dirClient = await Directory.systemTemp.createTemp('khs_cli2');
    final vault = await Directory.systemTemp.createTemp('khs_vault2');

    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(dirServer.path);
    final dbServer = TaskDatabase();
    final noteId = await dbServer.insertNote(
      Note(
        title: 'Будет удалена',
        content: 'текст',
        createdAt: DateTime(2026, 8, 15, 10),
        updatedAt: DateTime(2026, 8, 15, 10),
      ),
    );

    databaseFactoryFfi.setDatabasesPath(dirClient.path);
    final dbClient = TaskDatabase();

    final port = await _freePort();
    final server = SyncServer(
      db: dbServer,
      obsidian: ObsidianService(vault.path),
      port: port,
      token: '',
      onChanged: () async {},
    );
    await server.start();

    // Первый синк: телефон получает заметку.
    final client = SyncClient(db: dbClient, host: '127.0.0.1:$port', token: '');
    await client.sync();

    final clientNotes = await dbClient.getAllNotes();
    expect(clientNotes, hasLength(1));
    final key = clientNotes.single['client_key'] as String;

    // Удаляем на телефоне (мягкое удаление) и снова синхронизируемся.
    final localNote = (await dbClient.getAllNotes()).single;
    await dbClient.deleteNote(localNote['id'] as int);
    final result2 = await client.sync();
    expect(result2.ok, isTrue);

    // Сервер тоже пометил заметку удалённой.
    final serverNotes = await dbServer.getAllNotes();
    expect(serverNotes.single['deleted'], 1);
    expect(serverNotes.single['client_key'], key);
    expect(noteId, isNotNull);

    await server.stop();
    for (final d in [dirServer, dirClient, vault]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('отдельная заметка с телефона пишется файлом в Obsidian', () async {
    final dirServer = await Directory.systemTemp.createTemp('khs_srv_stand');
    final dirClient = await Directory.systemTemp.createTemp('khs_cli_stand');
    final vault = await Directory.systemTemp.createTemp('khs_vault_stand');

    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(dirServer.path);
    final dbServer = TaskDatabase();

    databaseFactoryFfi.setDatabasesPath(dirClient.path);
    final dbClient = TaskDatabase();
    await dbClient.insertNote(
      Note(
        title: 'Идеи',
        content: 'отдельная заметка без даты',
        createdAt: DateTime(2026, 8, 16, 10),
        updatedAt: DateTime(2026, 8, 16, 10),
      ),
    );

    final port = await _freePort();
    final server = SyncServer(
      db: dbServer,
      obsidian: ObsidianService(vault.path),
      port: port,
      token: '',
      onChanged: () async {},
    );
    await server.start();

    final client = SyncClient(db: dbClient, host: '127.0.0.1:$port', token: '');
    final result = await client.sync();
    expect(result.ok, isTrue);

    final file = File(p.join(vault.path, 'заметки', 'Идеи.md'));
    expect(await file.exists(), isTrue);
    final content = await file.readAsString();
    expect(content, contains('отдельная заметка без даты'));

    await server.stop();
    for (final d in [dirServer, dirClient, vault]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('сервер раздаёт update.json и файл обновления', () async {
    final dirServer = await Directory.systemTemp.createTemp('khs_upd');
    final vault = await Directory.systemTemp.createTemp('khs_vault_upd');

    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(dirServer.path);
    final dbServer = TaskDatabase();

    final updatesDir = Directory(p.join(Directory.current.path, 'updates'));
    await updatesDir.create(recursive: true);
    try {
      await File(p.join(updatesDir.path, 'khs-test.apk'))
          .writeAsBytes(List.filled(64, 7));
      // BOM из Windows-редакторов не должен ломать парсинг.
      await File(p.join(updatesDir.path, 'update.json')).writeAsString(
        '\uFEFF${jsonEncode({'version': '99.0.0', 'notes': 'тестовая версия', 'android': 'khs-test.apk'})}',
      );

      final port = await _freePort();
      final server = SyncServer(
        db: dbServer,
        obsidian: ObsidianService(vault.path),
        port: port,
        token: '',
        onChanged: () async {},
      );
      await server.start();

      final client = HttpClient();
      try {
        final metaRes = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/api/v1/update'),
        )).close();
        expect(metaRes.statusCode, 200);
        final meta = jsonDecode(
          await utf8.decoder.bind(metaRes).join(),
        ) as Map<String, dynamic>;
        expect(meta['version'], '99.0.0');
        expect(meta['android'], 'khs-test.apk');
        expect(meta['android_size'], 64);

        final fileRes = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/files/khs-test.apk'),
        )).close();
        expect(fileRes.statusCode, 200);
        final bytes = await fileRes.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(bytes, hasLength(64));
      } finally {
        client.close();
        await server.stop();
      }
    } finally {
      try {
        await updatesDir.delete(recursive: true);
      } catch (_) {}
      for (final d in [dirServer, vault]) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
  });

  test('клиент скачивает файл по правильному URL (без бага интерполяции)',
      () async {
    final port = await _freePort();
    final body = List<int>.filled(128, 3);
    String capturedUri = '';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server.listen((req) async {
      capturedUri =
          '${req.uri.path}${req.uri.hasQuery ? '?${req.uri.query}' : ''}';
      req.response
        ..statusCode = 200
        ..contentLength = body.length;
      req.response.add(body);
      await req.response.close();
    });

    final dir = await Directory.systemTemp.createTemp('khs_dl');
    try {
      final checker = UpdateChecker(host: '127.0.0.1:$port', token: 'secret');
      final file = await checker.download('khs-1.2.13.apk', dir);
      expect(await file.readAsBytes(), body);
      // Раньше URL получался вида «Closure: (String) => String ...» — это баг.
      expect(capturedUri, '/files/khs-1.2.13.apk?token=secret');
      expect(capturedUri.contains('Closure'), isFalse);
    } finally {
      await server.close(force: true);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('сервер отдаёт android-файл для «мусорного» имени старого клиента',
      () async {
    final dirServer = await Directory.systemTemp.createTemp('khs_upd_fb');
    final vault = await Directory.systemTemp.createTemp('khs_vault_fb');

    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(dirServer.path);
    final dbServer = TaskDatabase();

    final updatesDir = Directory(p.join(Directory.current.path, 'updates'));
    await updatesDir.create(recursive: true);
    try {
      await File(p.join(updatesDir.path, 'khs-fallback.apk'))
          .writeAsBytes(List.filled(48, 9));
      await File(p.join(updatesDir.path, 'update.json')).writeAsString(
        jsonEncode({
          'version': '98.0.0',
          'notes': '',
          'android': 'khs-fallback.apk',
        }),
      );

      final port = await _freePort();
      final server = SyncServer(
        db: dbServer,
        obsidian: ObsidianService(vault.path),
        port: port,
        token: '',
        onChanged: () async {},
      );
      await server.start();

      final client = HttpClient();
      try {
        // Имя, которое просил старый битый клиент.
        final res = await (await client.getUrl(
          Uri.parse(
            'http://127.0.0.1:$port/files/Closure:%20(String)%20=%3E%20String'
            '%20from%20Function%20\'_safeName@0\':.(filename)',
          ),
        )).close();
        expect(res.statusCode, 200);
        final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
        expect(bytes, hasLength(48));
      } finally {
        client.close();
        await server.stop();
      }
    } finally {
      try {
        await updatesDir.delete(recursive: true);
      } catch (_) {}
      for (final d in [dirServer, vault]) {
        try {
          await d.delete(recursive: true);
        } catch (_) {}
      }
    }
  });

  test('сервер присылает путь к vault ПК при синхронизации', () async {
    final dirServer = await Directory.systemTemp.createTemp('khs_srv_vp');
    final dirClient = await Directory.systemTemp.createTemp('khs_cli_vp');
    final vault = await Directory.systemTemp.createTemp('khs_vault_vp');

    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(dirServer.path);
    final dbServer = TaskDatabase();

    databaseFactoryFfi.setDatabasesPath(dirClient.path);
    final dbClient = TaskDatabase();

    final port = await _freePort();
    final server = SyncServer(
      db: dbServer,
      obsidian: ObsidianService(vault.path),
      port: port,
      token: '',
      onChanged: () async {},
    );
    await server.start();

    final client = SyncClient(
      db: dbClient,
      host: '127.0.0.1:$port',
      token: '',
    );
    final result = await client.sync();
    expect(result.ok, isTrue);
    expect(result.vaultPath, vault.path);

    await server.stop();
    for (final d in [dirServer, dirClient, vault]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });
}
