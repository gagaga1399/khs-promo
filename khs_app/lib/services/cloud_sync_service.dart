import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note.dart';
import '../models/task.dart';
import 'sync_engine.dart';
import 'task_database.dart';

/// Итог одного прохода облачной синхронизации.
class CloudSyncResult {
  /// 'ok' — синхронизировались, 'skipped' — нечего делать или нет входа,
  /// 'error' — не получилось, но данные на устройстве целы.
  final String status;
  final Object? error;
  final int pushed;
  final int pulled;

  /// Заметки до и после слияния — чтобы показать, что пришло с других
  /// устройств.
  final List<Map<String, dynamic>> notesBefore;
  final List<Map<String, dynamic>> notesAfter;

  const CloudSyncResult({
    required this.status,
    this.error,
    this.pushed = 0,
    this.pulled = 0,
    this.notesBefore = const [],
    this.notesAfter = const [],
  });
}

/// Синхронизация задач и заметок с облаком Firestore.
///
/// Записи лежат по пути `users/{uid}/tasks/{client_key}` и
/// `users/{uid}/notes/{client_key}`: идентификатор документа — это тот же
/// `client_key`, что и в локальной базе, поэтому обе копии записи
/// сопоставляются без всяких преобразований. Слияние — то же, что и в
/// локальной синхронизации с ПК ([SyncEngine]): побеждает запись с более
/// новым `updated_at`, удаление — это состояние `deleted = 1`.
///
/// Права доступа проверяет Firestore: прочитать или изменить запись другого
/// пользователя нельзя, даже зная точный путь.
class CloudSyncService {
  CloudSyncService({
    required this.db,
    required this.uidProvider,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final TaskDatabase db;

  /// Идентификатор текущего пользователя или null, если входа нет. Функция, а
  /// не сам FirebaseAuth, чтобы сервис можно было проверить без моков платформы.
  final String? Function() uidProvider;

  final FirebaseFirestore _firestore;

  /// Сколько строк отправлять за раз: Firestore просит не больше 500 операций
  /// в одной транзакции, а крупный проход лучше разбить, чем упираться в
  /// квоту записи при плохом соединении.
  static const int _batchSize = 200;

  CollectionReference<Map<String, dynamic>> _collection(
    String uid,
    String name,
  ) => _firestore.collection('users').doc(uid).collection(name);

  /// Firestore не принимает null в значениях полей, а локальные строки
  /// содержат пустые колонки (например `category`). Поэтому пустые значения
  /// убираем, а на чтении отсутствие поля и null равнозначны.
  static Map<String, dynamic> _stripNulls(Map<String, dynamic> row) {
    final out = <String, dynamic>{};
    for (final entry in row.entries) {
      final v = entry.value;
      if (v == null) continue;
      if (v is Map) {
        final nested = _stripNulls(Map<String, dynamic>.from(v));
        if (nested.isNotEmpty) out[entry.key] = nested;
        continue;
      }
      out[entry.key] = v;
    }
    return out;
  }

  static Map<String, dynamic> _fromDoc(Map<String, dynamic> data) {
    final row = <String, dynamic>{};
    for (final entry in data.entries) {
      final v = entry.value;
      if (v == Map && v.containsKey('__')) continue;
      row[entry.key] = v;
    }
    return row;
  }

  Future<List<Map<String, dynamic>>> _pull(String uid, String name) async {
    final snapshot = await _collection(uid, name).get();
    return [
      for (final doc in snapshot.docs)
        _fromDoc({...doc.data(), 'client_key': doc.id}),
    ];
  }

  Future<void> _push(
    String uid,
    String name,
    List<Map<String, dynamic>> rows,
  ) async {
    final collection = _collection(uid, name);
    for (var i = 0; i < rows.length; i += _batchSize) {
      final chunk = rows.skip(i).take(_batchSize).toList();
      final batch = _firestore.batch();
      for (final row in chunk) {
        final key = row['client_key'];
        if (key is! String || key.isEmpty) continue;
        batch.set(collection.doc(key), _stripNulls(SyncEngine.withoutId(row)));
      }
      if (chunk.isNotEmpty) await batch.commit();
    }
  }

  Future<CloudSyncResult> run() async {
    final uid = uidProvider();
    if (uid == null || uid.isEmpty) {
      return const CloudSyncResult(status: 'skipped');
    }

    final localTasks = await db.getAllTasks();
    final localNotes = await db.getAllNotes();

    try {
      final remoteTasks = await _pull(uid, 'tasks');
      final remoteNotes = await _pull(uid, 'notes');

      final mergedTasks = SyncEngine.mergeTasks(
        localTasks,
        remoteTasks,
        now: DateTime.now().millisecondsSinceEpoch,
      );
      final mergedNotes = SyncEngine.mergeNotes(
        localNotes,
        remoteNotes,
        now: DateTime.now().millisecondsSinceEpoch,
      );

      final tasksPushed = await _applyTasks(localTasks, mergedTasks);
      final notesPushed = await _applyNotes(localNotes, mergedNotes);

      if (tasksPushed.isNotEmpty) {
        await _push(uid, 'tasks', tasksPushed);
      }
      if (notesPushed.isNotEmpty) {
        await _push(uid, 'notes', notesPushed);
      }

      return CloudSyncResult(
        status: 'ok',
        pushed: tasksPushed.length + notesPushed.length,
        pulled:
            (mergedTasks.length - localTasks.length).abs() +
            (mergedNotes.length - localNotes.length).abs(),
        notesBefore: localNotes,
        notesAfter: mergedNotes,
      );
    } catch (e) {
      // Сеть отвалилась или прав нет: локальные данные не трогаем, приложение
      // продолжает работать, попробуем на следующем проходе.
      return CloudSyncResult(status: 'error', error: e);
    }
  }

  /// Раскладывает результат слияния по локальной базе и возвращает строки,
  /// которые нужно отправить в облако (локальные победители).
  ///
  /// Победителя определяем по времени записи, а не по тому, совпала ли ссылка
  /// на карту: [SyncEngine] при равных временах оставляет локальную версию, но
  /// сравнивать карты по ссылке нельзя — одинаковые строки не обязаны быть
  /// одним и тем же объектом.
  Future<List<Map<String, dynamic>>> _applyTasks(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> merged,
  ) async {
    final byKey = <String, Map<String, dynamic>>{
      for (final r in local)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };
    final toPush = <Map<String, dynamic>>[];
    for (final row in merged) {
      final key = row['client_key'];
      if (key is! String || key.isEmpty) continue;
      final existing = byKey[key];
      if (existing == null) {
        await db.insertTask(Task.fromMap(SyncEngine.withoutId(row)));
        toPush.add(row);
      } else if (_taskTime(row) > _taskTime(existing)) {
        // Пришла более новая версия: кладём её локально без задирания
        // updated_at и отправляем в облако.
        final withId = Map<String, dynamic>.from(row)..['id'] = existing['id'];
        await db.updateTask(Task.fromMap(withId), bumpUpdatedAt: false);
        toPush.add(row);
      } else {
        // Наша версия не старше — она и есть победитель.
        toPush.add(existing);
      }
    }
    return toPush;
  }

  Future<List<Map<String, dynamic>>> _applyNotes(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> merged,
  ) async {
    final byKey = <String, Map<String, dynamic>>{
      for (final r in local)
        if (r['client_key'] is String) r['client_key'] as String: r,
    };
    final toPush = <Map<String, dynamic>>[];
    for (final row in merged) {
      final key = row['client_key'];
      if (key is! String || key.isEmpty) continue;
      final existing = byKey[key];
      if (existing == null) {
        await db.insertNote(Note.fromMap(SyncEngine.withoutId(row)));
        toPush.add(row);
      } else if (_noteTime(row) > _noteTime(existing)) {
        final withId = Map<String, dynamic>.from(row)..['id'] = existing['id'];
        await db.updateNote(Note.fromMap(withId));
        toPush.add(row);
      } else {
        toPush.add(existing);
      }
    }
    return toPush;
  }

  /// Время задачи: обновление, а у только что созданной — создание.
  static int _taskTime(Map<String, dynamic> row) =>
      row['updated_at'] as int? ?? row['created_at'] as int;

  static int _noteTime(Map<String, dynamic> row) => row['updated_at'] as int;
}
