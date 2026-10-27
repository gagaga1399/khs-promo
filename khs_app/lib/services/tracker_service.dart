import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/tracker_entry.dart';
import 'obsidian_service.dart';

/// Разобранная заметка: свойства из frontmatter плюс тело без шапки.
class ParsedNote {
  final Map<String, Object?> properties;
  final String body;

  const ParsedNote(this.properties, this.body);
}

/// Движок трекеров: обходит папку ежедневных заметок Obsidian, читает
/// заметки с датой и разбирает их свойства (frontmatter и inline
/// `[ключ:: значение]`).
///
/// Сами трекеры здесь намеренно не описаны — сервис лишь собирает данные:
/// список датированных заметок и сводку свойств, по которым их можно строить.
class TrackerService extends ChangeNotifier {
  TrackerService({required this.vaultPathProvider});

  /// Путь к хранилищу Obsidian берётся лениво из AppState: пользователь может
  /// сменить его в настройках, не перезапуская приложение.
  final String Function() vaultPathProvider;

  bool _scanning = false;
  String? _error;
  List<TrackerEntry> _entries = const [];
  List<TrackerProperty> _properties = const [];
  List<String> _roots = const [];
  DateTime? _updatedAt;

  bool get scanning => _scanning;
  String? get error => _error;
  List<TrackerEntry> get entries => _entries;
  List<TrackerProperty> get properties => _properties;

  /// Папки, которые обошёл последний скан (для диагностики).
  List<String> get roots => _roots;
  DateTime? get updatedAt => _updatedAt;

  String get vaultPath => vaultPathProvider().trim();
  bool get configured => vaultPath.isNotEmpty;

  /// Перечитывает хранилище. Безопасно вызывать повторно и когда путь не задан.
  Future<void> refresh() async {
    final vault = vaultPath;
    if (vault.isEmpty) {
      _entries = const [];
      _properties = const [];
      _roots = const [];
      _error = null;
      _updatedAt = DateTime.now();
      notifyListeners();
      return;
    }

    _scanning = true;
    _error = null;
    notifyListeners();
    try {
      final obsidian = ObsidianService(vault);
      final roots = await obsidian.dailyNoteRoots();
      _roots = roots;
      final entries = await _scan(roots);
      _entries = entries;
      _properties = summarizeProperties(entries);
    } catch (e) {
      _error = '$e';
      _entries = const [];
      _properties = const [];
    } finally {
      _scanning = false;
      _updatedAt = DateTime.now();
      notifyListeners();
    }
  }

  Future<List<TrackerEntry>> _scan(List<String> roots) async {
    final seen = <String>{};
    final entries = <TrackerEntry>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (!await dir.exists()) continue;
      try {
        await for (final entity in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          if (!entity.path.toLowerCase().endsWith('.md')) continue;
          if (!seen.add(entity.path)) continue;
          try {
            final content = await entity.readAsString(encoding: utf8);
            final entry = parseNote(path: entity.path, content: content);
            if (entry != null) entries.add(entry);
          } catch (_) {}
        }
      } catch (_) {}
    }
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  /// Значения свойства по датам (только записи с непустым значением),
  /// отсортированы по дате возрастания.
  List<(DateTime, Object?)> seriesFor(String propertyName) {
    final series = <(DateTime, Object?)>[];
    for (final e in _entries) {
      final v = e.properties[propertyName];
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      series.add((e.date, v));
    }
    series.sort((a, b) => a.$1.compareTo(b.$1));
    return series;
  }

  /// Подряд идущие дни со значением `true`, заканчивающиеся сегодня
  /// (или последним днём с данными).
  static int habitStreak(List<(DateTime, Object?)> series) {
    final values = <DateTime, Object?>{for (final s in series) s.$1: s.$2};
    if (values.isEmpty) return 0;
    final dates = values.keys.toList()..sort();
    final last = dates.last;
    // Серия идёт от последнего дня с данными назад; «дыры» (пустые дни
    // без заметки) серию не рвут, а вот явное false — рвут.
    var streak = 0;
    var cursor = last;
    for (;;) {
      final v = values[cursor];
      if (v == true) {
        streak++;
      } else if (v == false) {
        break;
      }
      cursor = cursor.subtract(const Duration(days: 1));
      final hasOlder = values[cursor] != null || dates.first.isBefore(cursor);
      if (!hasOlder) break;
    }
    return streak;
  }

