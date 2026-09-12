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

/// Ключ доступа для тестов: сервер принимает только непустой ключ (#18),
/// поэтому весь обмен в тестах идёт с реальным токеном (заголовок/X-KHS-Token
/// или шифрование тела).
const String testToken = 'test-access-key';

const Map<String, String> authHeader = {'X-KHS-Token': testToken};

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
    // Состояние сервера (счётчики replay, deviceId) пишется в .khs-data в
    // рабочей папке — стираем, чтобы тесты были независимы от запусков.
    final dataDir = Directory(p.join(Directory.current.path, '.khs-data'));
    if (dataDir.existsSync()) {
      dataDir.deleteSync(recursive: true);
    }
  });

  tearDownAll(() {
    final dataDir = Directory(p.join(Directory.current.path, '.khs-data'));
    if (dataDir.existsSync()) {
      dataDir.deleteSync(recursive: true);
    }
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
        token: testToken,
        onChanged: () async {},
      );
      await server.start();

      final client = SyncClient(
        db: dbClient,
        host: '127.0.0.1:$port',
        token: testToken,
        cid: 'phone-sync-both',
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
      token: testToken,
      onChanged: () async {},
    );
    await server.start();

    // Первый синк: телефон получает заметку.
    final client = SyncClient(
      db: dbClient,
      host: '127.0.0.1:$port',
      token: testToken,
      cid: 'phone-del',
    );
final firstSync = await client.sync();

    final clientNotes = await dbClient.getAllNotes();
    expect(clientNotes, hasLength(1));
    final key = clientNotes.single['client_key'] as String;

    // Удаляем на телефоне (мягкое удаление) и снова синхронизируемся.
    // Как и в приложении, клиент собирается заново с подтверждёнными
    // сервером счётчиками (anti-replay, #6).
    final localNote = (await dbClient.getAllNotes()).single;
    await dbClient.deleteNote(localNote['id'] as int);
    final client2 = SyncClient(
      db: dbClient,
      host: '127.0.0.1:$port',
      token: testToken,
      cid: 'phone-del',
      ctr: firstSync.nextCtr ?? 1,
      lastServerCtr: firstSync.serverCtr ?? 0,
    );
    final result2 = await client2.sync();
    expect(result2.ok, isTrue, reason: 'err=${result2.error}');

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
      token: testToken,
      onChanged: () async {},
    );
    await server.start();

    final client = SyncClient(
      db: dbClient,
      host: '127.0.0.1:$port',
      token: testToken,
      cid: 'phone-stand',
    );
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
        token: testToken,
        onChanged: () async {},
      );
      await server.start();

      final client = HttpClient();
      try {
        final metaReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/api/v1/update'),
        );
        authHeader.forEach(metaReq.headers.set);
        final metaRes = await metaReq.close();
        expect(metaRes.statusCode, 200);
        final meta = jsonDecode(
          await utf8.decoder.bind(metaRes).join(),
        ) as Map<String, dynamic>;
        expect(meta['version'], '99.0.0');
        expect(meta['android'], 'khs-test.apk');
        expect(meta['android_size'], 64);

        final fileReq = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/files/khs-test.apk'),
        );
        authHeader.forEach(fileReq.headers.set);
        final fileRes = await fileReq.close();
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
    String capturedHeader = '';
    server.listen((req) async {
      capturedHeader = req.headers.value('X-KHS-Token') ?? '';
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
      // В адресе токен больше не светится — он ушёл в заголовок (#18):
      // «Closure ...» в URL был багом интерполяции.
      expect(capturedUri, '/files/khs-1.2.13.apk');
      expect(capturedUri.contains('Closure'), isFalse);
      expect(capturedHeader, 'secret');
    } finally {
      await server.close(force: true);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('сервер отдаёт 403 для «мусорного» имени файла старого клиента (#17)',
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
        token: testToken,
        onChanged: () async {},
      );
      await server.start();

      final client = HttpClient();
      try {
        // Имя, которое просил старый битый клиент.
        final fallbackReq = await client.getUrl(
          Uri.parse(
            'http://127.0.0.1:$port/files/Closure:%20(String)%20=%3E%20String'
            '%20from%20Function%20\'_safeName@0\':.(filename)',
          ),
        );
        fallbackReq.headers.set('X-KHS-Token', testToken);
        final res = await fallbackReq.close();
        // Мусорное имя из старого битого клиента теперь вне allowlist — 403.
        expect(res.statusCode, 403);
        final body = jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
        expect(body['error'], 'not_allowed');
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
      token: testToken,
      onChanged: () async {},
    );
    await server.start();

    final client = SyncClient(
      db: dbClient,
      host: '127.0.0.1:$port',
      token: testToken,
      cid: 'phone-vault',
    );
    final result = await client.sync();
    expect(result.ok, isTrue, reason: 'err=${result.error}');
    expect(result.vaultPath, vault.path);

    await server.stop();
    for (final d in [dirServer, dirClient, vault]) {
      try {
        await d.delete(recursive: true);
      } catch (_) {}
    }
  });
}
