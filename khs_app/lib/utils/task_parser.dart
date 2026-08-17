class ParsedTask {
  final String title;
  final DateTime? dueAt;
  final int priority; // 0 low, 1 normal, 2 high
  final String recurrence; // '', 'daily', 'weekly', 'monthly'
  final bool hasReminder;

  const ParsedTask({
    required this.title,
    this.dueAt,
    this.priority = 1,
    this.recurrence = '',
    this.hasReminder = false,
  });
}

class TaskParser {
  static const _weekdaysRu = <String, int>{
    'понедельник': 1,
    'вторник': 2,
    'среда': 3,
    'четверг': 4,
    'пятница': 5,
    'суббота': 6,
    'воскресенье': 7,
    'пн': 1,
    'вт': 2,
    'ср': 3,
    'чт': 4,
    'пт': 5,
    'сб': 6,
    'вс': 7,
  };

  static const _weekdaysEn = <String, int>{
    'monday': 1,
    'tuesday': 2,
    'wednesday': 3,
    'thursday': 4,
    'friday': 5,
    'saturday': 6,
    'sunday': 7,
    'mon': 1,
    'tue': 2,
    'wed': 3,
    'thu': 4,
    'fri': 5,
    'sat': 6,
    'sun': 7,
  };

  ParsedTask parse(String input) {
    final tokens = <_Token>[];
    final re = RegExp(r'\S+');
    for (final m in re.allMatches(input)) {
      tokens.add(_Token(m.group(0)!, m.start, m.end));
    }

    var priority = 1;
    var recurrence = '';
    var hasReminder = false;
    DateTime? date;
    DateTime? time;

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      if (token.removed) continue;
      final word = token.text.toLowerCase();

      // Priority: !высокий, !, keywords
      if (word.startsWith('!') ||
          word == 'важно' ||
          word == 'срочно' ||
          word == 'высокий' ||
          word == 'high' ||
          word == 'urgent' ||
          word == 'important') {
        priority = 2;
        token.removed = true;
        continue;
      }

      // Recurrence
      if (word == 'ежедневно' || word == 'каждодневно' || word == 'daily') {
        recurrence = 'daily';
        token.removed = true;
        continue;
      }
      if (word == 'еженедельно' || word == 'weekly') {
        recurrence = 'weekly';
        token.removed = true;
        continue;
      }
      if (word == 'ежемесячно' || word == 'monthly') {
        recurrence = 'monthly';
        token.removed = true;
        continue;
      }
      if (word == 'каждый' ||
          word == 'каждую' ||
          word == 'каждого' ||
          word == 'every') {
        final next = i + 1 < tokens.length
            ? tokens[i + 1].text.toLowerCase()
            : '';
        if (next == 'день' ||
            next == 'дня' ||
            next == 'days' ||
            next == 'day') {
          recurrence = 'daily';
          token.removed = true;
          tokens[i + 1].removed = true;
          i++;
          continue;
        }
        if (next == 'неделю' ||
            next == 'недели' ||
            next == 'week' ||
            next == 'weeks') {
          recurrence = 'weekly';
          token.removed = true;
          tokens[i + 1].removed = true;
          i++;
          continue;
        }
        if (next == 'месяц' ||
            next == 'месяца' ||
            next == 'month' ||
            next == 'months') {
          recurrence = 'monthly';
          token.removed = true;
          tokens[i + 1].removed = true;
          i++;
          continue;
        }
        // every monday / каждый понедельник
        final wd = _weekdaysEn[next] ?? _weekdaysRu[next];
        if (wd != null) {
          recurrence = 'weekly';
          date = _nextWeekday(wd);
          token.removed = true;
          tokens[i + 1].removed = true;
          i++;
          continue;
        }
      }

      // Weekday
      final wd = _weekdaysRu[word] ?? _weekdaysEn[word];
      if (wd != null) {
        date = _nextWeekday(wd);
        token.removed = true;
        _removePrep(tokens, i);
        continue;
      }

      // Today / tomorrow / after tomorrow
      if (word == 'сегодня' || word == 'today') {
        date = _dayAt(DateTime.now());
        token.removed = true;
        continue;
      }
      if (word == 'завтра' || word == 'tomorrow') {
        date = _dayAt(DateTime.now().add(const Duration(days: 1)));
        token.removed = true;
        continue;
      }
      if (word == 'послезавтра' ||
          (word == 'after' &&
              i + 1 < tokens.length &&
              tokens[i + 1].text.toLowerCase() == 'tomorrow')) {
        date = _dayAt(DateTime.now().add(const Duration(days: 2)));
        token.removed = true;
        if (word == 'after') tokens[i + 1].removed = true;
        continue;
      }

      // "через N дней" / "in N days"
      if (word == 'через' && i + 2 < tokens.length) {
        final n = int.tryParse(tokens[i + 1].text);
        final unit = tokens[i + 2].text.toLowerCase();
        if (n != null && (unit == 'день' || unit == 'дня' || unit == 'дней')) {
          date = _dayAt(DateTime.now().add(Duration(days: n)));
          token.removed = true;
          tokens[i + 1].removed = true;
          tokens[i + 2].removed = true;
          continue;
        }
      }
      if (word == 'in' && i + 2 < tokens.length) {
        final n = int.tryParse(tokens[i + 1].text);
        final unit = tokens[i + 2].text.toLowerCase();
        if (n != null && unit == 'days') {
          date = _dayAt(DateTime.now().add(Duration(days: n)));
          token.removed = true;
          tokens[i + 1].removed = true;
          tokens[i + 2].removed = true;
          continue;
        }
      }

      // Explicit date DD.MM(.YYYY) or DD/MM
      final dateMatch = RegExp(r'^(\d{1,2})[./](\d{1,2})(?:[./](\d{2,4}))?$')
          .firstMatch(word);
      if (dateMatch != null) {
        final d = int.parse(dateMatch.group(1)!);
        final mo = int.parse(dateMatch.group(2)!);
        var y = DateTime.now().year;
        if (dateMatch.group(3) != null) {
          final ys = dateMatch.group(3)!;
          y = ys.length == 2 ? 2000 + int.parse(ys) : int.parse(ys);
        } else if (mo < DateTime.now().month) {
          y += 1;
        }
        try {
          date = DateTime(y, mo, d);
        } catch (_) {}
        token.removed = true;
        continue;
      }

      // Time HH:MM
      final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(word);
      if (timeMatch != null) {
        time = _timeFrom(
          int.parse(timeMatch.group(1)!),
          int.parse(timeMatch.group(2)!),
        );
        token.removed = true;
        _removePrep(tokens, i);
        continue;
      }

      // "в N часов" / "в N ч" / "at N"
      if ((word == 'в' || word == 'at') && i + 2 < tokens.length) {
        final n = int.tryParse(tokens[i + 1].text);
        final unit = tokens[i + 2].text.toLowerCase();
        if (n != null &&
            (unit == 'час' ||
                unit == 'часа' ||
                unit == 'часов' ||
                unit == 'ч' ||
                unit == 'pm' ||
                unit == 'am')) {
          var h = n;
          if (unit == 'pm' && h < 12) h += 12;
          time = _timeFrom(h, 0);
          token.removed = true;
          tokens[i + 1].removed = true;
          tokens[i + 2].removed = true;
          continue;
        }
      }

      // Reminder
      if (word == 'напомни' ||
          word == 'напомнить' ||
          word == 'remind' ||
          word == 'reminder' ||
          (word == 'remind' &&
              i + 1 < tokens.length &&
              tokens[i + 1].text.toLowerCase() == 'me')) {
        hasReminder = true;
        token.removed = true;
        continue;
      }
    }