  /// Лучшая серия за всё время наблюдений.
  static int bestStreak(List<(DateTime, Object?)> series) {
    var best = 0;
    var run = 0;
    final values = <DateTime, Object?>{for (final s in series) s.$1: s.$2};
    if (values.isEmpty) return 0;
    final dates = values.keys.toList()..sort();
    var cursor = dates.first;
    final last = dates.last;
    while (!cursor.isAfter(last)) {
      final v = values[cursor];
      if (v == true) {
        run++;
        if (run > best) best = run;
      } else {
        run = 0;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return best;
  }

  // ── Разбор ───────────────────────────────────────────────────────────

  /// Служебные ключи, которые не показываем как свойства-трекеры.
  static const _ignoredKeys = {'date', 'cssclasses', 'cssclassescssclasses'};

  /// Разбирает заметку. Возвращает `null`, если у неё нет даты — ни в
  /// frontmatter, ни в имени файла.
  static TrackerEntry? parseNote({
    required String path,
    required String content,
  }) {
    final parsed = parseFrontmatter(content);
    final props = <String, Object?>{};
    for (final e in parsed.properties.entries) {
      if (_ignoredKeys.contains(e.key.toLowerCase())) continue;
      props[e.key] = e.value;
    }
    for (final e in parseInlineProperties(parsed.body).entries) {
      if (_ignoredKeys.contains(e.key.toLowerCase())) continue;
      props.putIfAbsent(e.key, () => e.value);
    }

    final date =
        dateFromValue(parsed.properties['date']) ??
        dateFromFileName(p.basename(path));
    if (date == null) return null;

    return TrackerEntry(
      date: date,
      title: p.basenameWithoutExtension(path),
      path: path,
      properties: props,
      body: parsed.body,
    );
  }

  /// Читает YAML-frontmatter в начале заметки. Если её нет — свойств пусто,
  /// а тело равно исходному тексту.
  static ParsedNote parseFrontmatter(String content) {
    var text = content;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = text.split('\n');
    if (lines.isEmpty || lines.first.trim() != '---') {
      return ParsedNote(const {}, text);
    }
    var end = -1;
    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim() == '---') {
        end = i;
        break;
      }
    }
    if (end == -1) return ParsedNote(const {}, text);

    final props = <String, Object?>{};
    final separator = RegExp(r'^(.+?):(?:\s+(.*))?$');
    for (var i = 1; i < end; i++) {
      final match = separator.firstMatch(lines[i]);
      if (match == null) continue;
      var key = match.group(1)!.trim();
      if (key.length >= 2 &&
          ((key.startsWith('"') && key.endsWith('"')) ||
              (key.startsWith("'") && key.endsWith("'")))) {
        key = key.substring(1, key.length - 1);
      }
      if (key.isEmpty) continue;
      props[key] = parseScalar(match.group(2) ?? '');
    }
    final body = lines.sublist(end + 1).join('\n');
    return ParsedNote(props, body);
  }

  /// Inline-свойства Dataview: `[ключ:: значение]` в теле заметки.
  static Map<String, Object?> parseInlineProperties(String body) {
    final out = <String, Object?>{};
    final re = RegExp(r'\[([^\[\]:]+)::\s*([^\[\]]*?)\]');
    for (final m in re.allMatches(body)) {
      final key = m.group(1)!.trim();
      if (key.isEmpty) continue;
      out[key] = parseScalar(m.group(2)!);
    }
    return out;
  }

