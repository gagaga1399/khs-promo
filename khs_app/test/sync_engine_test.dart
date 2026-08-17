import 'package:flutter_test/flutter_test.dart';
import 'package:khs/services/sync_engine.dart';

Map<String, dynamic> task(
  String key,
  int updated, {
  String? title,
  bool deleted = false,
}) {
  return {
    'id': 1,
    'title': title ?? 'Задача $key',
    'notes': null,
    'due_at': null,
    'priority': 1,
    'completed': 0,
    'recurrence': '',
    'reminder_at': null,
    'category': null,
    'created_at': 100,
    'completed_at': null,
    'client_key': key,
    'deleted': deleted ? 1 : 0,
    'updated_at': updated,
  };
}

Map<String, dynamic> note(
  String key,
  int updated, {
  String? title,
  bool deleted = false,
}) {
  return {
    'id': 2,
    'title': title ?? 'Заметка $key',
    'content': '',
    'created_at': 100,
    'updated_at': updated,
    'note_date': null,
    'client_key': key,
    'deleted': deleted ? 1 : 0,
  };
}

void main() {
  group('SyncEngine.mergeTasks', () {
    test('при конфликте побеждает более новая запись', () {
      final mine = [task('a', 10, title: 'старая')];
      final theirs = [task('a', 20, title: 'новая')];
      final merged = SyncEngine.mergeTasks(mine, theirs);
      expect(merged.length, 1);
      expect(merged.single['title'], 'новая');
    });

    test('записи с разными ключами объединяются', () {
      final mine = [task('a', 10)];
      final theirs = [task('b', 10)];
      final merged = SyncEngine.mergeTasks(mine, theirs);
      expect(merged.length, 2);
    });

    test('удаление побеждает, если оно новее', () {
      final mine = [task('a', 10)];
      final theirs = [task('a', 20, deleted: true)];
      final merged = SyncEngine.mergeTasks(mine, theirs);
      expect(merged.single['deleted'], 1);
    });

    test('запись без client_key игнорируется при слиянии', () {
      final mine = [task('a', 10)];
      final theirs = [
        {'title': 'no key', 'created_at': 5},
      ];
      final merged = SyncEngine.mergeTasks(mine, theirs);
      expect(merged.length, 1);
    });
  });

  group('SyncEngine.mergeNotes', () {
    test('при конфликте побеждает более новая заметка', () {
      final mine = [note('n', 10, title: 'старая')];
      final theirs = [note('n', 20, title: 'новая')];
      final merged = SyncEngine.mergeNotes(mine, theirs);
      expect(merged.single['title'], 'новая');
    });

    test('равные по времени оставляют свою версию', () {
      final mine = [note('n', 10, title: 'моя')];
      final theirs = [note('n', 10, title: 'чужая')];
      final merged = SyncEngine.mergeNotes(mine, theirs);
      expect(merged.single['title'], 'моя');
    });
  });
}
