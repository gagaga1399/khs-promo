import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/note.dart';
import 'package:khs/models/task.dart';
import 'package:khs/services/obsidian_service.dart';

void main() {
  group('taskFromLine', () {
    test('parses open task with due date', () {
      final t = ObsidianService.taskFromLine(
        '- [ ] Купить молоко 📅 2026-08-15',
      );
      expect(t, isNotNull);
      expect(t!.title, 'Купить молоко');
      expect(t.completed, isFalse);
      expect(t.dueDate, DateTime(2026, 8, 15));
    });

    test('parses completed task with done date', () {
      final t = ObsidianService.taskFromLine(
        '- [x] Позвонить врачу 📅 2026-08-14 ✅ 2026-08-14',
      );
      expect(t!.title, 'Позвонить врачу');
      expect(t.completed, isTrue);
      expect(t.completedAt, DateTime(2026, 8, 14));
    });

    test('parses reminder time, priority and recurrence', () {
      final t = ObsidianService.taskFromLine(
        '- [ ] Зарядка 📅 2026-08-15 ⏰ 07:30 [priority:: high] 🔁 every day ➕ 2026-08-01',
      );
      expect(t!.title, 'Зарядка');
      expect(t.priority, 2);
      expect(t.recurrence, 'daily');
      expect(t.reminderAt, DateTime(2026, 8, 15, 7, 30));
    });

    test('parses low priority', () {
      final t = ObsidianService.taskFromLine('- [ ] Уборка [priority:: low]');
      expect(t!.priority, 0);
    });

    test('parses category tag and strips it from title', () {
      final t = ObsidianService.taskFromLine(
        '- [ ] Отчёт 📅 2026-08-15 ➕ 2026-08-01 #работа',
      );
      expect(t!.title, 'Отчёт');
      expect(t.category, 'работа');
    });

    test('roundtrips category through section', () {
      final task = Task(
        title: 'Отчёт',
        dueAt: DateTime(2026, 8, 15),
        category: 'работа',
        createdAt: DateTime(2026, 8, 1),
      );
      final section = ObsidianService.buildSection([task]);
      expect(section, contains('#работа'));
      final reparsed = ObsidianService.parseSection(section);
      expect(reparsed.single.title, 'Отчёт');
      expect(reparsed.single.category, 'работа');
    });

    test('returns null for non-task lines', () {
      expect(ObsidianService.taskFromLine('# задачи'), isNull);
      expect(ObsidianService.taskFromLine('## Задачи KHS'), isNull);
      expect(ObsidianService.taskFromLine('обычный текст'), isNull);
    });
  });

  group('parseSection', () {
    const content = '''
# заметка

не задачи

## Задачи KHS

- [ ] Дело 1 📅 2026-08-15
- [x] Дело 2 ✅ 2026-08-14

# следующий раздел

- [ ] Не наше
''';

    test('parses only tasks inside the section', () {
      final tasks = ObsidianService.parseSection(content);
      expect(tasks.length, 2);
      expect(tasks[0].title, 'Дело 1');
      expect(tasks[1].title, 'Дело 2');
    });

    test('заметки-чекбоксы без маркеров KHS не становятся задачами', () {
      const noteContent = '''
## Задачи KHS

- [ ] купить хлеб
- [x] созвониться с мамой

# ниже
''';
      final tasks = ObsidianService.parseSection(noteContent);
      expect(tasks, isEmpty);
    });

    test('задачи KHS без маркера ➕ но с датой 📅 всё равно импортируются', () {
      const content = '''
## Задачи KHS

- [ ] Дело 1 📅 2026-08-15
- [x] Дело 2 ✅ 2026-08-14

# конец
''';
      final tasks = ObsidianService.parseSection(content);
      expect(tasks.length, 2);
    });
  });

  group('buildSection / roundtrip', () {
    test('writes and reparses tasks', () {
      final tasks = [
        Task(
          title: 'Задача',
          dueAt: DateTime(2026, 8, 15),
          reminderAt: DateTime(2026, 8, 15, 9, 0),
          priority: 2,
          recurrence: 'weekly',
          category: 'Meetings',
          createdAt: DateTime(2026, 8, 1),
        ),
        Task(
          title: 'Сделано',
          dueAt: DateTime(2026, 8, 15),
          completed: true,
          completedAt: DateTime(2026, 8, 15),
          createdAt: DateTime(2026, 8, 1),
        ),
      ];
      final section = ObsidianService.buildSection(tasks);
      final reparsed = ObsidianService.parseSection(section);
      expect(reparsed.length, 2);
      expect(reparsed[0].title, 'Задача');
      expect(reparsed[0].dueDate, DateTime(2026, 8, 15));
      expect(reparsed[0].reminderAt, DateTime(2026, 8, 15, 9, 0));
      expect(reparsed[0].priority, 2);
      expect(reparsed[0].recurrence, 'weekly');
      expect(reparsed[1].completed, isTrue);
      expect(reparsed[1].completedAt, DateTime(2026, 8, 15));
    });

    test('empty section placeholder', () {
      final section = ObsidianService.buildSection([]);
      expect(section, contains('_нет задач_'));
    });
  });

  group('vault file roundtrip', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('khs_obsidian_test');
      await Directory('${tempDir.path}/.obsidian').create();
      await File(
        '${tempDir.path}/.obsidian/daily-notes.json',
      ).writeAsString('{"folder": "даты/2026/месяцы/август"}', encoding: utf8);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('writes to configured daily-note folder path', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      final path = await service.writeTasks(date, [
        Task(title: 'Тест', dueAt: date, createdAt: date),
      ]);
      expect(File(path).existsSync(), isTrue);
      expect(path, contains('даты'));
      expect(path, contains('2026'));
      expect(path, contains('август'));
      expect(path, endsWith('2026-08-15.md'));
    });

    test('readTasks round-trips written tasks', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      await service.writeTasks(date, [
        Task(title: 'Помыть посуду', dueAt: date, createdAt: date),
        Task(title: 'Прочитать главу', dueAt: date, createdAt: date),
      ]);
      final read = await service.readTasks(date);
      expect(read.length, 2);
      expect(
        read.map((t) => t.title),
        containsAll(['Помыть посуду', 'Прочитать главу']),
      );
    });

    test('rewrite replaces previous section without duplicating', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      await service.writeTasks(date, [
        Task(title: 'Первая', dueAt: date, createdAt: date),
      ]);
      await service.writeTasks(date, [
        Task(title: 'Первая', dueAt: date, createdAt: date),
        Task(title: 'Вторая', dueAt: date, createdAt: date),
      ]);
      final read = await service.readTasks(date);
      expect(read.length, 2);
    });

    test('new daily note applies configured template and keeps KHS at bottom', () async {
      await Directory('${tempDir.path}/templates').create();
      await File(
        '${tempDir.path}/templates/daily.md',
      ).writeAsString('# Ежедневная заметка\n\nЗаполни меня', encoding: utf8);
      await File('${tempDir.path}/.obsidian/daily-notes.json').writeAsString(
        '{"folder": "даты/2026/месяцы/август", "template": "templates/daily"}',
        encoding: utf8,
      );
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      final path = await service.writeTasks(date, [
        Task(title: 'Дело', dueAt: date, createdAt: date),
      ]);
      final content = await File(path).readAsString(encoding: utf8);
      expect(content, startsWith('# Ежедневная заметка\n\nЗаполни меня'));
      expect(content, contains('## Задачи KHS'));
      expect(
        content.indexOf('Задачи KHS'),
        greaterThan(content.indexOf('Заполни меня')),
      );
      expect(content, contains('- [ ] Дело 📅 2026-08-15 ➕ 2026-08-15'));
    });

    test('without template new daily note has just KHS section', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      final path = await service.writeTasks(date, []);
      final content = await File(path).readAsString(encoding: utf8);
      expect(content.trim(), '## Задачи KHS\n\n_нет задач_');
    });
  });

  group('standalone note', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('khs_standalone_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Note makeNote({String title = 'Идеи на неделю', String content = 'Текст'}) {
      return Note(
        title: title,
        content: content,
        createdAt: DateTime(2026, 8, 15),
        updatedAt: DateTime(2026, 8, 15),
      );
    }

    test('writes a standalone note as a file in the vault', () async {
      final service = ObsidianService(tempDir.path);
      final path = await service.writeStandaloneNote(makeNote());
      expect(path, contains('заметки'));
      expect(path, endsWith('Идеи на неделю.md'));
      final content = await File(path).readAsString(encoding: utf8);
      expect(content, contains('# Идеи на неделю'));
      expect(content, contains('Текст'));
    });

    test('update overwrites the same file, no duplicates', () async {
      final service = ObsidianService(tempDir.path);
      final path = await service.writeStandaloneNote(
        makeNote(content: 'Версия 1'),
      );
      final path2 = await service.writeStandaloneNote(
        makeNote(content: 'Версия 2'),
      );
      expect(path2, path);
      final content = await File(path).readAsString(encoding: utf8);
      expect(content, contains('Версия 2'));
      expect(content, isNot(contains('Версия 1')));
    });

    test('delete removes the file', () async {
      final service = ObsidianService(tempDir.path);
      final path = await service.writeStandaloneNote(makeNote());
      expect(File(path).existsSync(), isTrue);
      await service.deleteStandaloneNote(makeNote());
      expect(File(path).existsSync(), isFalse);
    });

    test('file name strips forbidden characters', () async {
      final service = ObsidianService(tempDir.path);
      final path = await service.writeStandaloneNote(
        makeNote(title: 'A/B:C*D'),
      );
      expect(path, endsWith('A B C D.md'));
    });
  });

  group('daily note block', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('khs_note_test');
      await Directory('${tempDir.path}/.obsidian').create();
      await File(
        '${tempDir.path}/.obsidian/daily-notes.json',
      ).writeAsString('{"folder": "даты/2026/месяцы/август"}', encoding: utf8);
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('writeDailyNote creates file: note above KHS section', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      final path = await service.writeDailyNote(date, body: 'Текст заметки');
      final content = await File(path).readAsString(encoding: utf8);
      expect(content, contains('## Заметка\n\nТекст заметки'));
      expect(content, contains('## Задачи KHS'));
      expect(
        content.indexOf('Задачи KHS'),
        greaterThan(content.indexOf('Текст заметки')),
      );
    });

    test('writeDailyNote replaces only the note block, keeps template', () async {
      await Directory('${tempDir.path}/templates').create();
      await File('${tempDir.path}/templates/daily.md')
          .writeAsString('# Шаблон', encoding: utf8);
      await File('${tempDir.path}/.obsidian/daily-notes.json').writeAsString(
        '{"folder": "даты/2026/месяцы/август", "template": "templates/daily"}',
        encoding: utf8,
      );
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      await service.writeDailyNote(date, body: 'Первая версия');
      final path = await service.writeDailyNote(date, body: 'Вторая версия');
      final content = await File(path).readAsString(encoding: utf8);
      expect(content, contains('# Шаблон'));
      expect(content, contains('## Заметка\n\nВторая версия'));
      expect(content, isNot(contains('Первая версия')));
    });

    test('writeDailyNote with empty body removes the note block', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      await service.writeDailyNote(date, body: 'Было');
      final path = await service.writeDailyNote(date, body: '');
      final content = await File(path).readAsString(encoding: utf8);
      expect(content, isNot(contains('Было')));
      expect(content, isNot(contains('## Заметка')));
      expect(content, contains('## Задачи KHS'));
    });

    test('readDailyNoteBody extracts note text', () async {
      final service = ObsidianService(tempDir.path);
      final date = DateTime(2026, 8, 15);
      await service.writeDailyNote(date, body: 'Текст заметки');
      expect(await service.readDailyNoteBody(date), 'Текст заметки');
    });
  });
}
