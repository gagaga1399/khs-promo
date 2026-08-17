import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/task.dart';
import 'package:khs/services/task_database.dart';
import 'package:khs/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    TaskDatabase.useStableDesktopPath = false;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('khs_progress_test');
    databaseFactory = databaseFactoryFfi;
    databaseFactoryFfi.setDatabasesPath(tempDir.path);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Task task({
    required String title,
    int priority = 1,
    String? category,
    DateTime? dueAt,
    bool completed = false,
    DateTime? completedAt,
  }) =>
      Task(
        title: title,
        priority: priority,
        category: category,
        dueAt: dueAt,
        completed: completed,
        completedAt: completedAt,
        notify: false,
        createdAt: DateTime(2026, 8, 15),
      );

  Future<AppState> makeState() async {
    final state = AppState();
    await state.addTask(
      task(title: 'Высокий', priority: 2),
    );
    return state;
  }

  test('progressPercentForPriority считает по весу', () async {
    final state = await makeState();
    await state.addTask(task(title: 'Высокий 2', priority: 2));
    await state.addTask(task(title: 'Средний', priority: 1));

    expect(state.progressPercentForPriority(2), 0);

    await state.addTask(
      task(title: 'Высокий готов', priority: 2, completed: true),
    );

    // Всего задач с priority 2 — три, выполнена одна.
    expect(state.progressPercentForPriority(2), 33);
    expect(state.progressPercentForPriority(1), 0);
    expect(state.progressPercentForPriority(0), 0);
  });

  test('overdueCount считает просроченные по группам', () async {
    final state = await makeState();
    final now = DateTime.now();
    await state.addTask(
      task(
        title: 'Просроченная',
        category: 'Meetings',
        dueAt: now.subtract(const Duration(days: 1)),
      ),
    );
    await state.addTask(
      task(
        title: 'Просроченная другая',
        dueAt: now.subtract(const Duration(days: 2)),
      ),
    );
    await state.addTask(
      task(title: 'Не просрочена', dueAt: now.add(const Duration(days: 1))),
    );

    expect(state.overdueCount(null), 2);
    expect(state.overdueCount('Meetings'), 1);
  });

  test('dailyGoalPercent и streakDays по выполненным сегодня', () async {
    final state = await makeState();
    await state.setDailyGoal(2);
    expect(state.dailyGoal, 2);

    final now = DateTime.now();
    await state.addTask(
      task(title: 'Готова 1', completed: true, completedAt: now),
    );

    expect(state.doneToday, 1);
    expect(state.dailyGoalPercent, 50);
    // Цель (2) сегодня не выполнена — серия считается от вчера, задач нет.
    expect(state.streakDays, 0);

    await state.addTask(
      task(title: 'Готова 2', completed: true, completedAt: now),
    );
    expect(state.doneToday, 2);
    expect(state.dailyGoalPercent, 100);
    // Сегодня выполнено — серия начинается с сегодняшнего дня.
    expect(state.streakDays, 1);

    final yesterday = now.subtract(const Duration(days: 1));
    await state.addTask(
      task(title: 'Вчера 1', completed: true, completedAt: yesterday),
    );
    await state.addTask(
      task(title: 'Вчера 2', completed: true, completedAt: yesterday),
    );
    expect(state.streakDays, 2);
  });

  test('barEnabled / setBarEnabled переключают и сохраняют выбор', () async {
    final state = await makeState();
    expect(state.barEnabled(AppState.barGoal), isTrue);

    state.setBarEnabled(AppState.barGoal, false);
    expect(state.barEnabled(AppState.barGoal), isFalse);
    expect(state.barEnabled(AppState.barWeek), isTrue);

    state.setBarEnabled(AppState.barGoal, true);
    expect(state.barEnabled(AppState.barGoal), isTrue);
  });

  test('doneCountsLast возвращает ряд за N дней (сегодня — последний)', () async {
    final state = await makeState();
    final now = DateTime.now();
    await state.addTask(
      task(title: 'Готова сегодня', completed: true, completedAt: now),
    );
    await state.addTask(
      task(
        title: 'Готова вчера',
        completed: true,
        completedAt: now.subtract(const Duration(days: 1)),
      ),
    );

    final row = state.doneCountsLast(7);
    expect(row, hasLength(7));
    expect(row.last, 1); // сегодня
    expect(row[row.length - 2], 1); // вчера
  });

  test('priorityFilter показывает только задачи выбранного приоритета', () async {
    final state = await makeState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await state.addTask(
      task(title: 'Высокий', priority: 2, dueAt: today.add(const Duration(hours: 10))),
    );
    await state.addTask(
      task(title: 'Средний', priority: 1, dueAt: today.add(const Duration(hours: 11))),
    );
    await state.addTask(
      task(title: 'Низкий', priority: 0, dueAt: today.add(const Duration(hours: 12))),
    );

    state.setPriorityFilter(2);
    expect(state.filteredTasks.map((t) => t.title), ['Высокий']);

    state.setPriorityFilter(0);
    expect(state.filteredTasks.map((t) => t.title), ['Низкий']);

    state.setPriorityFilter(1);
    expect(state.filteredTasks.map((t) => t.title), ['Средний']);

    state.setPriorityFilter(null);
    expect(state.filteredTasks, hasLength(3));
  });

  test('progressPercentDueToday и DueWeek по срокам', () async {
    final state = await makeState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await state.addTask(task(title: 'Сегодня', dueAt: today.add(const Duration(hours: 12))));
    await state.addTask(task(title: 'Сегодня 2', dueAt: today.add(const Duration(hours: 18))));
    await state.addTask(task(title: 'Через 3 дня', dueAt: today.add(const Duration(days: 3))));

    expect(state.progressPercentDueToday(), 0);

    await state.addTask(
      task(
        title: 'Сегодня готова',
        dueAt: today.add(const Duration(hours: 12)),
        completed: true,
      ),
    );

    // Сегодня — три задачи со сроком, выполнена одна.
    expect(state.progressPercentDueToday(), 33);
    // Всего в неделе (сегодня + 3 дня) четыре задачи, выполнена одна.
    expect(state.progressPercentDueWeek(), 25);
  });
}
