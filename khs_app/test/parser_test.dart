import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/task.dart';
import 'package:khs/utils/task_parser.dart';

void main() {
  final parser = TaskParser();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = today.add(const Duration(days: 1));

  ParsedTask parse(String input) => parser.parse(input);

  group('TaskParser', () {
    test('parses plain title', () {
      final p = parse('buy milk');
      expect(p.title, 'buy milk');
      expect(p.dueAt, isNull);
      expect(p.priority, 1);
      expect(p.recurrence, '');
      expect(p.hasReminder, false);
    });

    test('parses tomorrow + time + priority', () {
      final p = parse('call the doctor tomorrow at 15:00 !high');
      expect(p.title, 'call the doctor');
      expect(
        p.dueAt,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0),
      );
      expect(p.priority, 2);
    });

    test('parses russian tomorrow + time + priority', () {
      final p = parse('позвонить врачу завтра в 15:00 !важно');
      expect(p.title, 'позвонить врачу');
      expect(
        p.dueAt,
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 15, 0),
      );
      expect(p.priority, 2);
    });

    test('parses weekday as next monday', () {
      final p = parse('встреча в понедельник');
      expect(p.title, 'встреча');
      expect(p.dueAt!.weekday, 1);
      expect(p.dueAt!.isAfter(today) || p.dueAt == today, true);
    });

    test('parses weekday in english with week recurrence', () {
      final p = parse('gym every monday');
      expect(p.title, 'gym');
      expect(p.recurrence, 'weekly');
      expect(p.dueAt!.weekday, 1);
    });

    test('parses daily recurrence', () {
      final p = parse('тренировка каждый день в 7:00');
      expect(p.title, 'тренировка');
      expect(p.recurrence, 'daily');
      expect(p.dueAt, DateTime(today.year, today.month, today.day, 7, 0));
    });

    test('parses explicit date', () {
      final p = parse('оплатить счет 20.08.2026');
      expect(p.title, 'оплатить счет');
      expect(p.dueAt, DateTime(2026, 8, 20));
    });

    test('parses "через N дней"', () {
      final p = parse('через 3 дня отправить отчет');
      expect(p.title, 'отправить отчет');
      expect(p.dueAt, today.add(const Duration(days: 3)));
    });

    test('parses after tomorrow', () {
      final p = parse('помыть машину послезавтра');
      expect(p.title, 'помыть машину');
      expect(p.dueAt, today.add(const Duration(days: 2)));
    });

    test('parses reminder keyword', () {
      final p = parse('напомни оплатить интернет завтра');
      expect(p.title, 'оплатить интернет');
      expect(p.hasReminder, true);
      expect(p.dueAt, tomorrow);
    });

    test('parses "в N часов" time', () {
      final p = parse('подготовить презентацию в 9 часов');
      expect(p.title, 'подготовить презентацию');
      expect(p.dueAt, DateTime(today.year, today.month, today.day, 9, 0));
    });
  });

  group('Task.nextOccurrence', () {
    test('advances daily', () {
      final task = Task(
        title: 'x',
        dueAt: DateTime(2026, 8, 14, 7, 0),
        recurrence: 'daily',
        createdAt: DateTime(2026, 8, 14),
      );
      final next = task.nextOccurrence();
      expect(next.dueAt, DateTime(2026, 8, 15, 7, 0));
      expect(next.id, isNull);
    });

    test('advances weekly', () {
      final task = Task(
        title: 'x',
        dueAt: DateTime(2026, 8, 14, 7, 0),
        recurrence: 'weekly',
        createdAt: DateTime(2026, 8, 14),
      );
      expect(task.nextOccurrence().dueAt, DateTime(2026, 8, 21, 7, 0));
    });

    test('keeps reminder offset on recurrence', () {
      final due = DateTime(2026, 8, 14, 7, 0);
      final task = Task(
        title: 'x',
        dueAt: due,
        recurrence: 'daily',
        reminderAt: due.subtract(const Duration(minutes: 5)),
        createdAt: DateTime(2026, 8, 14),
      );
      final next = task.nextOccurrence();
      expect(next.reminderAt, DateTime(2026, 8, 15, 6, 55));
    });
  });
}
