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
  var prevSpace = true; // исходную строку не обрезаем, но ведущие пробелы схлопываем
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