import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/note.dart';
import '../models/task.dart';
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

  const SyncClientResult({
    required this.status,
    this.error,
    this.notesBefore = const [],
    this.notesAfter = const [],
    this.vaultPath,
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

  SyncClient({required this.db, required this.host, required this.token});

  Uri get _base => Uri.parse('http://$host/api/v1');
  Uri get _syncUrl => Uri.parse('http://$host/api/v1/sync');

  Future<HttpClient> _client() async {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..idleTimeout = const Duration(seconds: 6);
  }

  /// Проверка доступности сервера (GET /api/v1/health).
  Future<bool> check() async {
    final client = await _client();
    try {
      final req = await client.getUrl(_base.replace(path: '/api/v1/health'));
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

    final payload = {'tasks': tasks, 'notes': notes, 'token': token};

    final client = await _client();
    try {
      final req = await client.postUrl(_syncUrl);
      req.headers.contentType = ContentType.json;
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
      final body = jsonDecode(text) as Map<String, dynamic>;

      final serverTasks = (body['tasks'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final serverNotes = (body['notes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      final localTasks = await db.getAllTasks();
      final localNotes = await db.getAllNotes();
      final mergedTasks = SyncEngine.mergeTasks(localTasks, serverTasks);
      final mergedNotes = SyncEngine.mergeNotes(localNotes, serverNotes);

      await _persistTasks(localTasks, mergedTasks);
      await _persistNotes(localNotes, mergedNotes);

      return SyncClientResult(
        status: 'ok',
        notesBefore: localNotes,
        notesAfter: mergedNotes,
        vaultPath: body['vaultPath'] is String
            ? body['vaultPath'] as String
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
