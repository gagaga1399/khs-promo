import 'dart:convert';
import 'dart:io';

import 'text_document.dart';

/// Лёгкий извлекатель текстового слоя PDF.
///
/// Разбирает объектную модель PDF, страницы, ресурсы шрифтов и карты
/// ToUnicode (CMap) и собирает текст из операторов Tj / TJ.
/// Возвращает null, если текстовый слой не извлечён (например, скан).
class PdfTextExtractor {
  static final Map<String, TextDocument?> _cache = {};

  static Future<TextDocument?> tryExtract(
      String path, {bool useCache = true}) async {
    if (useCache && _cache.containsKey(path)) return _cache[path];
    try {
      final doc = await _extract(path);
      _cache[path] = doc;
      return doc;
    } catch (_) {
      _cache[path] = null;
      return null;
    }
  }

  static void invalidate(String path) => _cache.remove(path);
}

Future<TextDocument?> _extract(String path) async {
  final bytes = await File(path).readAsBytes();
  final file = _PdfFile(bytes);
  if (!file.parse()) return null;

  final pages = file.collectPages();
  if (pages.isEmpty) return null;

  final chapters = <TextChapter>[];
  for (final page in pages) {
    final texts = file.extractPageText(page);
    var pageText = texts.join('\n').trim();
    pageText = pageText.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    pageText = pageText.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    if (pageText.isEmpty) continue;
    chapters.add(TextChapter(title: 'Стр. ${page.number}', text: pageText));
  }

  // Отсекаем «мусор»: PDF-сканы/водяные знаки дают повторяющиеся короткие
  // строки (www.…, «-», цифры страниц) вместо связного текста. Если такие
  // шумовые строки составляют почти весь объём — текст не извлечён.
  final cleaned = chapters.map((ch) {
    final lines = ch.text.split('\n');
    final kept = <String>[];
    for (final line in lines) {
      final t = line.trim();
      if (t.length <= 3 && RegExp(r'^[\-\.\s0-9]+$').hasMatch(t)) continue;
      if (_isNoiseLine(t)) continue;
      kept.add(t);
    }
    return (title: ch.title, text: kept.join('\n'));
  });

  var realChars = 0;
  var realChapters = 0;
  for (final e in cleaned) {
    realChars += e.text.length;
    if (e.text.trim().isNotEmpty) realChapters++;
  }

  // Сломанный ToUnicode/кодировка шрифта: PDF визуально читается, а текст
  // извлекается кашей — «т005010 006n010» вместо слов. Для таких PDF
  // текстовый режим бесполезен, читаем как страницы.
  if (cleaned.isNotEmpty && _isGarbled(cleaned)) return null;

  // Скан или почти без текста — вернуть null, чтобы ридер показал страницы.
  // Нормальные PDF дают сотни символов на страницу; сканы — единицы.
  if (realChapters == 0 || realChars < 400) return null;
  if (realChapters == 1 && realChars < 1200) return null;
  if (chapters.isNotEmpty && (realChars / chapters.length) < 50) return null;

  final out = <TextChapter>[];
  for (final e in cleaned) {
    if (e.text.trim().isNotEmpty) {
      out.add(TextChapter(title: e.title, text: e.text));
    }
  }
  return TextDocument(chapters: out);
}

// Повторяющийся между страницами шум (водяные знаки, URL, сноски).
bool _isNoiseLine(String line) =>
    line.startsWith('www') || line.startsWith('http');

/// Признаки того, что извлечённый текст — мусор из-за сломанной карты
/// кодировок: либо управляющие символы, либо «слова» с цифрой и буквой
/// внутри (код-в-код вместо Unicode).
bool _isGarbled(Iterable<({String title, String text})> cleaned) {
  var totalTokens = 0;
  var mixedTokens = 0;
  var controls = 0;
  var totalChars = 0;
  final hasDigit = RegExp(r'[0-9]');
  final hasLetter = RegExp(r'[A-Za-zА-Яа-яёЁ]');
  for (final e in cleaned) {
    final text = e.text;
    totalChars += text.length;
    for (final tok in text.split(RegExp(r'\s+'))) {
      if (tok.isEmpty) continue;
      totalTokens++;
      if (hasDigit.hasMatch(tok) && hasLetter.hasMatch(tok)) mixedTokens++;
    }
    for (final code in text.codeUnits) {
      if (code < 0x20 && code != 0x09 && code != 0x0A && code != 0x0D) {
        controls++;
      }
    }
  }
  if (totalChars == 0) return false;
  final controlRatio = controls / totalChars;
  if (controlRatio > 0.005) return true;
  if (totalTokens == 0) return false;
  final mixedRatio = mixedTokens / totalTokens;
  return mixedRatio > 0.35;
}