  /// Разбирает скалярное значение свойства: bool, число, список или строка.
  static Object? parseScalar(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return null;
    if (v.startsWith('"') && v.endsWith('"') && v.length >= 2) {
      return v.substring(1, v.length - 1);
    }
    if (v.startsWith("'") && v.endsWith("'") && v.length >= 2) {
      return v.substring(1, v.length - 1);
    }
    if (v.startsWith('[') && v.endsWith(']')) {
      final inner = v.substring(1, v.length - 1).trim();
      if (inner.isEmpty) return const <Object?>[];
      return inner.split(',').map((s) => parseScalar(s)).toList();
    }
    final low = v.toLowerCase();
    if (low == 'true' || low == 'да') return true;
    if (low == 'false' || low == 'нет') return false;
    final n = _tryNum(v);
    if (n != null) return n;
    return v;
  }

  static num? _tryNum(String v) {
    final direct = num.tryParse(v);
    if (direct != null) return direct;
    if (RegExp(r'^-?\d+[.,]\d+$').hasMatch(v)) {
      return num.tryParse(v.replaceAll(',', '.'));
    }
    return null;
  }

  /// Тип значения свойства.
  static TrackerPropertyKind kindOf(Object? value) {
    if (value is bool) return TrackerPropertyKind.boolean;
    if (value is num) return TrackerPropertyKind.number;
    if (value is List) return TrackerPropertyKind.list;
    if (value is String) {
      if (RegExp(
        r'^\d{4}-\d{1,2}-\d{1,2}([ T]\d|$)',
      ).hasMatch(value.trim())) {
        return TrackerPropertyKind.date;
      }
      return TrackerPropertyKind.text;
    }
    return TrackerPropertyKind.text;
  }

  static DateTime? dateFromValue(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return DateTime(value.year, value.month, value.day);
    return dateFromFileName('$value');
  }

  /// Дата `YYYY-MM-DD` из имени файла (или строки свойства).
  static DateTime? dateFromFileName(String fileName) {
    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(fileName);
    if (m == null) return null;
    final year = int.tryParse(m.group(1)!);
    final month = int.tryParse(m.group(2)!);
    final day = int.tryParse(m.group(3)!);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  /// Значение свойства в виде строки для предпросмотра.
  static String displayValue(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? '✓' : '✗';
    if (value is List) return value.map(displayValue).join(', ');
    return '$value';
  }

  /// YAML-представление значения свойства — для записи frontmatter обратно.
  static String encodeScalar(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    if (value is List) {
      return '[${value.map(encodeScalar).join(', ')}]';
    }
    final text = '$value';
    if (text.isEmpty) return '';
    if (_needsQuoting(text)) {
      return '"${text.replaceAll('"', r'\"')}"';
    }
    return text;
  }

  /// Нужно ли брать строку в кавычки, чтобы YAML прочитал её как текст.
  static bool _needsQuoting(String text) {
    if (text != text.trim()) return true;
    if (RegExp(r'^[-?:,\[\]{}#&*!|>%@`]').hasMatch(text)) return true;
    if (text.contains(': ') || text.contains(' #')) return true;
    final low = text.toLowerCase();
    if (const {
      'true',
      'false',
      'yes',
      'no',
      'on',
      'off',
      'null',
      '~',
      'да',
      'нет',
    }.contains(low)) {
      return true;
    }
    return num.tryParse(text) != null;
  }

  /// Собирает YAML-шапку заметки из свойств. Пустая строка, если свойств нет.
  static String buildFrontmatter(Map<String, Object?> properties) {
    final entries = properties.entries
        .where((e) => e.key.trim().isNotEmpty)
        .toList();
    if (entries.isEmpty) return '';
    final buffer = StringBuffer('---\n');
    for (final entry in entries) {
      buffer.write('${_encodeKey(entry.key.trim())}: ${encodeScalar(entry.value)}\n');
    }
    buffer.write('---\n');
    return buffer.toString();
  }

  /// YAML-имя свойства: двоеточие-разделитель допустимо внутри имени, но
  /// имя с пробелом после двоеточия берём в кавычки.
  static String _encodeKey(String key) {
    if (key.contains(': ') || key.endsWith(':')) {
      return '"${key.replaceAll('"', r'\"')}"';
    }
    return key;
  }

  /// Считает значение привычки выполненным: `true`, `1`, «да», «true», «✅».
  static bool isDone(Object? value) {
    if (value == true) return true;
    if (value is num) return value == 1;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == '1' || v == 'да' || v == 'yes' || v == '✅';
    }
    return false;
  }

