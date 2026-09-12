/// Чистая логика слияния записей между устройствами.
///
/// Записи сопоставляются по `client_key` (стабильный ключ, один и тот же
/// на всех устройствах). При конфликте выигрывает запись с более новым
/// `updated_at` (последний пишет первым). Удаление — это тоже состояние
/// записи (`deleted = 1`), поэтому оно побеждает, если новее.
class SyncEngine {
  /// Максимально допустимый «забег в будущее» времени обновления записи.
  /// Большее — зажимаем до [now]: часы устройства не должны решать
  /// конфликты за счёт накрученного времени.
  static const int maxFutureSkewMs = Duration.millisecondsPerDay * 1;

  static int _taskTime(Map<String, dynamic> row) =>
      row['updated_at'] as int? ?? row['created_at'] as int;

  static int _noteTime(Map<String, dynamic> row) => row['updated_at'] as int;

  /// Приводит подозрительно будущие времена записи к [now] (иначе оставляет
  /// ту же карту). Возвращает новую карту только если что-то поправил.
  static Map<String, dynamic> _clampRow(
    Map<String, dynamic> row,
    int now,
  ) {
    final limit = now + maxFutureSkewMs;
    var changed = false;
    for (final key in const ['updated_at', 'created_at']) {
      final v = row[key];
      if (v is int && v > limit) {
        changed = true;
        row = Map<String, dynamic>.from(row)..[key] = now;
      }
    }
    return row;
  }

  static List<Map<String, dynamic>> _clampAll(
    List<Map<String, dynamic>> rows,
    int? now,
  ) {
    if (now == null) return rows;
    return [for (final r in rows) _clampRow(r, now)];
  }

  /// Победитель по времени: `a` при равенстве, иначе новее.
  static Map<String, dynamic> _newer(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    required int Function(Map<String, dynamic>) time,
  }) {
    return time(a) >= time(b) ? a : b;
  }

  static Map<String, dynamic> newerTask(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) => _newer(a, b, time: _taskTime);

  static Map<String, dynamic> newerNote(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) => _newer(a, b, time: _noteTime);

  /// Сливает «свой» набор строк с чужим. Возвращает объединение по
  /// `client_key`, конфликты решены по времени. Строки без `client_key`
  /// остаются как есть (таких быть не должно после миграции в v5).
  ///
  /// Если задан [now] — «будущие» времена записей зажимаются до него,
  /// чтобы устройство с накрученными часами не выигрывало конфликты (#12).
  static List<Map<String, dynamic>> mergeTasks(
    List<Map<String, dynamic>> mine,
    List<Map<String, dynamic>> theirs, {
    int? now,
  }) {
    return _merge(mine, theirs, now: now, newer: newerTask);
  }

  static List<Map<String, dynamic>> mergeNotes(
    List<Map<String, dynamic>> mine,
    List<Map<String, dynamic>> theirs, {
    int? now,
  }) {
    return _merge(mine, theirs, now: now, newer: newerNote);
  }

  static List<Map<String, dynamic>> _merge(
    List<Map<String, dynamic>> mine,
    List<Map<String, dynamic>> theirs, {
    required int? now,
    required Map<String, dynamic> Function(Map<String, dynamic>, Map<String, dynamic>) newer,
  }) {
    final cleanMine = _clampAll(mine, now);
    final cleanTheirs = _clampAll(theirs, now);
    final byKey = <String, Map<String, dynamic>>{};
    final result = <Map<String, dynamic>>[];
    for (final row in cleanMine) {
      result.add(row);
      final key = row['client_key'];
      if (key is String) byKey[key] = row;
    }
    for (final row in cleanTheirs) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null) {
        result.add(row);
        byKey[key] = row;
      } else {
        final winner = newer(existing, row);
        final i = result.indexOf(existing);
        if (i != -1) result[i] = winner;
        byKey[key] = winner;
      }
    }
    return result;
  }

  static Map<String, dynamic> withoutId(Map<String, dynamic> row) {
    return Map<String, dynamic>.from(row)..remove('id');
  }
}
