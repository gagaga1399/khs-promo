/// Чистая логика слияния записей между устройствами.
///
/// Записи сопоставляются по `client_key` (стабильный ключ, один и тот же
/// на всех устройствах). При конфликте выигрывает запись с более новым
/// `updated_at` (последний пишет первым). Удаление — это тоже состояние
/// записи (`deleted = 1`), поэтому оно побеждает, если новее.
class SyncEngine {
  static int _taskTime(Map<String, dynamic> row) =>
      row['updated_at'] as int? ?? row['created_at'] as int;

  static int _noteTime(Map<String, dynamic> row) => row['updated_at'] as int;

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
  static List<Map<String, dynamic>> mergeTasks(
    List<Map<String, dynamic>> mine,
    List<Map<String, dynamic>> theirs,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    final result = <Map<String, dynamic>>[];
    for (final row in mine) {
      result.add(row);
      final key = row['client_key'];
      if (key is String) byKey[key] = row;
    }
    for (final row in theirs) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null) {
        result.add(row);
        byKey[key] = row;
      } else {
        final winner = newerTask(existing, row);
        final i = result.indexOf(existing);
        if (i != -1) result[i] = winner;
        byKey[key] = winner;
      }
    }
    return result;
  }

  static List<Map<String, dynamic>> mergeNotes(
    List<Map<String, dynamic>> mine,
    List<Map<String, dynamic>> theirs,
  ) {
    final byKey = <String, Map<String, dynamic>>{};
    final result = <Map<String, dynamic>>[];
    for (final row in mine) {
      result.add(row);
      final key = row['client_key'];
      if (key is String) byKey[key] = row;
    }
    for (final row in theirs) {
      final key = row['client_key'];
      if (key is! String) continue;
      final existing = byKey[key];
      if (existing == null) {
        result.add(row);
        byKey[key] = row;
      } else {
        final winner = newerNote(existing, row);
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