  /// Считается ли заметка «написанной» — для «Серии заметок». Пустые
  /// авто-заметки из шаблона (все свойства пусты/false, только шаблонный
  /// текст и блок задач KHS) не считаются. Написанной считаем, если есть
  /// содержательное значение свойства, пользовательский блок «## Заметка»
  /// или хотя бы одна задача в теле.
  static bool noteWritten(TrackerEntry entry) {
    for (final e in entry.properties.entries) {
      if (_ignoredKeys.contains(e.key.toLowerCase())) continue;
      final v = e.value;
      if (v == null) continue;
      if (v is bool) {
        if (v) return true;
        continue;
      }
      if (v is num) return true;
      if (v is String) {
        if (v.trim().isNotEmpty) return true;
        continue;
      }
      if (v is List) {
        if (v.isNotEmpty) return true;
        continue;
      }
    }
    if (ObsidianService.extractNoteBlock(entry.body).trim().isNotEmpty) {
      return true;
    }
    final taskLine = RegExp(r'^\s*[-*]\s*\[[ xX]\]');
    for (final line in entry.body.split('\n')) {
      if (taskLine.hasMatch(line)) return true;
    }
    return false;
  }

  /// Количество слов в теле заметки.
  static int wordsIn(String body) {
    if (body.trim().isEmpty) return 0;
    return body.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  /// Количество выполненных чекбоксов (`- [x]`) в теле заметки.
  static int completedTasksIn(String body) {
    var count = 0;
    for (final line in body.split('\n')) {
      if (RegExp(r'^\s*[-*]\s*\[[xX]\]').hasMatch(line)) count++;
    }
    return count;
  }

  /// Сводка свойств: какие встречаются, как часто и какого типа.
  /// Кандидаты в трекеры (да/нет и числа) идут первыми.
  static List<TrackerProperty> summarizeProperties(
    List<TrackerEntry> entries,
  ) {
    final names = <String>{};
    for (final e in entries) {
      names.addAll(e.properties.keys);
    }
    final result = <TrackerProperty>[];
    for (final name in names) {
      var filled = 0;
      final kindCounts = <TrackerPropertyKind, int>{};
      final samples = <String>[];
      for (final e in entries) {
        final value = e.properties[name];
        if (value == null) continue;
        if (value is String && value.trim().isEmpty) continue;
        filled++;
        final kind = kindOf(value);
        kindCounts[kind] = (kindCounts[kind] ?? 0) + 1;
        final sample = displayValue(value);
        if (sample.isNotEmpty &&
            samples.length < 6 &&
            !samples.contains(sample)) {
          samples.add(sample);
        }
      }
      if (filled == 0) continue;

      var kind = TrackerPropertyKind.text;
      var best = -1;
      kindCounts.forEach((k, c) {
        if (c > best) {
          best = c;
          kind = k;
        }
      });
      result.add(
        TrackerProperty(
          name: name,
          kind: kind,
          filled: filled,
          total: entries.length,
          samples: samples,
        ),
      );
    }
    result.sort((a, b) {
      final aTracker =
          a.kind == TrackerPropertyKind.boolean ||
          a.kind == TrackerPropertyKind.number;
      final bTracker =
          b.kind == TrackerPropertyKind.boolean ||
          b.kind == TrackerPropertyKind.number;
      if (aTracker != bTracker) return aTracker ? -1 : 1;
      if (a.filled != b.filled) return b.filled - a.filled;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }
}
