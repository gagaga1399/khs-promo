import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class Config {
  static const double maxBookSizeMB = 2.0;

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} МБ';
  }
}

/// Переносит библиотеку из папки прежней отдельной читалки в папку хаба.
///
/// Копирует `books`, `covers`, `data` и переписывает индекс, попутно
/// переставляя префикс в абсолютном `coverPath`. Существующие файлы не
/// перезаписываются: перенос ничего не теряет даже если запустить его
/// повторно. Возвращает `true`, если индекс был перезаписан.
///
/// Ошибки внутри проглатываются — перенос не должен ломать запуск
/// приложения, а исходная папка остаётся нетронутой в любом случае.
bool migrateLegacyLibrary(String fromRoot, String toRoot, File toIndex) {
  final legacyIndex = File(p.join(fromRoot, 'index.json'));
  if (!legacyIndex.existsSync()) return false;
  if (!Directory(p.join(fromRoot, 'books')).existsSync()) return false;

  try {
    for (final dir in ['books', 'covers', 'data']) {
      final from = Directory(p.join(fromRoot, dir));
      if (!from.existsSync()) continue;
      final to = Directory(p.join(toRoot, dir));
      if (!to.existsSync()) to.createSync(recursive: true);
      for (final f in from.listSync()) {
        if (f is! File) continue;
        final dest = File(p.join(to.path, p.basename(f.path)));
        if (dest.existsSync()) continue;
        f.copySync(dest.path);
      }
    }

    // coverPath в индексе абсолютный и указывает на старую папку, поэтому
    // префикс пути переписываем на новый. Иначе книги откроются, а
    // обложки пропадут.
    // Разделитель добавляем вручную: p.join(path, '') его отбрасывает, и
    // отрезанный остаток пути начинался бы с разделителя, из-за чего
    // p.join вернул бы путь от корня диска вместо папки назначения.
    final legacyPrefix = fromRoot.endsWith(p.separator)
        ? fromRoot
        : '$fromRoot${p.separator}';
    final decoded = jsonDecode(legacyIndex.readAsStringSync());
    final list = decoded is List ? decoded : const <dynamic>[];
    final out = <Map<String, dynamic>>[];
    for (final entry in list) {
      if (entry is! Map<String, dynamic>) continue;
      final e = Map<String, dynamic>.from(entry);
      final cover = e['coverPath'];
      if (cover is String && cover.startsWith(legacyPrefix)) {
        e['coverPath'] = p.join(toRoot, cover.substring(legacyPrefix.length));
      }
      out.add(e);
    }
    toIndex.writeAsStringSync(jsonEncode(out));
    return true;
  } catch (_) {
    return false;
  }
}

class Library {
  Library._();
  static final Library instance = Library._();

  Directory? _root;
  late Directory booksDir;
  late Directory coversDir;

  List<Book> books = [];
  final Map<String, BookData> _data = {};
  bool loaded = false;