class _PdfPageRef {
  final int number;
  final List<int> contentObjects;
  final Map<String, int> fonts; // имя шрифта (/F39) → объект шрифта
  _PdfPageRef(this.number, this.contentObjects, this.fonts);
}

class _PdfObject {
  final Map<String, String> dict;
  final List<int>? rawStream;
  _PdfObject(this.dict, this.rawStream);
}

class _PdfFile {
  final List<int> _bytes;
  final Map<int, _PdfObject> _objects = {};
  bool _parsed = false;
  _PdfFile(this._bytes);

  static final RegExp _objRe = RegExp(r'(\d+)\s+0\s+obj\b');
  static final RegExp _dictEntryRe = RegExp(
      r'/([A-Za-z_][\w]*)\s*((?:\d+\s+\d+\s+R)|\[[^\]]*\]|<<[^>]*>>|/[A-Za-z_][\w]*|<[0-9A-Fa-f]*>|\((?:[^()\\]|\\.)*\)|true|false|-?[\d.]+)');
  static final RegExp _refRe = RegExp(r'^(\d+)\s+\d+\s+R$');
  static final RegExp _arrayItemRe = RegExp(
      r'(?:\d+\s+\d+\s+R)|<[0-9A-Fa-f\s]+>|\((?:[^()\\]|\\.)*\)|(/[A-Za-z_][\w]*)|(-?[\d.]+)');

  bool parse() {
    if (_parsed) return true;
    final ascii = latin1.decode(_bytes, allowInvalid: true);
    for (final m in _objRe.allMatches(ascii)) {
      final num = int.tryParse(m.group(1)!);
      if (num == null || _objects.containsKey(num)) continue;
      final endObj = ascii.indexOf('endobj', m.start);
      if (endObj < 0) continue;
      final blockLen = endObj - m.start;
      final blockStr = ascii.substring(m.start, m.start + blockLen);
      final si = blockStr.indexOf('stream');
      final dictPart = si >= 0 ? blockStr.substring(0, si) : blockStr;
      final dict = <String, String>{};
      _parseDict(dictPart, dict);
      List<int>? raw;
      if (si >= 0) {
        final streamAbs = m.start + si;
        var p = streamAbs + 'stream'.codeUnits.length;
        while (p < _bytes.length &&
            (_bytes[p] == 0x0D || _bytes[p] == 0x0A)) {
          p++;
        }
        var e = _findBytes(p, 'endstream'.codeUnits);
        if (e < 0) e = _bytes.length;
        var end = e;
        while (end > p && _bytes[end - 1] <= 0x20) {
          end--;
        }
        if (end > p) raw = _bytes.sublist(p, end);
      }
      _objects[num] = _PdfObject(dict, raw);
    }
    _parsed = _objects.isNotEmpty;
    return _parsed;
  }

  void _parseDict(String s, Map<String, String> out) {
    for (final m in _dictEntryRe.allMatches(s)) {
      out[m.group(1)!] = m.group(2)!.trim();
    }
  }

  _PdfObject? _obj(int num) => _objects[num];

  int? _refNum(dynamic value) {
    if (value is String) {
      final m = _refRe.firstMatch(value);
      if (m != null) return int.parse(m.group(1)!);
    } else if (value is int) {
      return value;
    }
    return null;
  }

  /// Резолвит значение в объект со словарём (если это indirect ref).
  _PdfObject? _dictOf(dynamic value) {
    final n = _refNum(value);
    return n != null ? _obj(n) : null;
  }

  List<dynamic> _splitArray(String s) {
    final inner = s.substring(1, s.length - 1);
    final items = <dynamic>[];
    for (final m in _arrayItemRe.allMatches(inner)) {
      final v = m.group(0)!;
      if (_refRe.hasMatch(v)) {
        items.add(v);
      } else if (v.startsWith('<')) {
        items.add(v);
      } else if (v.startsWith('(')) {
        items.add(v);
      } else if (v.startsWith('/')) {
        items.add(v);
      } else {
        items.add(double.tryParse(v) ?? int.tryParse(v));
      }
    }
    return items;
  }

  List<int> _contentObjectNumbers(dynamic contents) {
    final result = <int>[];
    if (contents == null) return result;
    if (contents is String && contents.startsWith('[')) {
      for (final item in _splitArray(contents)) {
        final n = _refNum(item);
        if (n != null) result.add(n);
      }
    } else {
      final n = _refNum(contents);
      if (n != null) result.add(n);
    }
    return result;
  }

