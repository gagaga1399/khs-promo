import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/note.dart';
import '../models/task.dart';
import 'sync_crypto.dart';
import 'sync_engine.dart';
import 'task_database.dart';

/// Результат синхронизации клиента (телефон).
class SyncClientResult {
  /// 'ok' | 'offline' | 'error'
  final String status;
  final Object? error;

  /// Заметки до и после слияния — для уведомлений о «пришедших» заметках.
  final List<Map<String, dynamic>> notesBefore;
  final List<Map<String, dynamic>> notesAfter;

  /// Путь к vault ПК, присланный сервером при синхронизации.
  final String? vaultPath;

  /// Идентификатор сервера (для защиты от незаметного переключения на
  /// чужой/другой KHS-сервер, #11).
  final String? serverDeviceId;

  /// Новые значения счётчиков для сохранения (anti-replay, #6).
  final int? nextCtr;
  final int? serverCtr;

  /// Новый ключ доступа, если сервер его сменил (#19).
  final String? newToken;

  const SyncClientResult({
    required this.status,
    this.error,
    this.notesBefore = const [],
    this.notesAfter = const [],
    this.vaultPath,
    this.serverDeviceId,
    this.nextCtr,
    this.serverCtr,
    this.newToken,
  });

  bool get ok => status == 'ok';
}

/// Клиент синхронизации: ходит на HTTP-сервер ПК и сливает локальную БД
/// с хранилищем ПК. Работает на телефоне; при недоступном ПК данные просто
/// остаются локальными и уйдут на ПК при следующем удачном соединении.
class SyncClient {
  final TaskDatabase db;
  final String host; // например 192.168.1.5:4680
  final String token;

  /// Стабильный идентификатор телефона (для счётчика replay).
  final String cid;

  /// Монотонный счётчик запросов телефона.
  final int ctr;

  /// Последний принятый счётчик ответов сервера.
  final int lastServerCtr;

  /// Идентификатор сервера, с которым уже синкались (или '' — ещё нет).
  final String pinnedDeviceId;

  SyncClient({
    required this.db,
    required this.host,
    required this.token,
    this.cid = '',
    this.ctr = 0,
    this.lastServerCtr = 0,
    this.pinnedDeviceId = '',
  });

  Uri get _healthUrl => Uri.parse('http://$host/api/v1/health');
  Uri get _syncUrl => Uri.parse('http://$host/api/v1/sync');

  Map<String, String> _authHeaders() =>
      token.isEmpty ? const <String, String>{} : {'X-KHS-Token': token};

