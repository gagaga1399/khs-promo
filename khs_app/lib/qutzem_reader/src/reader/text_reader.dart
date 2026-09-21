import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../ai.dart';
import '../library.dart';
import '../models.dart';
import '../text_document.dart';
import 'reader_screen.dart';
import 'reader_settings.dart';
import 'selection_utils.dart';
import 'text_scale.dart';

class TextReaderWidget extends StatefulWidget {
  final String path;
  final BookFormat format;
  final Book book;
  final Library library;
  final AiSettings aiSettings;
  final int initialChapter;
  final int initialOffset;

  const TextReaderWidget({
    super.key,
    required this.path,
    required this.format,
    required this.book,
    required this.library,
    required this.aiSettings,
    required this.initialChapter,
    required this.initialOffset,
  });

  @override
  State<TextReaderWidget> createState() => _TextReaderWidgetState();
}

class _TextReaderWidgetState extends State<TextReaderWidget> {
  TextDocument? _doc;
  int _chapter = 0;
  double _fontSize = ReaderSettingsStore.defaultFont;
  bool _loading = false;
  String? _error;
  String _lastSelected = '';
  Timer? _saveTimer;
  final ScrollController _scroll = ScrollController();

  ReaderService get _service =>
      ReaderService(library: widget.library, book: widget.book, aiSettings: widget.aiSettings);

