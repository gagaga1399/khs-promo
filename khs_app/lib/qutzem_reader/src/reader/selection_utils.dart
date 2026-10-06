/// Поиск фрагмента в тексте главы с нормализацией пробелов и переносов строк.
///
/// Выделение из SelectionArea/SelectableText может содержать переводы строк
/// между фрагментами (по одному `\n` на границу блока) и сжатые пробелы,
/// которых нет в исходном тексте. Здесь обе строки схлопываются до «одного
/// пробела» и/или «переноса», поэтому слово, фраза и даже выделение в
/// несколько абзацев находятся надёжно.
///
/// Возвращает пару [startRaw, endRaw) — индексы в исходном [haystack],
/// либо null, если фрагмент не найден.
List<int>? findFragment(String haystack, String needle) {
  final n = _collapseWhitespace(needle);
  if (n.isEmpty) return null;

  final hNorm = <int>[];
  final hBuf = StringBuffer();
  var prevSpace =
      true; // исходную строку не обрезаем, но ведущие пробелы схлопываем
  for (var i = 0; i < haystack.length; i++) {
    final c = haystack.codeUnitAt(i);
    final isWs = _isWhitespace(c);
    if (isWs) {
      if (!prevSpace) {
        hBuf.write(' ');
        hNorm.add(i);
      }
      prevSpace = true;
      continue;
    }
    hBuf.write(haystack[i]);
    hNorm.add(i);
    prevSpace = false;
  }

  final h = hBuf.toString();
  final idx = h.indexOf(n);
  if (idx < 0) return null;
  final startRaw = hNorm[idx];
  final endRaw = hNorm[idx + n.length - 1] + 1;
  return [startRaw, endRaw];
}

/// Схлопнуть пробелы/переносы в [s] в один пробел и убрать по краям.
String _collapseWhitespace(String s) {
  final buf = StringBuffer();
  var prevSpace = true;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (_isWhitespace(c)) {
      if (!prevSpace) buf.write(' ');
      prevSpace = true;
      continue;
    }
    buf.write(s[i]);
    prevSpace = false;
  }
  return buf.toString();
}

bool _isWhitespace(int c) =>
    c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C;

/// Абзац, по которому можно восстановить офсеты выделения.
typedef SelectionBlock = ({int chapter, int start, int end, String text});

/// Текст без пробелов/переносов + индексы символов в исходной строке.
({String sk, List<int> map}) _skel(String s) {
  final b = StringBuffer();
  final m = <int>[];
  for (var i = 0; i < s.length; i++) {
    if (_isWhitespace(s.codeUnitAt(i))) continue;
    b.write(s[i]);
    m.add(i);
  }
  return (sk: b.toString(), map: m);
}

