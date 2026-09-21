import 'package:flutter/material.dart';

import '../ai.dart';
import '../library.dart';
import '../models.dart';
import '../pdf_text.dart';
import '../text_document.dart';
import 'spread_reader.dart';
import 'text_reader.dart';
import 'pdf_reader.dart';

class ReaderScreen extends StatefulWidget {
  final Library library;
  final Book book;
  final AiSettings aiSettings;
  final Highlight? initialHighlight;
  final Bookmark? initialBookmark;

  const ReaderScreen({
    super.key,
    required this.library,
    required this.book,
    required this.aiSettings,
    this.initialHighlight,
    this.initialBookmark,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  _PdfMode? _pdfMode;
  TextDocument? _pdfDoc;
  TextDocument? _textDoc;
  Object? _textError;
  bool _textLoading = false;

  @override
  void initState() {
    super.initState();
    _decidePdfMode();
    if (widget.book.format == BookFormat.epub ||
        widget.book.format == BookFormat.fb2) {
      _loadTextDoc();
    }
  }

  Future<void> _loadTextDoc() async {
    setState(() => _textLoading = true);
    try {
      final path = widget.library.bookFilePath(widget.book);
      TextDocument doc;
      if (widget.book.format == BookFormat.epub) {
        doc = await TextDocument.fromEpubFile(path);
      } else {
        doc = TextDocument.fromFb2File(path);
      }
      if (!mounted) return;
      setState(() {
        _textDoc = doc;
        _textLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _textError = e;
        _textLoading = false;
      });
    }
  }

  Future<void> _decidePdfMode() async {
    if (widget.book.format != BookFormat.pdf) return;
    final path = widget.library.bookFilePath(widget.book);
    final doc = await PdfTextExtractor.tryExtract(path);
    if (!mounted) return;
    setState(() {
      _pdfDoc = doc;
      _pdfMode = (doc != null && doc.chapters.isNotEmpty)
          ? _PdfMode.text
          : _PdfMode.pages;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.library.dataOf(widget.book.id);
    final path = widget.library.bookFilePath(widget.book);
    if (data == null) {
      return const Scaffold(body: Center(child: Text('Книга не найдена')));
    }
    final bm = widget.initialBookmark;
    final reading = data.reading;
    final pdfInitialPage = bm != null ? max(1, bm.chapter) : max(1, reading.chapter);
    final spreadInitial = bm != null
        ? bm.offset
        : (widget.book.format == BookFormat.pdf
            ? reading.charOffset
            : reading.chapter);
    final textInitialChapter = bm != null ? bm.chapter : reading.chapter;
    final textInitialOffset = bm != null ? bm.offset : reading.charOffset;
    switch (widget.book.format) {
      case BookFormat.pdf:
        if (_pdfMode == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (_pdfMode == _PdfMode.pages) {
          return PdfReaderWidget(
            path: path,
            book: widget.book,
            library: widget.library,
            aiSettings: widget.aiSettings,
            initialPage: pdfInitialPage,
          );
        }
        final doc = _pdfDoc;
        if (doc == null || doc.chapters.isEmpty) {
          return PdfReaderWidget(
            path: path,
            book: widget.book,
            library: widget.library,
            aiSettings: widget.aiSettings,
            initialPage: pdfInitialPage,
          );
        }
        return SpreadReader(
          doc: doc,
          book: widget.book,
          library: widget.library,
          aiSettings: widget.aiSettings,
          initialSpread: spreadInitial,
          initialHighlight: widget.initialHighlight,
        );
      case BookFormat.epub:
      case BookFormat.fb2:
        if (_textLoading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (_textError != null) {
          return TextReaderWidget(
            path: path,
            format: widget.book.format,
            book: widget.book,
            library: widget.library,
            aiSettings: widget.aiSettings,
            initialChapter: textInitialChapter,
            initialOffset: textInitialOffset,
          );
        }
        final tdoc = _textDoc;
        if (tdoc == null || tdoc.chapters.isEmpty) {
          return TextReaderWidget(
            path: path,
            format: widget.book.format,
            book: widget.book,
            library: widget.library,
            aiSettings: widget.aiSettings,
            initialChapter: textInitialChapter,
            initialOffset: textInitialOffset,
          );
        }
        return SpreadReader(
          doc: tdoc,
          book: widget.book,
          library: widget.library,
          aiSettings: widget.aiSettings,
          initialSpread: spreadInitial,
          initialHighlight: widget.initialHighlight,
        );
    }
  }
}

enum _PdfMode { pages, text }

class ReaderService {
  final Library library;
  final Book book;
  final AiSettings aiSettings;

  ReaderService({
    required this.library,
    required this.book,
    required this.aiSettings,
  });

  BookData get data => library.dataOf(book.id)!;

  List<Highlight> get highlights => data.highlights;

  List<Bookmark> get bookmarks => data.bookmarks;

  Future<void> savePosition(
      int chapter, int charOffset, int chapterCount) async {
    data.reading.chapter = chapter;
    data.reading.charOffset = charOffset;
    data.reading.chapterCount = chapterCount;
    await library.saveBookData(data, notify: false);
  }

  Future<bool> addHighlight({
    required int chapter,
    required String text,
    required int start,
    required int end,
    int colorIndex = 0,
    String? note,
  }) async {
    final exists = data.highlights
        .any((e) => e.chapter == chapter && e.text == (text.isEmpty ? data.highlights.map((e) => e.text).toString() : text));
    if (exists) return false;
    final h = Highlight(
      id: 'h${DateTime.now().microsecondsSinceEpoch}',
      chapter: chapter,
      start: start,
      end: end,
      text: text.isEmpty ? data.highlights.map((e) => e.text).toString() : text,
      colorIndex: colorIndex,
      note: note,
      createdAt: DateTime.now(),
    );
    data.highlights.add(h);
    await library.saveBookData(data);
    return true;
  }

  Future<void> updateHighlight(Highlight h,
      {String? note, int? colorIndex}) async {
    final idx = data.highlights.indexWhere((e) => e.id == h.id);
    if (idx >= 0) {
      final existing = data.highlights[idx];
      data.highlights[idx] = Highlight(
        id: existing.id,
        chapter: existing.chapter,
        start: existing.start,
        end: existing.end,
        text: existing.text,
        colorIndex: colorIndex ?? existing.colorIndex,
        note: note ?? existing.note,
        createdAt: existing.createdAt,
      );
      await library.saveBookData(data);
    }
  }

  Future<void> removeHighlight(Highlight h) async {
    data.highlights.removeWhere((e) => e.id == h.id);
    await library.saveBookData(data);
  }

  Future<void> addBookmark({
    required int chapter,
    required int offset,
    String? label,
  }) async {
    final b = Bookmark(
      id: 'bm${DateTime.now().microsecondsSinceEpoch}',
      chapter: chapter,
      offset: offset,
      label: label?.trim().isEmpty ?? true ? '' : label!.trim(),
      createdAt: DateTime.now(),
    );
    data.bookmarks.add(b);
    await library.saveBookData(data);
  }

  Future<void> removeBookmark(Bookmark b) async {
    data.bookmarks.removeWhere((e) => e.id == b.id);
    await library.saveBookData(data);
  }
}

const highlightColors = [
  Color(0xFFFFF176),
  Color(0xFFFFAB91),
  Color(0xFF9CCC65),
  Color(0xFF80DEEA),
  Color(0xFFCE93D8),
];

const highlightColorLabels = [
  'Жёлтый',
  'Оранжевый',
  'Зелёный',
  'Голубой',
  'Фиолетовый',
];

void showSelectionActions(
  BuildContext context,
  String selectedText,
  Future<void> Function(String text, int colorIndex, String? note) onHighlight,
  AiSettings aiSettings, {
  AnalysisContext? analysisContext,
}) {
  final text = selectedText.trim();
  if (text.isEmpty) return;
  showBottomSheet(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < highlightColors.length; i++)
                Tooltip(
                  message: 'Выделить (${highlightColorLabels[i]})',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () async {
                      Navigator.pop(ctx);
                      await onHighlight(text, i, null);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: highlightColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey.shade400),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await onHighlight(text, 0, null);
                },
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Заметка'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  showAiAnalysisDialog(ctx, aiSettings, text,
                      ctx: analysisContext);
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('ИИ-разбор'),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…';