  @override
  void initState() {
    super.initState();
    _chapter = widget.initialChapter.clamp(0, 1000000);
    _loadFontSetting();
    _load();
    widget.library.revision.addListener(_onLibraryChanged);
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFontSetting() async {
    final saved = await ReaderSettingsStore.instance.fontSize(spread: false);
    if (!mounted) return;
    setState(() => _fontSize = saved);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.library.revision.removeListener(_onLibraryChanged);
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      TextDocument doc;
      if (widget.format == BookFormat.epub) {
        doc = await TextDocument.fromEpubFile(widget.path);
      } else if (widget.format == BookFormat.fb2) {
        doc = TextDocument.fromFb2File(widget.path);
      } else {
        doc = await TextDocument.fromPdfFile(widget.path) ??
            TextDocument(chapters: []);
      }
      if (doc.chapters.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'В этом PDF-файле не удалось извлечь текстовый слой (возможно, это скан).';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
        if (_chapter >= doc.chapters.length) _chapter = 0;
      });
      _scheduleSave();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScroll();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _restoreScroll() {
    final doc = _doc;
    if (doc == null) return;
    final current = doc.chapters[_chapter];
    if (current.text.isEmpty) return;
    final frac =
        (widget.initialOffset.clamp(0, current.text.length)) / current.text.length;
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent * frac.clamp(0, 1));
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      final doc = _doc;
      if (doc == null) return;
      final current = doc.chapters[_chapter];
      int offset = _scroll.hasClients
          ? (current.text.length *
                  (_scroll.offset / max(1, _scroll.position.maxScrollExtent)))
              .round()
          : widget.initialOffset;
      _service.savePosition(_chapter, offset, doc.chapters.length);
    });
  }

  void _changeChapter(int delta) {
    final doc = _doc;
    if (doc == null) return;
    final next = (_chapter + delta).clamp(0, doc.chapters.length - 1);
    if (next == _chapter) return;
    setState(() => _chapter = next);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _scheduleSave();
  }

  void _gotoChapter(int index) {
    setState(() => _chapter = index);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _doc != null && _doc!.chapters.isNotEmpty
              ? _doc!.chapters[_chapter].title.isNotEmpty
                  ? _doc!.chapters[_chapter].title
                  : widget.book.title
              : widget.book.title,
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            tooltip: 'Оглавление',
            onPressed: _doc == null ? null : _showToc,
          ),
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: 'Размер шрифта',
            onPressed: _doc == null ? null : _showFontPicker,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Добавить закладку',
            onPressed: _doc == null ? null : _addBookmark,
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Закладки',
            onPressed: _doc == null ? null : _showBookmarks,
          ),
        ],
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: _buildBody(),
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'prev',
            tooltip: 'Назад',
            onPressed: _doc == null ? null : () => _changeChapter(-1),
            child: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          FloatingActionButton.small(
            heroTag: 'next',
            tooltip: 'Вперёд',
            onPressed: _doc == null ? null : () => _changeChapter(1),
            child: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('Не удалось открыть книгу:\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Назад'),
              ),
            ],
          ),
        ),
      );
    }
    final doc = _doc!;
    final current = doc.chapters[_chapter];
    final highlights = _service.highlights
        .where((h) => h.chapter == _chapter)
        .toList();

    final spans = <TextSpan>[];
    var pos = 0;
    if (highlights.isEmpty) {
      spans.add(TextSpan(text: current.text));
    } else {
      final sorted = [...highlights]
        ..sort((a, b) => a.start.compareTo(b.start));
      for (final h in sorted) {
        final start = h.start.clamp(0, current.text.length);
        final end = h.end.clamp(start, current.text.length);
        if (end <= pos) continue; // перекрытие — не дублируем
        final from = max(start, pos);
        if (from > pos) {
          spans.add(TextSpan(text: current.text.substring(pos, from)));
        }
        spans.add(TextSpan(
          text: current.text.substring(from, end),
          style: TextStyle(
            backgroundColor: highlightColors[
                h.colorIndex.clamp(0, highlightColors.length - 1)],
          ),
        ));
        pos = end;
      }
      if (pos < current.text.length) {
        spans.add(TextSpan(text: current.text.substring(pos)));
      }
    }

    return Column(
      children: [
        Expanded(
          child: SelectionArea(
            onSelectionChanged: (sel) {
              if (sel != null && sel.plainText.trim().isNotEmpty) {
                setState(() => _lastSelected = sel.plainText);
              }
            },
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (current.title.isNotEmpty) ...[
                    Text(
                      current.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  SelectableText.rich(
                    TextSpan(
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: 1.55,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      children: spans,
                    ),
                    textScaler: readerTextScaler(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_lastSelected.isNotEmpty)
          Material(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Выбрано: ${clip(_lastSelected, 40)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.highlight_alt, size: 18),
                    label: const Text('Выделить'),
                    onPressed: () => _showHighlightActions(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showHighlightActions() async {
    final text = _lastSelected.trim();
    if (text.isEmpty) return;
    showSelectionActions(
      context,
      text,
      (t, color, note) async {
        final doc = _doc;
        if (doc == null) return;
        final chapterText = doc.chapters[_chapter].text;
        final found = findFragment(chapterText, t) ?? [0, 0];
        final end = found[1];
        final added = await _service.addHighlight(
          chapter: _chapter,
          text: t,
          start: found[0],
          end: end,
          colorIndex: color,
          note: note,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(added ? 'Добавлено в заметки' : 'Уже есть в заметках')));
        setState(() => _lastSelected = '');
        _scheduleSave();
      },
      widget.aiSettings,
      analysisContext: _analysisContext(),
    );
  }

  AnalysisContext _analysisContext() {
    final doc = _doc;
    final title = doc != null && _chapter < doc.chapters.length
        ? doc.chapters[_chapter].title
        : '';
    return AnalysisContext(
      bookTitle: widget.book.title,
      bookAuthor: widget.book.author,
      chapter: title.trim().isNotEmpty ? title.trim() : 'Глава ${_chapter + 1}',
    );
  }

  void _showToc() {
    final doc = _doc;
    if (doc == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            itemCount: doc.chapters.length,
            itemBuilder: (ctx, i) {
              final title = doc.chapters[i].title.isNotEmpty
                  ? doc.chapters[i].title
                  : 'Глава ${i + 1}';
              return ListTile(
                dense: true,
                leading: Icon(
                  Icons.menu_book_outlined,
                  color: i == _chapter
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: i == _chapter,
                onTap: () {
                  Navigator.pop(ctx);
                  _gotoChapter(i);
                },
              );
            },
          ),
        );
      },
    );
  }

  void _addBookmark() {
    final doc = _doc;
    if (doc == null) return;
    final current = doc.chapters[_chapter];
    int offset = _scroll.hasClients
        ? (current.text.length *
                (_scroll.offset / max(1, _scroll.position.maxScrollExtent)))
            .round()
        : 0;
    _service.addBookmark(
      chapter: _chapter,
      offset: offset,
      label: doc.chapters[_chapter].title,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Закладка добавлена'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showBookmarks() {
    final doc = _doc;
    if (doc == null) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final service = _service;
            final bookmarks = service.bookmarks.reversed.toList();
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(
                      children: [
                        const Text('Закладки',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _addBookmark();
                          },
                          icon: const Icon(Icons.bookmark_add_outlined),
                          label: const Text('Добавить'),
                        ),
                      ],
                    ),
                  ),
                  if (bookmarks.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Пока нет закладок.\nНажмите «Добавить», чтобы отметить место.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: bookmarks.length,
                        itemBuilder: (ctx, i) {
                          final b = bookmarks[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.bookmark,
                                color: Colors.amber),
                            title: Text(
                              b.label.isNotEmpty
                                  ? b.label
                                  : 'Глава ${b.chapter + 1}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _fmtTs(b.createdAt),
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await service.removeBookmark(b);
                                if (ctx.mounted) setSheetState(() {});
                              },
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _jumpToBookmark(b);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _jumpToBookmark(Bookmark b) {
    final doc = _doc;
    if (doc == null) return;
    final chapter = b.chapter.clamp(0, doc.chapters.length - 1);
    setState(() => _chapter = chapter);
    _scheduleSave();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = doc.chapters[chapter];
      if (current.text.isEmpty || !_scroll.hasClients) return;
      final frac = b.offset.clamp(0, current.text.length) / current.text.length;
      _scroll.jumpTo(_scroll.position.maxScrollExtent * frac.clamp(0, 1));
    });
    _scheduleSave();
  }

  String _fmtTs(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}.${t.month}.${t.year}';
  }

  void _showFontPicker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Размер шрифта',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.text_decrease),
                          onPressed: () {
                            setSheetState(() {
                              _fontSize =
                                  (_fontSize - 1).clamp(12.0, 34.0);
                            });
                            setState(() {});
                            _saveFontSetting();
                          },
                        ),
                        Expanded(
                          child: Slider(
                            min: 12,
                            max: 34,
                            value: _fontSize,
                            label: _fontSize.round().toString(),
                            onChanged: (v) {
                              setSheetState(() => _fontSize = v);
                              setState(() {});
                              _saveFontSetting();
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.text_increase),
                          onPressed: () {
                            setSheetState(() {
                              _fontSize =
                                  (_fontSize + 1).clamp(12.0, 34.0);
                            });
                            setState(() {});
                            _saveFontSetting();
                          },
                        ),
                      ],
                    ),
                    Text('${_fontSize.round()} pt'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Готово'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _saveFontSetting() {
    ReaderSettingsStore.instance
        .setFontSize(_fontSize, spread: false);
  }
}