  Future<HttpClient> _client() async {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 6);
  }

  /// Проверка доступности сервера (GET /api/v1/health). Сервер отвечает
  /// 200 только обладателю ключа (#18), поэтому ключ шлём и здесь.
  Future<bool> check() async {
    final client = await _client();
    try {
      final req = await client.getUrl(_healthUrl);
      _authHeaders().forEach(req.headers.set);
      final res = await req.close();
      await res.drain();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Выполняет синхронизацию: отправляет свою БД, получает слитую,
  /// применяет локально.
  Future<SyncClientResult> sync() async {
    final notesBefore = await db.getAllNotes();
    final tasks = await db.getAllTasks();
    final notes = notesBefore;
    final nextCtr = ctr + 1;

    final inner = jsonEncode({
      'tasks': tasks,
      'notes': notes,
      'cid': cid,
      'ctr': nextCtr,
    });
    final data = await SyncCrypto.encrypt(token, inner);
    final payload = {'v': 2, 'data': data};

    final client = await _client();
    try {
      final req = await client.postUrl(_syncUrl);
      req.headers.contentType = ContentType.json;
      _authHeaders().forEach(req.headers.set);
      req.write(jsonEncode(payload));
      final res = await req.close();
      final text = await utf8.decoder.bind(res).join();
      if (res.statusCode != 200) {
        return SyncClientResult(
          status: 'error',
          error: 'HTTP ${res.statusCode}: $text',
          notesBefore: notesBefore,
        );
      }
      final outer = jsonDecode(text) as Map<String, dynamic>;
      if ((outer['v'] as int?) != 2) {
        return SyncClientResult(
          status: 'error',
          error: 'bad protocol',
          notesBefore: notesBefore,
        );
      }
      final body = jsonDecode(
            await SyncCrypto.decrypt(token, outer['data'] as String),
          )
          as Map<String, dynamic>;

      // #11: сервер должен быть тем же, с кем уже синкались. Другой
      // (например, другой KHS-ПК) — отказываемся применять его данные,
      // пока пользователь не подтвердит смену.
      final remoteId = body['deviceId'];
      if (remoteId is String &&
          remoteId.isNotEmpty &&
          pinnedDeviceId.isNotEmpty &&
          pinnedDeviceId != remoteId) {
        return SyncClientResult(
          status: 'error',
          error: 'server_changed',
          notesBefore: notesBefore,
          serverDeviceId: remoteId,
        );
      }

      // #6: серверные ответы тоже не должны повторяться.
      final sctr = body['sctr'];
      if (sctr is int) {
        if (lastServerCtr > 0 && sctr <= lastServerCtr) {
          return SyncClientResult(
            status: 'error',
            error: 'stale_reply',
            notesBefore: notesBefore,
          );
        }
      }

      final serverTasks = (body['tasks'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final serverNotes = (body['notes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final localTasks = await db.getAllTasks();
      final localNotes = await db.getAllNotes();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final mergedTasks = SyncEngine.mergeTasks(localTasks, serverTasks, now: nowMs);
      final mergedNotes = SyncEngine.mergeNotes(localNotes, serverNotes, now: nowMs);

      await _persistTasks(localTasks, mergedTasks);
      await _persistNotes(localNotes, mergedNotes);

      return SyncClientResult(
        status: 'ok',
        notesBefore: localNotes,
        notesAfter: mergedNotes,
        vaultPath: body['vaultPath'] is String
            ? body['vaultPath'] as String
            : null,
        serverDeviceId: remoteId is String && remoteId.isNotEmpty
            ? remoteId
            : null,
        nextCtr: nextCtr,
        serverCtr: sctr is int ? sctr : null,
        newToken: body['newToken'] is String
            ? body['newToken'] as String
            : null,
      );
    } on SocketException catch (e) {
      return SyncClientResult(
        status: 'offline',
        error: e,
        notesBefore: notesBefore,
      );
    } on TimeoutException catch (e) {
      return SyncClientResult(
        status: 'offline',
        error: e,
        notesBefore: notesBefore,
      );
    } catch (e) {
      return SyncClientResult(
        status: 'error',
        error: e,
        notesBefore: notesBefore,
      );
    } finally {
      client.close();
    }
  }

  Future<void> _persistTasks(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> merged,
  ) async {
    final byKey = <String, Map<String, dynamic>>{
      for (final r in local)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };
    for (final row in merged) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null) {
        await db.insertTask(Task.fromMap(SyncEngine.withoutId(row)));
      } else if (identical(row, existing)) {
        // Наша же версия победила — менять нечего.
      } else {
        final winner = SyncEngine.newerTask(existing, row);
        if (!identical(winner, existing)) {
          final withId = Map<String, dynamic>.from(row)
            ..['id'] = existing['id'];
          await db.updateTask(Task.fromMap(withId), bumpUpdatedAt: false);
        }
      }
    }
  }

  Future<void> _persistNotes(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> merged,
  ) async {
    final byKey = <String, Map<String, dynamic>>{
      for (final r in local)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };
    for (final row in merged) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null) {
        await db.insertNote(Note.fromMap(SyncEngine.withoutId(row)));
      } else if (identical(row, existing)) {
        // Наша же версия победила — менять нечего.
      } else {
        final winner = SyncEngine.newerNote(existing, row);
        if (!identical(winner, existing)) {
          final withId = Map<String, dynamic>.from(row)
            ..['id'] = existing['id'];
          await db.updateNote(Note.fromMap(withId));
        }
      }
    }
  }
}