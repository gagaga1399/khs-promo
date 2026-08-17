import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/note.dart';

void main() {
  test('Note round-trips via map', () {
    final note = Note(
      id: 7,
      title: 'Идеи',
      content: 'Первая строка\nвторая',
      createdAt: DateTime(2026, 8, 15, 10),
      updatedAt: DateTime(2026, 8, 15, 11),
    );
    final restored = Note.fromMap(note.toMap());
    expect(restored.id, 7);
    expect(restored.title, 'Идеи');
    expect(restored.content, 'Первая строка\nвторая');
    expect(restored.updatedAt, DateTime(2026, 8, 15, 11));
  });

  test('Note round-trips daily date via map', () {
    final note = Note(
      title: 'День',
      content: '',
      createdAt: DateTime(2026, 8, 15, 10),
      updatedAt: DateTime(2026, 8, 15, 11),
      date: DateTime(2026, 8, 15),
    );
    final restored = Note.fromMap(note.toMap());
    expect(restored.date, DateTime(2026, 8, 15));
    final standalone = Note(
      title: 'Без даты',
      content: '',
      createdAt: DateTime(2026, 8, 15, 10),
      updatedAt: DateTime(2026, 8, 15, 11),
    );
    expect(Note.fromMap(standalone.toMap()).date, isNull);
    expect(
      note.copyWith(title: 'Новое').date,
      DateTime(2026, 8, 15),
      reason: 'copyWith должен сохранять дату',
    );
  });

  test('Note snippet is first non-empty line', () {
    final base = DateTime(2026, 8, 15);
    final note = Note(
      title: 't',
      content: '\n\nПервая строка\nвторая',
      createdAt: base,
      updatedAt: base,
    );
    expect(note.snippet, 'Первая строка');
    final empty = Note(title: 't', createdAt: base, updatedAt: base);
    expect(empty.snippet, '');
  });
}