  /// Собирает страницы в порядке следования (по дереву /Pages).
  List<_PdfPageRef> collectPages() {
    final pages = <_PdfPageRef>[];
    _PdfObject? catalog;
    for (final o in _objects.values) {
      if (o.dict['Type'] == '/Catalog') {
        catalog = o;
        break;
      }
    }
    if (catalog == null) return pages;
    final rootRef = _refNum(catalog.dict['Pages']);
    if (rootRef == null) return pages;
    var no = 0;
    void walk(dynamic kidsValue) {
      if (kidsValue is! String || !kidsValue.startsWith('[')) return;
      for (final item in _splitArray(kidsValue)) {
        final n = _refNum(item);
        if (n == null) continue;
        final o = _obj(n);
        if (o == null) continue;
        final type = o.dict['Type'];
        if (type == '/Pages' && o.dict.containsKey('Kids')) {
          walk(o.dict['Kids']);
        } else if (type == '/Page' ||
            (type == null && o.dict.containsKey('Contents'))) {
          no++;
          pages.add(_buildPage(n, o, no));
        }
      }
    }
    walk(_obj(rootRef)?.dict['Kids']);
    return pages;
  }

  _PdfPageRef _buildPage(int objNum, _PdfObject page, int no) {
    final contents = _contentObjectNumbers(page.dict['Contents']);
    final fonts = <String, int>{};
    final res = _dictOf(page.dict['Resources']);
    if (res != null) {
      var fontEntry = res.dict['Font'];
      if (fontEntry != null) {
        final fontObj = _dictOf(fontEntry);
        if (fontObj != null) fontEntry = fontObj.dict['Font'];
        if (fontEntry != null) _collectFontMap(fontEntry, fonts);
      }
    }
    return _PdfPageRef(no, contents, fonts);
  }

  void _collectFontMap(String fontsValue, Map<String, int> fonts) {
    final re = RegExp(r'/([A-Za-z_][\w]*)\s+(\d+)\s+\d+\s+R');
    for (final m in re.allMatches(fontsValue)) {
      final name = m.group(1)!;
      final fontObj = int.parse(m.group(2)!);
      if (_obj(fontObj) != null) fonts[name] = fontObj;
    }
  }

  /// Извлекает текст страницы из её content-потоков.
  List<String> extractPageText(_PdfPageRef page) {
    final lines = <String>[];
    for (final contentObj in page.contentObjects) {
      final o = _obj(contentObj);
      if (o?.rawStream == null) continue;
      List<int> data;
      try {
        data = ZLibCodec().decode(o!.rawStream!);
      } catch (_) {
        data = o!.rawStream!;
      }
      final s = utf8.decode(data, allowMalformed: true);
      final t = _parseContent(s, page.fonts);
      if (t.trim().isNotEmpty) lines.add(t);
    }
    return lines;
  }

  String _parseContent(String s, Map<String, int> fonts) {
    final linesBuf = <String>[];
    final pending = StringBuffer();
    var currentFont = -1;

    final re = RegExp(
        r'\[[^\]]*\]|<[0-9A-Fa-f\s]+>|\((?:\\.|[^()\\])*\)|/[A-Za-z_][\w]*|-?[\d.]+|\S+');
    final toks = <String>[];
    for (final m in re.allMatches(s)) {
      toks.add(m.group(0)!);
    }

    var i = 0;
    while (i < toks.length) {
      final tok = toks[i];
      if (tok == 'Tf' && i >= 2 && toks[i - 2].startsWith('/')) {
        final name = toks[i - 2].substring(1);
        currentFont = fonts[name] ?? currentFont;
      } else if (tok == 'ET' || tok == 'Td' || tok == 'TD' || tok == 'T*' ||
          tok == 'Tm') {
        _flush(pending, linesBuf);
      } else if (tok == 'Tj') {
        final op = i > 0 ? toks[i - 1] : '';
        if (op.startsWith('<') || op.startsWith('(')) {
          pending.write(_decodeOperand(op, currentFont));
        }
      } else if (tok == 'TJ') {
        final op = i > 0 ? toks[i - 1] : '';
        if (op.startsWith('[')) {
          final items = _splitArray(op);
          for (final item in items) {
            if (item is String && item.startsWith('<')) {
              final dec = _decodeOperand(item, currentFont);
              pending.write(dec);
            } else if (item is String && item.startsWith('(')) {
              pending.write(_decodeOperand(item, currentFont));
            } else if (item is num && item > 200) {
              pending.write(' ');
            }
          }
        }
      }
      i++;
    }
    _flush(pending, linesBuf);
    return linesBuf.join('\n');
  }

  void _flush(StringBuffer pending, List<String> linesBuf) {
    final s = pending.toString().trim();
    if (s.isNotEmpty) linesBuf.add(s);
    pending.clear();
  }