  /// Увеличивается при каждом сохранении данных книги. Слушатели (например,
  /// вкладка «Заметки») перестраиваются и показывают свежий список.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<Directory> get root async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    _root = Directory(p.join(base.path, 'library'));
    booksDir = Directory(p.join(_root!.path, 'books'));
    coversDir = Directory(p.join(_root!.path, 'covers'));
    return _root!;
  }

  Future<void> init() async {
    await root;
    if (!booksDir.existsSync()) booksDir.createSync(recursive: true);
    if (!coversDir.existsSync()) coversDir.createSync(recursive: true);
    _ensureDataDir();
    final index = File(p.join(_root!.path, 'index.json'));
    if (!index.existsSync()) {
      // Папка пустая — значит, это первый запуск встроенной читалки. Если
      // библиотека прежней отдельной читалки ещё лежит рядом, переносим её,
      // иначе у пользователя книги исчезают после переезда в хаб.
      await _importLegacyLibrary(index);
    }
    if (index.existsSync()) {
      books = _readIndex(index);
    }
    _data.clear();
    for (final book in books) {
      _data[book.id] = _loadBookData(book);
    }
    loaded = true;
  }

  BookData? dataOf(String id) => _data[id];

  /// Читает индекс, пропуская битые записи.
  ///
  /// Раньше здесь стоял `catch (_) { books = []; }`: одна нечитаемая запись
  /// скрывала всю библиотеку, а следующий же `save()` затирал индекс пустым
  /// списком — книги пропадали навсегда.
  List<Book> _readIndex(File index) {
    try {
      final decoded = jsonDecode(index.readAsStringSync());
      if (decoded is! List) return <Book>[];
      final result = <Book>[];
      for (final entry in decoded) {
        if (entry is! Map<String, dynamic>) continue;
        try {
          result.add(Book.fromJson(entry));
        } catch (_) {
          continue;
        }
      }
      return result;
    } catch (_) {
      return <Book>[];
    }
  }

  /// Одноразовый перенос библиотеки из прежней отдельной читалки.
  ///
  /// `getApplicationSupportDirectory()` на Windows/Android выводится из
  /// CompanyName/ProductName и applicationId, поэтому у хаба и у прежней
  /// отдельной «QutZem Reader» это разные папки. Переноса при встраивании
  /// читалки в хаб не было — из-за чего библиотека выглядела пустой.
  /// Запускается только когда в новой папке нет index.json, то есть ровно
  /// один раз.
  Future<void> _importLegacyLibrary(File index) async {
    if (Platform.isAndroid) return; // чужой приватный каталог недоступен
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;
    final legacyRoot = Directory(
      p.join(appData, 'QutZem', 'QutZem Reader', 'library'),
    );
    migrateLegacyLibrary(legacyRoot.path, _root!.path, index);
  }

  /// Все заметки всех книг, отсортированные по дате (новые сверху).
  List<({Book book, Highlight highlight})> allNotes() {
    final result = <({Book book, Highlight highlight})>[];
    for (final b in books) {
      final d = _data[b.id];
      if (d == null) continue;
      for (final h in d.highlights) {
        result.add((book: b, highlight: h));
      }
    }
    result.sort(
      (a, b) => b.highlight.createdAt.compareTo(a.highlight.createdAt),
    );
    return result;
  }

  /// Все закладки всех книг, отсортированные по дате (новые сверху).
  List<({Book book, Bookmark bookmark})> allBookmarks() {
    final result = <({Book book, Bookmark bookmark})>[];
    for (final b in books) {
      final d = _data[b.id];
      if (d == null) continue;
      for (final bm in d.bookmarks) {
        result.add((book: b, bookmark: bm));
      }
    }
    result.sort((a, b) => b.bookmark.createdAt.compareTo(a.bookmark.createdAt));
    return result;
  }

  String bookFilePath(Book book) =>
      p.join(booksDir.path, '${book.id}.${book.format.extension}');

  File _bookDataFile(String id) =>
      File(p.join(_root!.path, 'data', '$id.json'));

  BookData _loadBookData(Book book) {
    final f = _bookDataFile(book.id);
    if (f.existsSync()) {
      try {
        final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
        return _dedupeHighlights(BookData.fromJson(json, book));
      } catch (_) {
        return BookData(book: book, reading: ReadingState(), highlights: []);
      }
    }
    return BookData(book: book, reading: ReadingState(), highlights: []);
  }

  /// Убирает повторяющиеся заметки (одинаковая фраза в одной главе).
  BookData _dedupeHighlights(BookData data) {
    final seen = <String>{};
    final unique = <Highlight>[];
    for (final h in data.highlights) {
      if (seen.add('${h.chapter}\u0000${h.text}')) unique.add(h);
    }
    if (unique.length != data.highlights.length) {
      data.highlights
        ..clear()
        ..addAll(unique);
    }
    return data;
  }

  Future<void> addBook(
    Book book,
    String sourcePath, {
    String? coverFromPath,
  }) async {
    final dest = File(bookFilePath(book));
    final src = File(sourcePath);
    if (!dest.existsSync()) {
      src.copySync(dest.path);
    }
    if (coverFromPath != null) {
      final coverDest = File(p.join(coversDir.path, '${book.id}.bin'));
      if (!coverDest.existsSync()) {
        File(coverFromPath).copySync(coverDest.path);
      }
      book.coverPath = coverDest.path;
    }
    books.add(book);
    _data[book.id] = BookData(
      book: book,
      reading: ReadingState(),
      highlights: [],
    );
    await save();
  }

  Future<void> updateBook(Book book) async {
    for (var i = 0; i < books.length; i++) {
      if (books[i].id == book.id) {
        books[i] = book;
        break;
      }
    }
    await save();
  }

  Future<void> saveBookData(BookData data, {bool notify = true}) async {
    _ensureDataDir();
    final f = _bookDataFile(data.book.id);
    f.writeAsStringSync(jsonEncode(data.toJson()));
    // Сообщаем экранам (вкладка «Заметки» и т.п.), что данные изменились:
    // они живут в IndexedStack и сами по себе не перестраиваются. Для
    // сохранения только позиции чтения уведомление не нужно — иначе читалка
    // лишний раз перерисовывается на каждом перелистывании.
    if (notify) revision.value++;
  }

  /// Гарантирует существование папки data. Раньше она создавалась через File,
  /// из-за чего появлялся файл `data`, и данные книги не сохранялись.
  Directory _ensureDataDir() {
    final path = p.join(_root!.path, 'data');
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.file) {
      File(path).deleteSync();
    }
    final dir = Directory(path);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<void> removeBook(String id) async {
    books.removeWhere((b) => b.id == id);
    _data.remove(id);
    for (final f in booksDir.listSync()) {
      if (p.basenameWithoutExtension(f.path) == id) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    final dataFile = _bookDataFile(id);
    if (dataFile.existsSync()) dataFile.deleteSync();
    final cover = File(p.join(coversDir.path, '$id.bin'));
    if (cover.existsSync()) cover.deleteSync();
    await save();
  }

  Future<void> save() async {
    final index = File(p.join(_root!.path, 'index.json'));
    index.writeAsStringSync(jsonEncode(books.map((b) => b.toJson()).toList()));
  }

  Future<String> exportJson() async {
    final payload = {
      'app': 'QutZem Reader',
      'exportedAt': DateTime.now().toIso8601String(),
      'books': books.map((b) => b.toJson()).toList(),
      'data': {for (final e in _data.entries) e.key: e.value.toJson()},
    };
    return jsonEncode(payload);
  }

  Future<String> importJson(String json) async {
    final parsed = jsonDecode(json) as Map<String, dynamic>;
    final list = (parsed['books'] as List<dynamic>? ?? [])
        .map((e) => Book.fromJson(e as Map<String, dynamic>))
        .toList();
    var imported = 0;
    for (final book in list) {
      final exists = books.any((b) => b.id == book.id);
      if (exists) continue;
      final src = File(bookFilePath(book));
      if (!src.existsSync()) continue;
      books.add(book);
      final d = parsed['data'] as Map<String, dynamic>?;
      final bd = d?[book.id] as Map<String, dynamic>?;
      _data[book.id] = BookData.fromJson(bd ?? {}, book);
      imported++;
    }
    await save();
    return imported.toString();
  }
}
