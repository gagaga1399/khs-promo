import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/note.dart';
import '../models/task.dart';

class ObsidianSyncResult {
  final int added;
  final int updated;
  final int written;
  final String? error;

  const ObsidianSyncResult({
    this.added = 0,
    this.updated = 0,
    this.written = 0,
    this.error,
  });
}

class ObsidianService {
  final String vaultPath;

  ObsidianService(this.vaultPath);

  static const sectionTitle = '## Задачи KHS';
  static const noteHeading = '## Заметка';

  static const _months = [
    'январь',
    'февраль',
    'март',
    'апрель',
    'май',
    'июнь',
    'июль',
    'август',
    'сентябрь',
    'октябрь',
    'ноябрь',
    'декабрь',
  ];

  bool get isConfigured => vaultPath.trim().isNotEmpty;

  static String dateString(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String _monthFolder(DateTime d) => _months[d.month - 1];

  Future<String?> _folderFromConfig() async {
    final configFile = File(p.join(vaultPath, '.obsidian', 'daily-notes.json'));
    if (!await configFile.exists()) return null;
    try {
      final json = jsonDecode(await configFile.readAsString());
      if (json is Map<String, dynamic> && json['folder'] is String) {
        return json['folder'] as String;
      }
    } catch (_) {}
    return null;
  }

  /// Ошибка (или пустой список), если сегмент папки нельзя использовать:
  /// «..», «.», пустые сегменты и т.п. — чтобы конфиг vault не вытаскивал
  /// записи за пределы хранилища (#7).
  static List<String> _safeSegments(String folder) {
    final segs = folder
        .split(RegExp(r'[/\\]'))
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    if (RegExp(r'^[A-Za-z]:$').hasMatch(segs.firstOrNull ?? '')) {
      return [];
    }
    return segs;
  }

  String _folderNotePath(String folder, DateTime date) {
    final segs = _safeSegments(folder);
    if (segs.isEmpty) return _defaultNotePath(date);
    if (segs.length >= 3 &&
        RegExp(r'^\d{4}$').hasMatch(segs[segs.length - 3])) {
      segs[segs.length - 3] = date.year.toString();
      if (_months.contains(segs[segs.length - 1])) {
        segs[segs.length - 1] = _monthFolder(date);
      } else {
        segs.add(_monthFolder(date));
      }
      return p.joinAll([vaultPath, ...segs, '${dateString(date)}.md']);
    }
    return p.join(vaultPath, p.joinAll(segs), '${dateString(date)}.md');
  }

  String _defaultNotePath(DateTime date) => p.joinAll([
    vaultPath,
    'даты',
    date.year.toString(),
    'месяцы',
    _monthFolder(date),
    '${dateString(date)}.md',
  ]);

  Future<List<String>> _candidatePaths(DateTime date) async {
    final result = <String>[];
    final folder = await _folderFromConfig();
    if (folder != null) result.add(_folderNotePath(folder, date));
    result.add(_defaultNotePath(date));
    result.add(p.join(vaultPath, '${dateString(date)}.md'));
    return result;
  }

  Future<String?> _existingNotePath(DateTime date) async {
    for (final path in await _candidatePaths(date)) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  Future<String> _targetPath(DateTime date) async {
    final existing = await _existingNotePath(date);
    if (existing != null) return existing;
    final folder = await _folderFromConfig();
    return folder != null
        ? _folderNotePath(folder, date)
        : _defaultNotePath(date);
  }

  /// Читает шаблон ежедневной заметки из настроек Obsidian
  /// (`.obsidian/daily-notes.json`, поле `template`). Если шаблона нет —
  /// возвращает `null`.
  Future<String?> readTemplate() async {
    final configFile = File(p.join(vaultPath, '.obsidian', 'daily-notes.json'));
    if (!await configFile.exists()) return null;
    try {
      final json = jsonDecode(await configFile.readAsString());
      if (json is Map<String, dynamic> && json['template'] is String) {
        var rel = (json['template'] as String).trim();
        if (rel.isEmpty) return null;
        if (!rel.endsWith('.md')) rel = '$rel.md';
        final segs = _safeSegments(rel);
        if (segs.isEmpty) return null;
        final file = File(p.join(vaultPath, p.joinAll(segs)));
        if (await file.exists()) {
          return await file.readAsString(encoding: utf8);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Шаблон (если есть) + блок KHS в самом низу — для новой ежедневной заметки.
  Future<String> _newDailyNote(String section) async {
    final template = await readTemplate();
    final head = (template == null || template.trim().isEmpty)
        ? ''
        : '${template.trimRight()}\n\n';
    return '$head$section';
  }

  static Task? taskFromLine(String line) {
    final match = RegExp(r'^\s*- \[([ xX])\]\s+(.*)$').firstMatch(line);
    if (match == null) return null;

    final completed = match.group(1)!.toLowerCase() == 'x';
    var text = match.group(2)!;

    DateTime? dueAt;
    DateTime? completedAt;
    DateTime? reminderAt;
    String recurrence = '';
    int priority = 1;

    final due = RegExp(r'📅 (\d{4}-\d{2}-\d{2})').firstMatch(text);
    if (due != null) {
      dueAt = DateTime.parse(due.group(1)!);
      text = text.replaceFirst(due.group(0)!, '');
    }

    final done = RegExp(r'✅ (\d{4}-\d{2}-\d{2})').firstMatch(text);
    if (done != null) {
      completedAt = DateTime.parse(done.group(1)!);
      text = text.replaceFirst(done.group(0)!, '');
    }

    final remind = RegExp(r'⏰ (\d{1,2}):(\d{2})').firstMatch(text);
    if (remind != null) {
      final base = dueAt ?? DateTime.now();
      reminderAt = DateTime(
        base.year,
        base.month,
        base.day,
        int.parse(remind.group(1)!),
        int.parse(remind.group(2)!),
      );
      text = text.replaceFirst(remind.group(0)!, '');
    }

    final rec = RegExp(r'🔁 every (day|week|month)').firstMatch(text);
    if (rec != null) {
      recurrence = switch (rec.group(1)) {
        'day' => 'daily',
        'week' => 'weekly',
        _ => 'monthly',
      };
      text = text.replaceFirst(rec.group(0)!, '');
    }

    final prio = RegExp(r'\[priority:: (lowest|low|medium|high|highest)\]')
        .firstMatch(text);
    if (prio != null) {
      priority = switch (prio.group(1)) {
        'lowest' || 'low' => 0,
        'high' || 'highest' => 2,
        _ => 1,
      };
      text = text.replaceFirst(prio.group(0)!, '');
    }

    final created = RegExp(r'➕ \d{4}-\d{2}-\d{2}').firstMatch(text);
    if (created != null) text = text.replaceFirst(created.group(0)!, '');

    final tags = RegExp(r'#([\p{L}\p{N}_-]+)', unicode: true).allMatches(text);
    String? category;
    if (tags.isNotEmpty) {
      category = tags.last.group(1)!;
      text = text.replaceAll(RegExp(r'#[\p{L}\p{N}_-]+', unicode: true), '');
    }

    final title = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) return null;

    return Task(
      title: title,
      dueAt: dueAt,
      completed: completed,
      recurrence: recurrence,
      reminderAt: reminderAt,
      priority: priority,
      completedAt: completedAt,
      category: category,
      createdAt: dueAt ?? DateTime.now(),
    );
  }

  static String _taskToLine(Task task) {
    final buffer = StringBuffer();
    buffer.write(task.completed ? '- [x] ' : '- [ ] ');
    buffer.write(task.title.trim());
    if (task.dueAt != null) {
      buffer.write(' 📅 ${dateString(task.dueAt!)}');
    }
    final reminder = task.reminderAt;
    if (reminder != null) {
      final hh = reminder.hour.toString().padLeft(2, '0');
      final mm = reminder.minute.toString().padLeft(2, '0');
      buffer.write(' ⏰ $hh:$mm');
    }
    switch (task.recurrence) {
      case 'daily':
        buffer.write(' 🔁 every day');
        break;
      case 'weekly':
        buffer.write(' 🔁 every week');
        break;
      case 'monthly':
        buffer.write(' 🔁 every month');
        break;
    }
    if (task.priority == 0) buffer.write(' [priority:: low]');
    if (task.priority == 2) buffer.write(' [priority:: high]');
    buffer.write(' ➕ ${dateString(task.createdAt)}');
    final category = task.category;
    if (category != null && category.isNotEmpty) {
      buffer.write(' #${category.replaceAll(RegExp(r'\s+'), '-')}');
    }
    if (task.completed && task.completedAt != null) {
      buffer.write(' ✅ ${dateString(task.completedAt!)}');
    }
    return buffer.toString();
  }

  /// Признак, что чекбокс-строка — настоящая задача KHS, а не заметка.
  ///
  /// Свои задачи KHS всегда пишутся со служебными маркерами (`➕ дата`,
  /// `📅 дата`, `✅ дата`, `⏰ время`, `🔁 ...`, `[priority:: ...]`).
  /// Простые чекбоксы без маркеров — это личные заметки пользователя,
  /// их в задачи превращать нельзя (иначе они портят график статистики).
  static bool _isKhsTaskLine(String line) {
    return RegExp(
      r'(📅 \d{4}-\d{2}-\d{2}|✅ \d{4}-\d{2}-\d{2}|⏰ \d{1,2}:\d{2}'
      r'|🔁 every (day|week|month)|\[priority::|➕ \d{4}-\d{2}-\d{2})',
    ).hasMatch(line);
  }

  static List<Task> parseSection(String content) {
    final lines = content.split('\n');
    final result = <Task>[];
    var inSection = false;
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim() == sectionTitle) {
        inSection = true;
        continue;
      }
      if (inSection) {
        if (line.trim().isEmpty) continue;
        if (RegExp(r'^#{1,6}\s').hasMatch(line.trim()) ||
            line.trim() == '___' ||
            line.trim() == '---') {
          break;
        }
        if (!_isKhsTaskLine(line)) continue;
        final task = taskFromLine(line);
        if (task != null) result.add(task);
      }
    }
    return result;
  }

  static String buildSection(List<Task> tasks) {
    final buffer = StringBuffer(sectionTitle);
    buffer.write('\n\n');
    if (tasks.isEmpty) buffer.write('_нет задач_\n');
    for (final task in tasks) {
      buffer.writeln(_taskToLine(task));
    }
    buffer.write('\n');
    return buffer.toString();
  }

  Future<List<Task>> readTasks(DateTime date) async {
    final path = await _existingNotePath(date);
    if (path == null) return [];
    try {
      final content = await File(path).readAsString(encoding: utf8);
      return parseSection(content);
    } catch (_) {
      return [];
    }
  }

  Future<String> writeTasks(DateTime date, List<Task> tasks) async {
    final section = buildSection(tasks);
    final targetPath = await _targetPath(date);

    final file = File(targetPath);
    await file.parent.create(recursive: true);

    String newContent;
    if (await file.exists()) {
      final allLines = (await file.readAsString(encoding: utf8)).split('\n');
      final userLines = _userCheckboxLines(allLines);
      final out = <String>[];
      var skipping = false;
      var removed = false;
      for (final raw in allLines) {
        final line = raw;
        if (line.trim() == sectionTitle) {
          skipping = true;
          removed = true;
          continue;
        }
        if (skipping) {
          if (line.trim().isEmpty) continue;
          if (RegExp(r'^#{1,6}\s').hasMatch(line.trim()) ||
              line.trim() == '___' ||
              line.trim() == '---') {
            skipping = false;
          } else {
            continue;
          }
        }
        out.add(line);
      }
      var content = out.join('\n');
      if (!content.endsWith('\n')) content += '\n';
      if (content.trimRight().isNotEmpty) content += '\n';
      var tail = '';
      if (userLines.isNotEmpty) tail = '\n${userLines.join('\n')}\n';
      if (removed) {
        newContent = '$content\n$section$tail';
      } else {
        newContent = '$content$section$tail';
      }
    } else {
      newContent = await _newDailyNote(section);
    }

    await file.writeAsString(newContent, encoding: utf8);
    return targetPath;
  }

  /// Записывает заметку дня в ежедневную заметку Obsidian.
  ///
  /// Если файла ещё нет — создаёт его: шаблон (если настроен) сверху,
  /// текст заметки под `## Заметка`, а в самом низу блок `## Задачи KHS`
  /// (если заметка пустая — только шаблон + блок KHS).
  ///
  /// Если файл уже есть — заменяет только блок `## Заметка`, не трогая
  /// шаблон и задачи. При пустой заметке блок удаляется.
  Future<String> writeDailyNote(
    DateTime date, {
    String body = '',
    List<Task> tasks = const [],
  }) async {
    final targetPath = await _targetPath(date);
    final file = File(targetPath);
    await file.parent.create(recursive: true);

    final cleanBody = body.trimRight();
    String newContent;
    if (await file.exists()) {
      final content = await file.readAsString(encoding: utf8);
      newContent = _replaceNoteBlock(content, cleanBody);
    } else {
      final section = buildSection(tasks);
      final template = await readTemplate();
      final buffer = StringBuffer();
      if (template != null && template.trim().isNotEmpty) {
        buffer.writeln(template.trimRight());
        buffer.writeln();
      }
      if (cleanBody.isNotEmpty) {
        buffer.writeln(noteHeading);
        buffer.writeln();
        buffer.writeln(cleanBody);
        buffer.writeln();
      }
      buffer.write(section);
      newContent = buffer.toString();
    }

    await file.writeAsString(newContent, encoding: utf8);
    return targetPath;
  }

  static String _safeNoteName(String title) {
    var name = title.trim();
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    return name.isEmpty ? 'без названия' : name;
  }

  static String _noteMarker(Note note) {
    final key = note.clientKey ?? '';
    return '> Заметка KHS · ${dateString(note.createdAt)} · k[$key]';
  }

  static String? _noteMarkerKey(String content) {
    for (final raw in content.split('\n')) {
      final line = raw.trimLeft();
      if (line.startsWith('> Заметка KHS')) {
        final m = RegExp(r'k\[([0-9a-f]{8,64})\]').firstMatch(line);
        return m?.group(1);
      }
    }
    return null;
  }

  Future<File?> _findStandaloneNoteFile(Note note) async {
    final key = note.clientKey;
    if (key == null || key.isEmpty) return null;
    final dir = Directory(p.join(vaultPath, 'заметки'));
    if (!await dir.exists()) return null;
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final f = e;
      try {
        final content = await f.readAsString(encoding: utf8);
        if (_noteMarkerKey(content) == key) return f;
      } catch (_) {}
    }
    return null;
  }

  Future<String> writeStandaloneNote(Note note) async {
    final folder = p.join(vaultPath, 'заметки');
    await Directory(folder).create(recursive: true);
    final previous = await _findStandaloneNoteFile(note);
    final baseName = _safeNoteName(note.title);
    var file = File(p.join(folder, '$baseName.md'));
    if (previous != null) {
      if (previous.path == file.path) {
        file = previous;
      } else {
        try {
          await previous.delete();
        } catch (_) {}
      }
    } else {
      var suffix = 2;
      while (await file.exists()) {
        file = File(p.join(folder, '$baseName ($suffix).md'));
        suffix++;
      }
    }
    final buffer = StringBuffer();
    buffer.writeln('# ${note.title.trim()}');
    buffer.writeln();
    buffer.writeln(_noteMarker(note));
    buffer.writeln();
    final body = note.content.trimRight();
    if (body.isNotEmpty) {
      buffer.writeln(body);
      buffer.writeln();
    }
    await file.writeAsString(buffer.toString(), encoding: utf8);
    return file.path;
  }

  Future<void> deleteStandaloneNote(Note note) async {
    final byKey = await _findStandaloneNoteFile(note);
    if (byKey != null) {
      try {
        await byKey.delete();
      } catch (_) {}
      return;
    }
    // По имени файл тоже удаляем только если это действительно наша заметка
    // (есть маркер KHS): чужой пользовательский файл с таким же именем
    // трогать нельзя (#7).
    final file = File(
      p.join(vaultPath, 'заметки', '${_safeNoteName(note.title)}.md'),
    );
    if (await file.exists()) {
      try {
        final content = await file.readAsString(encoding: utf8);
        if (_noteMarkerKey(content) != null) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  /// Читает текст блока `## Заметка` из ежедневной заметки (если есть).
  Future<String> readDailyNoteBody(DateTime date) async {
    final path = await _existingNotePath(date);
    if (path == null) return '';
    try {
      final content = await File(path).readAsString(encoding: utf8);
      return extractNoteBlock(content);
    } catch (_) {
      return '';
    }
  }

  static String extractNoteBlock(String content) {
    final lines = content.split('\n');
    final buffer = <String>[];
    var inNote = false;
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.trim() == noteHeading) {
        inNote = true;
        continue;
      }
      if (inNote) {
        if (RegExp(r'^#{1,6}\s').hasMatch(line.trim()) ||
            line.trim() == '___' ||
            line.trim() == '---') {
          break;
        }
        buffer.add(line);
      }
    }
    return buffer.join('\n').trim();
  }

  static String _replaceNoteBlock(String content, String body) {
    final lines = content.split('\n');
    final out = <String>[];
    var skipping = false;
    for (final raw in lines) {
      final line = raw;
      if (line.trim() == noteHeading) {
        skipping = true;
        continue;
      }
      if (skipping) {
        if (RegExp(r'^#{1,6}\s').hasMatch(line.trim()) ||
            line.trim() == '___' ||
            line.trim() == '---') {
          skipping = false;
        } else {
          continue;
        }
      }
      out.add(line);
    }
    var result = out.join('\n');
    if (body.trim().isNotEmpty) {
      final block = '\n\n$noteHeading\n\n${body.trimRight()}\n';
      final idx = result.indexOf(sectionTitle);
      if (idx != -1) {
        result = result.substring(0, idx) + block + result.substring(idx);
      } else {
        result = result.trimRight();
        if (result.isNotEmpty) result += '\n';
        result += block;
      }
    }
    return result;
  }
  static List<String> _userCheckboxLines(List<String> lines) {
    final result = <String>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (RegExp(r'^\s*- \[[ xX]\]\s').hasMatch(line) &&
          !_isKhsTaskLine(line)) {
        result.add(line);
      }
    }
    return result;
  }
}
