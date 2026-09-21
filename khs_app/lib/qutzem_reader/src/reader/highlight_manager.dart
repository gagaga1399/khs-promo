import '../library.dart';
import '../models.dart';

/// Хелпер для управления выделениями поверх потока абзацев.
///
/// Выделение хранится как chapter (номер страницы PDF / источник) + смещения
/// в тексте этой главы, что совместимо с существующей моделью [Highlight].
class HighlightManager {
  final Library library;
  final Book book;

  HighlightManager({required this.library, required this.book});

  BookData? get _data => library.dataOf(book.id);
  List<Highlight> get highlights => _data?.highlights ?? const [];

  Future<bool> add({
    required int chapter,
    required String text,
    required int start,
    required int end,
    int colorIndex = 0,
    String? note,
    String? chapterTitle,
  }) async {
    final d = _data;
    if (d == null) return false;
    // Защита от дублей: одинаковая фраза в одной главе добавляется один раз.
    final exists = d.highlights
        .any((e) => e.chapter == chapter && e.text == text);
    if (exists) return false;
    final h = Highlight(
      id: 'h${DateTime.now().microsecondsSinceEpoch}',
      chapter: chapter,
      start: start,
      end: end,
      text: text,
      colorIndex: colorIndex,
      note: note,
      chapterTitle: chapterTitle,
      createdAt: DateTime.now(),
    );
    d.highlights.add(h);
    await library.saveBookData(d);
    return true;
  }

  Future<void> update(Highlight h, {String? note, int? colorIndex}) async {
    final d = _data;
    if (d == null) return;
    final idx = d.highlights.indexWhere((e) => e.id == h.id);
    if (idx < 0) return;
    final e = d.highlights[idx];
    d.highlights[idx] = Highlight(
      id: e.id,
      chapter: e.chapter,
      start: e.start,
      end: e.end,
      text: e.text,
      colorIndex: colorIndex ?? e.colorIndex,
      note: note ?? e.note,
      chapterTitle: e.chapterTitle,
      createdAt: e.createdAt,
    );
    await library.saveBookData(d);
  }

  Future<void> remove(Highlight h) async {
    final d = _data;
    if (d == null) return;
    d.highlights.removeWhere((e) => e.id == h.id);
    await library.saveBookData(d);
  }
}