  String _decodeOperand(String operand, int fontObj) {
    if (operand.startsWith('<')) {
      final hex = operand
          .substring(1, operand.length - 1)
          .replaceAll(RegExp(r'\s+'), '');
      if (hex.isEmpty) return '';
      if (fontObj < 0) return '';
      final map = _toUnicodeMap(fontObj);
      final out = StringBuffer();
      // Identity/fonts с 2-байтными глифами: разбор по 4 hex
      if (hex.length % 4 == 0 && _isTwoByte(map, hex)) {
        for (var k = 0; k + 3 < hex.length; k += 4) {
          final code = int.parse(hex.substring(k, k + 4), radix: 16);
          out.write(map.containsKey(code) ? map[code]! : _utf16be(code));
        }
      } else if (hex.length % 2 == 0) {
        // однобайтовые шрифты (StandartEncoding / WinAnsi)
        for (var k = 0; k + 1 < hex.length; k += 2) {
          final byte = int.parse(hex.substring(k, k + 2), radix: 16);
          out.write(map.containsKey(byte) ? map[byte]! : String.fromCharCode(byte));
        }
      } else {
        return '';
      }
      return out.toString();
    }
    if (operand.startsWith('(')) {
      final inner = operand.substring(1, operand.length - 1);
      return _unescapeLiteral(inner);
    }
    return '';
  }

  bool _isTwoByte(Map<int, String> map, String hex) {
    if (map.isEmpty) {
      final last = int.parse(
          hex.substring(hex.length - 4, hex.length),
          radix: 16);
      return last > 255;
    }
    return true;
  }

  String _utf16be(int code) {
    return String.fromCharCodes([code >> 8, code & 0xFF]);
  }

  String _unescapeLiteral(String s) {
    final b = StringBuffer();
    var i = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == '\\' && i + 1 < s.length) {
        b.write(s[i + 1]);
        i += 2;
      } else {
        b.write(c);
        i++;
      }
    }
    return b.toString();
  }

  final Map<int, Map<int, String>> _tuCache = {};

  Map<int, String> _toUnicodeMap(int fontObj) {
    final cached = _tuCache[fontObj];
    if (cached != null) return cached;
    final map = <int, String>{};
    final o = _obj(fontObj);
    if (o == null) {
      _tuCache[fontObj] = map;
      return map;
    }
    final tu = o.dict['ToUnicode'];
    final tuRef = _refNum(tu);
    if (tuRef == null) {
      _tuCache[fontObj] = map;
      return map;
    }
    final tuObj = _obj(tuRef);
    if (tuObj?.rawStream == null) {
      _tuCache[fontObj] = map;
      return map;
    }
    List<int> raw;
    try {
      raw = ZLibCodec().decode(tuObj!.rawStream!);
    } catch (_) {
      raw = tuObj!.rawStream!;
    }
    final cmap = utf8.decode(raw, allowMalformed: true);

    // Разбираем CMap по секциям: bfchar и bfrange отдельно,
    // чтобы регулярные выражения не пересекали границы записей.
    final bfcharBlocks =
        RegExp(r'beginbfchar\b([\s\S]*?)endbfchar').allMatches(cmap);
    for (final block in bfcharBlocks) {
      final body = block.group(1)!;
      for (final bm in RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(body)) {
        final code = int.parse(bm.group(1)!, radix: 16);
        map[code] = _utf16hex(bm.group(2)!);
      }
    }
    final bfrangeBlocks =
        RegExp(r'beginbfrange\b([\s\S]*?)endbfrange').allMatches(cmap);
    for (final block in bfrangeBlocks) {
      final body = block.group(1)!;
      for (final br in RegExp(
              r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')
          .allMatches(body)) {
        final lo = int.parse(br.group(1)!, radix: 16);
        final hi = int.parse(br.group(2)!, radix: 16);
        final dst = int.parse(br.group(3)!, radix: 16);
        for (var c = lo; c <= hi; c++) {
          map[c] = _utf16hex(
              (dst + (c - lo)).toRadixString(16).padLeft(4, '0'));
        }
      }
    }
    _tuCache[fontObj] = map;
    return map;
  }

  String _utf16hex(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    if (clean.length <= 4) {
      return String.fromCharCode(int.parse(clean, radix: 16));
    }
    // UTF-16BE surrogate pair
    final bytes = <int>[];
    for (var i = 0; i + 3 < clean.length; i += 4) {
      bytes.add(int.parse(clean.substring(i, i + 4), radix: 16));
    }
    if (bytes.length >= 2) {
      final hi = bytes[0];
      final lo = bytes[1];
      final cp = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00);
      return String.fromCharCode(cp);
    }
    return String.fromCharCode(bytes.isNotEmpty ? bytes[0] : 0);
  }

  int _findBytes(int start, List<int> tok) {
    for (var i = start; i + tok.length <= _bytes.length; i++) {
      var ok = true;
      for (var k = 0; k < tok.length; k++) {
        if (_bytes[i + k] != tok[k]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }
}