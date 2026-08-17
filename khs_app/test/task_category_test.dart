import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/task.dart';
import 'package:khs/ui/app_theme.dart';

void main() {
  test('Task round-trips category via map', () {
    final task = Task(
      title: 'Встреча',
      category: 'Meetings',
      createdAt: DateTime(2026, 8, 15),
    );
    final restored = Task.fromMap(task.toMap());
    expect(restored.category, 'Meetings');
  });

  test('copyWith sets and clears category', () {
    final task = Task(title: 't', createdAt: DateTime(2026, 8, 15));
    expect(task.copyWith(category: 'Trip').category, 'Trip');
    expect(
      task.copyWith(category: 'Trip').copyWith(clearCategory: true).category,
      isNull,
    );
  });

  test('nextOccurrence keeps category', () {
    final task = Task(
      title: 'Ежедневно',
      dueAt: DateTime(2026, 8, 15, 9),
      recurrence: 'daily',
      category: 'General',
      createdAt: DateTime(2026, 8, 15),
    );
    expect(task.nextOccurrence().category, 'General');
  });

  test('groupColor is deterministic and stable', () {
    final a = AppTheme.groupColor('Meetings');
    final b = AppTheme.groupColor('Meetings');
    expect(a, b);
    expect(AppTheme.groupColor(''), AppTheme.accentBlue);
    final c = AppTheme.groupColor('Trip');
    expect(a, isNot(AppTheme.groupColor('Trip')));
    expect(AppTheme.groupPalette, contains(a));
    expect(AppTheme.groupPalette, contains(c));
  });
}
