import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/models/tracker_entry.dart';
import 'package:khs/services/obsidian_service.dart';
import 'package:khs/services/tracker_service.dart';

void main() {
  group('parseScalar', () {
    test('bools', () {
      expect(TrackerService.parseScalar('true'), true);
      expect(TrackerService.parseScalar('да'), true);
      expect(TrackerService.parseScalar('false'), false);
      expect(TrackerService.parseScalar('нет'), false);
    });

    test('numbers c integer', () {
      expect(TrackerService.parseScalar('7'), 7);
      expect(TrackerService.parseScalar('8.5'), 8.5);
      expect(TrackerService.parseScalar('3,5'), 3.5);
      expect(TrackerService.parseScalar('-2'), -2);
    });

    test('strings and quotes', () {
      expect(TrackerService.parseScalar(''), isNull);
      expect(TrackerService.parseScalar('  '), isNull);
      expect(TrackerService.parseScalar('hello'), 'hello');
      expect(TrackerService.parseScalar('"quoted"'), 'quoted');
      expect(TrackerService.parseScalar("'single'"), 'single');
    });

    test('lists', () {
      expect(TrackerService.parseScalar('[a, b, c]'), ['a', 'b', 'c']);
      expect(TrackerService.parseScalar('[]'), <Object?>[]);
      expect(TrackerService.parseScalar('[1, 2]'), [1, 2]);
    });
  });

  group('parseFrontmatter', () {
    test('no frontmatter', () {
      final parsed = TrackerService.parseFrontmatter('Просто тело.');
      expect(parsed.properties, isEmpty);
      expect(parsed.body, 'Просто тело.');
    });

    test('reads keys and values', () {
      final content = '''
---
date: 2026-10-11
чтение: true
продуктивность: 7
самоощущение: 8,5
тег: "важное"
список: [a, b]
---
Тело заметки.
''';
      final parsed = TrackerService.parseFrontmatter(content);
      expect(parsed.properties['чтение'], true);
      expect(parsed.properties['продуктивность'], 7);
      expect(parsed.properties['самоощущение'], 8.5);
      expect(parsed.properties['тег'], 'важное');
      expect(parsed.properties['список'], ['a', 'b']);
      expect(parsed.body, 'Тело заметки.\n');
    });

    test('body without frontmatter is untouched', () {
      final parsed = TrackerService.parseFrontmatter('one: two\\n---\\n');
      expect(parsed.properties, isEmpty);
      expect(parsed.body, 'one: two\\n---\\n');
    });

    test('keeps colons inside property names', () {
      final parsed = TrackerService.parseFrontmatter(
        '---\nсон с 22:30: true\ndate: 2026-10-05\n---\nтело',
      );
      expect(parsed.properties['сон с 22:30'], true);
      expect(parsed.properties['date'], '2026-10-05');
      expect(parsed.body, 'тело');
    });
  });

  group('parseInlineProperties', () {
    test('dataview style', () {
      final found = TrackerService.parseInlineProperties(
        'Сходил [прогулка:: 40 мин] и [настроение:: ок].',
      );
      expect(found['прогулка'], '40 мин');
      expect(found['настроение'], 'ок');
    });
  });

  group('parseNote', () {
    test('date from frontmatter wins over file name', () {
      final entry = TrackerService.parseNote(
        path: 'C:/vault/даты/2026/месяцы/октябрь/2026-10-05.md',
        content: '---\ndate: 2026-10-11\nчтение: true\n---\nзапись',
      );
      expect(entry, isNotNull);
      expect(entry!.date, DateTime(2026, 10, 11));
      expect(entry.properties['чтение'], true);
      expect(entry.properties.containsKey('date'), isFalse);
    });

    test('date from file name when absent in frontmatter', () {
      final entry = TrackerService.parseNote(
        path: 'C:/vault/даты/2026/месяцы/октябрь/2026-10-11.md',
        content: '---\nтренировка: true\n---\n',
      );
      expect(entry, isNotNull);
      expect(entry!.date, DateTime(2026, 10, 11));
      expect(entry.title, '2026-10-11');
    });

    test('null when no date anywhere', () {
      final entry = TrackerService.parseNote(
        path: 'C:/vault/заметки/мысли.md',
        content: '---\nтег: x\n---\n',
      );
      expect(entry, isNull);
    });

    test('inline properties merge into note', () {
      final entry = TrackerService.parseNote(
        path: 'C:/vault/даты/2026/месяцы/октябрь/2026-10-11.md',
        content: '---\nзарядка: true\n---\nПробежка [прогулка:: 40 мин]\n',
      );
      expect(entry, isNotNull);
      expect(entry!.properties['зарядка'], true);
      expect(entry.properties['прогулка'], '40 мин');
    });
  });

  group('dateFromFileName', () {
    test('parses YYYY-MM-DD', () {
      expect(
        TrackerService.dateFromFileName('2026-10-11.md'),
        DateTime(2026, 10, 11),
      );
      // Дату ищем в строке, а не только в имени: свойство date тоже бывает
      // строкой с любым префиксом.
      expect(
        TrackerService.dateFromFileName('даты/2026-05-03.md'),
        DateTime(2026, 5, 3),
      );
      expect(TrackerService.dateFromFileName('notes.md'), isNull);
    });
  });

  group('kindOf', () {
    test('classifies values', () {
      expect(TrackerService.kindOf(true), TrackerPropertyKind.boolean);
      expect(TrackerService.kindOf(false), TrackerPropertyKind.boolean);
      expect(TrackerService.kindOf(7), TrackerPropertyKind.number);
      expect(TrackerService.kindOf(8.5), TrackerPropertyKind.number);
      expect(TrackerService.kindOf(['a']), TrackerPropertyKind.list);
      expect(
        TrackerService.kindOf('2026-10-11'),
        TrackerPropertyKind.date,
      );
      expect(TrackerService.kindOf('просто текст'), TrackerPropertyKind.text);
    });
  });

  group('summarizeProperties', () {
    TrackerEntry entry({
      required String path,
      required Map<String, Object?> props,
    }) => TrackerEntry(
      date: TrackerService.dateFromFileName(path)!,
      title: path.split('/').last,
      path: path,
      properties: props,
    );

    test('aggregates fills, kinds and samples', () {
      final entries = [
        entry(path: '2026-10-10.md', props: {
          'чтение': true,
          'продуктивность': 6,
        }),
        entry(path: '2026-10-11.md', props: {
          'чтение': false,
          'продуктивность': 7,
        }),
        entry(path: '2026-10-12.md', props: {'чтение': true}),
      ];
      final props = TrackerService.summarizeProperties(entries);
      expect(props.length, 2);

      final reading = props.firstWhere((p) => p.name == 'чтение');
      expect(reading.kind, TrackerPropertyKind.boolean);
      expect(reading.filled, 3);
      expect(reading.total, 3);
      expect(reading.ratio, 1.0);

      final product = props.firstWhere((p) => p.name == 'продуктивность');
      expect(product.kind, TrackerPropertyKind.number);
      expect(product.filled, 2);
      expect(product.ratio, closeTo(2 / 3, 1e-9));
    });

    test('bool/number properties come first', () {
      final entries = [
        entry(path: '2026-10-10.md', props: {'заметка': 'текст', 'та': true}),
      ];
      final props = TrackerService.summarizeProperties(entries);
      expect(props.first.name, 'та');
    });

    test('empty values do not count as filled', () {
      final entries = [
        entry(path: '2026-10-10.md', props: {'чтение': ''}),
        entry(path: '2026-10-11.md', props: {'чтение': true}),
      ];
      final props = TrackerService.summarizeProperties(entries);
      expect(props.first.filled, 1);
    });
  });

  group('dailyNoteRoots', () {
    test('derives stable root from month-specific config', () async {
      final tempDir = await Directory.systemTemp.createTemp('khs_tracker_root');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      await Directory('${tempDir.path}/.obsidian').create();
      await File('${tempDir.path}/.obsidian/daily-notes.json').writeAsString(
        '{"folder":"даты/2026/месяцы/октябрь"}',
      );
      await Directory('${tempDir.path}/даты/2026/месяцы/октябрь').create(
        recursive: true,
      );

      final roots = await ObsidianService(tempDir.path).dailyNoteRoots();
      expect(roots, ['${tempDir.path}${Platform.pathSeparator}даты']);
    });
  });

  group('seriesFor', () {
    Future<TrackerService> vault(Map<String, String> notes) async {
      final tempDir = await Directory.systemTemp.createTemp('khs_tracker_sv');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final month = Directory('${tempDir.path}/даты/2026/месяцы/октябрь');
      await month.create(recursive: true);
      for (final e in notes.entries) {
        await File('${month.path}/${e.key}.md').writeAsString(e.value);
      }
      final service = TrackerService(vaultPathProvider: () => tempDir.path);
      await service.refresh();
      return service;
    }

    test('sorts ascending and skips empty values', () async {
      final service = await vault({
        '2026-10-12': '---\nпродуктивность: 7\n---\n',
        '2026-10-10': '---\nпродуктивность: 5\n---\n',
        '2026-10-11': '---\nпродуктивность: ""\n---\n',
      });
      final series = service.seriesFor('продуктивность');
      expect(series.map((s) => s.$1.day), [10, 12]);
      expect(series.map((s) => s.$2), [5, 7]);
    });

    test('unknown property yields empty series', () async {
      final service = await vault({'2026-10-10': '---\nчтение: true\n---\n'});
      expect(service.seriesFor('тренировка'), isEmpty);
    });
  });

  group('habitStreak', () {
    List<(DateTime, Object?)> series(Map<int, Object?> byDay) {
      final list = [
        for (final e in byDay.entries) (DateTime(2026, 10, e.key), e.value),
      ];
      list.sort((a, b) => a.$1.compareTo(b.$1));
      return list;
    }

    test('counts consecutive true days to the last date', () {
      expect(
        TrackerService.habitStreak(series({10: true, 11: true, 12: true})),
        3,
      );
    });

    test('gaps without a note do not break the run', () {
      expect(TrackerService.habitStreak(series({10: true, 12: true})), 2);
    });

    test('explicit false on the last day resets to zero', () {
      expect(
        TrackerService.habitStreak(series({10: true, 11: true, 12: false})),
        0,
      );
    });

    test('empty series is zero', () {
      expect(TrackerService.habitStreak(const []), 0);
    });
  });

  group('bestStreak', () {
    List<(DateTime, Object?)> series(List<(int, Object?)> days) {
      final list = [
        for (final d in days) (DateTime(2026, 10, d.$1), d.$2),
      ];
      list.sort((a, b) => a.$1.compareTo(b.$1));
      return list;
    }

    test('finds longest run across history', () {
      final s = series([
        (10, true),
        (11, true),
        (12, false),
        (13, true),
        (14, true),
        (15, true),
      ]);
      expect(TrackerService.bestStreak(s), 3);
    });

    test('empty series is zero', () {
      expect(TrackerService.bestStreak(const []), 0);
    });
  });

  group('isDone', () {
    test('accepts common truthy habit values', () {
      expect(TrackerService.isDone(true), true);
      expect(TrackerService.isDone(1), true);
      expect(TrackerService.isDone('true'), true);
      expect(TrackerService.isDone('да'), true);
      expect(TrackerService.isDone('✅'), true);
    });

    test('rejects falsey and missing values', () {
      expect(TrackerService.isDone(false), false);
      expect(TrackerService.isDone(0), false);
      expect(TrackerService.isDone('нет'), false);
      expect(TrackerService.isDone(null), false);
      expect(TrackerService.isDone(''), false);
    });
  });

  group('wordsIn', () {
    test('counts words ignoring extra whitespace', () {
      expect(TrackerService.wordsIn('привет мир'), 2);
      expect(TrackerService.wordsIn('  a   b\n c '), 3);
      expect(TrackerService.wordsIn(''), 0);
      expect(TrackerService.wordsIn('   '), 0);
    });
  });

  group('completedTasksIn', () {
    test('counts checked boxes only', () {
      const body = '- [ ] не сделано\n- [x] сделано\n- [X] тоже\n* [x] звёздочный\n';
      expect(TrackerService.completedTasksIn(body), 3);
    });

    test('no tasks is zero', () {
      expect(TrackerService.completedTasksIn('просто текст'), 0);
    });
  });

  group('parseNote body', () {
    test('stores the note body without frontmatter', () {
      final entry = TrackerService.parseNote(
        path: 'даты/2026-10-12.md',
        content: '---\nчтение: true\n---\n\n# Заголовок\n- [x] задача\n',
      );
      expect(entry, isNotNull);
      expect(entry!.body.contains('# Заголовок'), true);
      expect(entry.body.contains('- [x] задача'), true);
      expect(entry.body.contains('чтение'), false);
    });
  });

  group('encodeScalar', () {
    test('keeps types', () {
      expect(TrackerService.encodeScalar(true), 'true');
      expect(TrackerService.encodeScalar(false), 'false');
      expect(TrackerService.encodeScalar(5), '5');
      expect(TrackerService.encodeScalar(2.5), '2.5');
      expect(TrackerService.encodeScalar(null), '');
    });

    test('quotes strings that would change type', () {
      expect(TrackerService.encodeScalar('просто'), 'просто');
      expect(TrackerService.encodeScalar('true'), '"true"');
      expect(TrackerService.encodeScalar('да'), '"да"');
      expect(TrackerService.encodeScalar('12'), '"12"');
      expect(TrackerService.encodeScalar('a: b'), '"a: b"');
      expect(TrackerService.encodeScalar('с пробелом '), '"с пробелом "');
    });

    test('lists', () {
      expect(TrackerService.encodeScalar([1, 'два']), '[1, два]');
    });
  });

  group('buildFrontmatter', () {
    test('empty when no properties', () {
      expect(TrackerService.buildFrontmatter(const {}), '');
      expect(TrackerService.buildFrontmatter({'': 1}), '');
    });

    test('round-trips through parseFrontmatter', () {
      final fm = TrackerService.buildFrontmatter({
        'чтение': true,
        'самоощущение': 4,
        'сон с 22:30': true,
        'теги': ['a', 'b'],
        'заметка': 'привет мир',
      });
      final parsed = TrackerService.parseFrontmatter('$fm' 'тело');
      expect(parsed.properties['чтение'], true);
      expect(parsed.properties['самоощущение'], 4);
      expect(parsed.properties['сон с 22:30'], true);
      expect(parsed.properties['теги'], ['a', 'b']);
      expect(parsed.properties['заметка'], 'привет мир');
      expect(parsed.body, 'тело');
    });

    test('keeps body untouched when there is no frontmatter', () {
      const text = 'без шапки\nстрока';
      final parsed = TrackerService.parseFrontmatter(text);
      expect(TrackerService.buildFrontmatter(parsed.properties), '');
      expect(parsed.body, text);
    });
  });

  group('noteWritten', () {
    TrackerEntry entry({
      Map<String, Object?> props = const {},
      String body = '',
    }) => TrackerEntry(
      date: DateTime(2026, 10, 16),
      title: '2026-10-16',
      path: 'даты/2026-10-16.md',
      body: body,
      properties: props,
    );

    test('пустая авто-заметка из шаблона не считается написанной', () {
      final e = entry(
        props: {
          'date': '2026-10-16',
          'продуктивность': null,
          'самоощущение': null,
          'чтение': false,
          'зарядка': false,
        },
        body: '# задачи\n\n[[Ежедневная заметка (чистая)]]\n\n## Задачи KHS\n_нет задач_\n',
      );
      expect(TrackerService.noteWritten(e), false);
    });

    test('числовое свойство — заметка написана', () {
      expect(
        TrackerService.noteWritten(entry(props: {'самоощущение': 100})),
        true,
      );
    });

    test('выполненная привычка — заметка написана', () {
      expect(TrackerService.noteWritten(entry(props: {'чтение': true})), true);
    });

    test('непустая строка списка — заметка написана', () {
      expect(
        TrackerService.noteWritten(entry(props: {'теги': ['a']})),
        true,
      );
      expect(
        TrackerService.noteWritten(entry(props: {'заметка': 'привет'})),
        true,
      );
    });

    test('пустая строка не считается', () {
      expect(TrackerService.noteWritten(entry(props: {'заметка': '   '})), false);
    });

    test('блок «## Заметка» — заметка написана', () {
      expect(
        TrackerService.noteWritten(
          entry(body: '## Заметка\nСегодня продуктивный день.\n'),
        ),
        true,
      );
    });

    test('задача в теле — заметка написана', () {
      expect(
        TrackerService.noteWritten(entry(body: '## Задачи KHS\n- [x] сделать\n')),
        true,
      );
    });

    test('только пустой блок «## Заметка» — не считается', () {
      expect(
        TrackerService.noteWritten(entry(body: '## Заметка\n\n\n')),
        false,
      );
    });
  });
}