    final titleParts = <String>[];
    for (final t in tokens) {
      if (!t.removed) titleParts.add(t.text);
    }
    final title = titleParts.join(' ');

    DateTime? dueAt;
    if (date != null) {
      dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 0,
        time?.minute ?? 0,
      );
    } else if (time != null) {
      final now = DateTime.now();
      dueAt = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    }

    return ParsedTask(
      title: title.isEmpty ? input.trim() : title,
      dueAt: dueAt,
      priority: priority,
      recurrence: recurrence,
      hasReminder: hasReminder,
    );
  }

  DateTime _dayAt(DateTime d) => DateTime(d.year, d.month, d.day);

  void _removePrep(List<_Token> tokens, int i) {
    if (i > 0) {
      final prev = tokens[i - 1];
      if (!prev.removed) {
        final w = prev.text.toLowerCase();
        if (w == 'в' || w == 'на' || w == 'во' || w == 'at' || w == 'on') {
          prev.removed = true;
        }
      }
    }
  }

  DateTime _timeFrom(int h, int m) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, h % 24, m);
  }

  DateTime _nextWeekday(int target) {
    final now = DateTime.now();
    final today = _dayAt(now);
    if (today.weekday == target) return today;
    final diff = (target - today.weekday + 7) % 7;
    return today.add(Duration(days: diff));
  }
}

class _Token {
  final String text;
  final int start;
  final int end;
  bool removed = false;

  _Token(this.text, this.start, this.end);
}