/// Разложить выделение SelectionArea на точные диапазоны исходного текста.
///
/// Flutter склеивает текст выбранных абзацев БЕЗ разделителя
/// (`SelectableRegion.getSelectedContent` просто пишет `plainText` каждого
/// абзаца подряд), поэтому в выделении видно «…гвоздями заколачивают…В общем…»,
/// хотя в книге это два абзаца. Такую строку не находит ни один поиск по
/// отдельному абзацу, и выделение «через абзацы» вообще не находилось.
///
/// Здесь границы восстанавливаются напрямую: абзацы страницы копятся подряд,
/// пока их склейка не станет префиксом выделения, после чего хвост выделения
/// уточняется точным поиском внутри последнего абзаца. Пробелы и переносы
/// при сравнении игнорируются, поэтому лишние пробелы выделения не важны.
///
/// Возвращает список (глава, start, end) — по одному на каждый затронутый
/// абзац, в порядке следования; старые заметки без `parts` чинятся тем же.
List<(int, int, int)> locateSelectionParts({
  required String selection,
  required List<SelectionBlock> blocks,
  int from = 0,
  int? to,
}) {
  final needle = selection.trim();
  final end = (to ?? blocks.length).clamp(0, blocks.length);
  if (needle.isEmpty || from >= end) return const [];
  final n = _skel(needle).sk;

  // Обычный случай: выделение целиком внутри одного абзаца.
  for (var i = from; i < end; i++) {
    final f = findFragment(blocks[i].text, needle);
    if (f != null) {
      return [
        (blocks[i].chapter, blocks[i].start + f[0], blocks[i].start + f[1]),
      ];
    }
  }

  // Выделение через несколько абзацев: ищем абзац, с которого начинается
  // выделение, и копим абзацы подряд. Якорь укорачиваем, пока он не
  // поместится внутри одного абзаца (начало выделения может быть короче
  // якоря, если выделен хвост абзаца).
  for (final len in const [32, 24, 16, 12, 8, 6, 4]) {
    if (len > needle.length) continue;
    final anchor = needle.substring(0, len);
    for (var i = from; i < end; i++) {
      // Одну и ту же фразу абзац может содержать несколько раз — проверяем
      // каждое вхождение, а не только первое.
      for (final at in findFragments(blocks[i].text, anchor)) {
        final ranges = _collect(blocks, i, at[0], needle, n, end);
        if (ranges != null && ranges.isNotEmpty) return ranges;
      }
    }
  }
  return const [];
}

/// Накопить абзацы, начиная с позиции [startIn] блока [first], пока не
/// покроется всё выделение. null — это место выделения не подошло.
///
/// [needle] — сырой текст выделения, [n] — он же без пробелов: сравниваем
/// по [n], а искать хвост нужно по сырому [needle].
List<(int, int, int)>? _collect(
  List<SelectionBlock> blocks,
  int first,
  int startIn,
  String needle,
  String n,
  int end,
) {
  final picked = <int>[];
  var joined = '';
  var j = first;
  while (j < end) {
    final acc = _skel(joined).sk;
    if (picked.isNotEmpty && !n.startsWith(acc)) return null; // не тот абзац
    if (acc.length >= n.length && picked.isNotEmpty) {
      // Выделение закончилось ровно на конце предыдущего абзаца.
      return _emitRanges(
        blocks,
        picked,
        startIn,
        blocks[picked.last].text.length,
      );
    }
    // Хвост выделения — внутри текущего абзаца.
    final rest = needle.substring(_skel(needle).map[acc.length]);
    final tail = findFragment(blocks[j].text, rest);
    if (tail != null) {
      return _emitRanges(blocks, [...picked, j], startIn, tail[1]);
    }
    picked.add(j);
    joined += blocks[j].text.substring(j == first ? startIn : 0);
    j++;
  }
  return picked.isNotEmpty
      ? _emitRanges(blocks, picked, startIn, blocks[picked.last].text.length)
      : null;
}

/// Все вхождения [needle] в [haystack] как пары индексов [start, end).
List<List<int>> findFragments(String haystack, String needle) {
  final out = <List<int>>[];
  if (needle.trim().isEmpty) return out;
  var from = 0;
  while (from < haystack.length) {
    final f = findFragment(haystack.substring(from), needle);
    if (f == null) break;
    out.add([f[0] + from, f[1] + from]);
    from = f[1] + from;
  }
  return out;
}

/// Собрать итоговые диапазоны по накопленным абзацам.
List<(int, int, int)> _emitRanges(
  List<SelectionBlock> blocks,
  List<int> picked,
  int firstStart,
  int lastEnd,
) {
  final out = <(int, int, int)>[];
  for (var k = 0; k < picked.length; k++) {
    final b = blocks[picked[k]];
    final isFirst = k == 0;
    final isLast = k == picked.length - 1;
    final s = isFirst ? firstStart : 0;
    final e = isLast ? lastEnd : b.text.length;
    if (e > s) out.add((b.chapter, b.start + s, b.start + e));
  }
  return out;
}
