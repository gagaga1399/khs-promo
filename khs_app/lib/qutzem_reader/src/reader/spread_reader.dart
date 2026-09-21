import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../ai.dart';
import '../library.dart';
import '../models.dart';
import '../screens/notes_screen.dart';
import '../screens/settings_screen.dart';
import '../settings.dart';
import '../text_document.dart';
import 'book_search.dart';
import 'highlight_manager.dart';
import 'reader_screen.dart';
import 'reader_settings.dart';
import 'selection_utils.dart';
import 'spread_paginator.dart';
import 'text_scale.dart';
import 'theme_data.dart';
import 'toc_panel.dart';

/// Действия в контекстном меню абзаца (правый клик).
enum _BlockAction { copy, quote }

class SpreadReader extends StatefulWidget {
  final TextDocument doc;
  final Book book;
  final Library library;
  final AiSettings aiSettings;
  final int initialSpread;
  final Highlight? initialHighlight;

  const SpreadReader({
    super.key,
    required this.doc,
    required this.book,
    required this.library,
    required this.aiSettings,
    this.initialSpread = 0,
    this.initialHighlight,
  });

  @override
  State<SpreadReader> createState() => _SpreadReaderState();
}

class _SpreadReaderState extends State<SpreadReader> {
  final ScrollController _scrollController = ScrollController();

  double _fontSize = ReaderSettingsStore.defaultFont;
  final double _lineHeight = 1.55;
  ReaderTheme _theme = ReaderTheme.sepia;
  bool _scrollMode = false;
  bool _twoColumns = false;
  bool _spread = false;
  bool _selectMode = true;

  late List<ReaderBlock> _blocks;
  SpreadPaginator? _paginator;
  int _currentPage = 0; // индекс экрана (разворота/страницы)
  int _screenCount = 0;
  int _global = 0; // global block index at top of current page
  bool _loading = true;
  double _buildProgress = 0;
  bool _paginatorCancelled = false;

  Timer? _saveTimer;
  bool _restored = false;
  String _lastSelected = '';
  Highlight? _highlightTarget;

  int? _searchBlockIndex;

  late final HighlightManager _hmanager =
      HighlightManager(library: widget.library, book: widget.book);

  Timer? _selPanelTimer;

  /// SelectionArea поверх лёгких Text-блоков: выделение идёт по символам в
  /// несколько строк/абзацев, без тяжёлого EditableText на всю книгу.
  Widget _buildSelectionRegion(Widget child) {
    return SelectionArea(
      onSelectionChanged: _onSelected,
      contextMenuBuilder: _buildSelectionMenu,
      child: child,
    );
  }

  /// При изменении выделения запоминаем его; панель действий появляется внизу.
  /// Перерисовку откладываем, чтобы не дёргать страницу на каждое движение
  /// мыши при выделении.
  void _onSelected(SelectedContent? content) {
    _selPanelTimer?.cancel();
    final text = content?.plainText.trim() ?? '';
    _lastSelected = text;
    if (text.isEmpty) {
      if (mounted) setState(() {});
      return;
    }
    _selPanelTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
  }

  void _dismissSelection() {
    _selPanelTimer?.cancel();
    _lastSelected = '';
    if (mounted) setState(() {});
  }

  /// Панель действий над выделением: копировать / цитата / заметка / цвета /
  /// анализ ИИ. Видна, пока есть непустое выделение.
  Widget _buildSelectionPanel(ReaderColors colors) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 8,
      right: 8,
      bottom: 86 + bottomPad,
      child: Center(
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(24),
          color: colors.ui,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  clip(_lastSelected, 22),
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                const SizedBox(width: 2),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  color: colors.text,
                  tooltip: 'Копировать',
                  onPressed: () {
                    _copySelection();
                    _dismissSelection();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.format_quote, size: 18),
                  color: colors.text,
                  tooltip: 'Копировать как цитату',
                  onPressed: () {
                    _copySelectionAsQuote();
                    _dismissSelection();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.menu_book, size: 18),
                  color: colors.text,
                  tooltip: 'Что значит термин',
                  onPressed: () => _askTerm(),
                ),
                IconButton(
                  icon: const Icon(Icons.psychology, size: 18),
                  color: colors.accent,
                  tooltip: 'Анализ нейросети',
                  onPressed: () => _analyzeSelection(),
                ),
                IconButton(
                  icon: const Icon(Icons.sticky_note_2, size: 18),
                  color: colors.accent,
                  tooltip: 'В заметки',
                  onPressed: () {
                    _addHighlightFromSelection(0);
                    _dismissSelection();
                  },
                ),
                for (var i = 0; i < highlightColors.length; i++)
                  InkWell(
                    onTap: () {
                      _addHighlightFromSelection(i);
                      _dismissSelection();
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: highlightColors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.muted.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: colors.muted,
                  tooltip: 'Закрыть',
                  onPressed: _dismissSelection,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionMenu(
      BuildContext c, SelectableRegionState state) {
    final text = _lastSelected.trim();
    final items = <ContextMenuButtonItem>[
      ContextMenuButtonItem(
        label: 'Копировать',
        onPressed: () => _copyText(text),
      ),
      ContextMenuButtonItem(
        label: 'Копировать как цитату',
        onPressed: () => _copyTextAsQuote(text),
      ),
      ContextMenuButtonItem(
        label: 'Анализ нейросети',
        onPressed: () => _analyzeSelection(),
      ),
      ContextMenuButtonItem(
        label: 'Что значит термин',
        onPressed: () => _askTerm(),
      ),
      for (var i = 0; i < highlightColors.length; i++)
        ContextMenuButtonItem(
          label: 'В заметки · ${highlightColorLabels[i]}',
          onPressed: () => _saveSelection(text, i),
        ),
    ];
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: state.contextMenuAnchors,
      buttonItems: items,
    );
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скопировано в буфер')));
  }

  Future<void> _copyTextAsQuote(String text) async {
    if (text.isEmpty) return;
    final chapter = _topChapter;
    final chapterTitle = _chapterTitleOf(chapter);
    final quote = '"${text.trim()}"\n\n— ${widget.book.title}'
        '${chapterTitle.isNotEmpty ? ', $chapterTitle' : ''}';
    await Clipboard.setData(ClipboardData(text: quote));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Цитата скопирована (${widget.book.title})')));
  }

  /// Найти (глава, start, end) выделенного текста. Выделение всегда в текущей
  /// главе (странице) или на её границе, поэтому ищем только в ней и соседних,
  /// а не по всей книге — иначе на больших PDF будут зависания.
  (int, int, int)? _locate(String text) {
    final order = <int>[
      _topChapter,
      _topChapter - 1,
      _topChapter + 1,
    ];
    for (final ch in order) {
      if (ch < 0 || ch >= widget.doc.chapters.length) continue;
      final found = findFragment(widget.doc.chapters[ch].text, text);
      if (found != null) return (ch, found[0], found[1]);
    }
    return null;
  }

  Future<void> _saveSelection(String text, int colorIndex) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final loc = _locate(t);
    final chapter = loc?.$1 ?? _topChapter;
    final added = await _hmanager.add(
      chapter: chapter,
      text: t,
      start: loc?.$2 ?? 0,
      end: loc?.$3 ?? 0,
      colorIndex: colorIndex,
      chapterTitle: _chapterTitleOf(chapter),
    );
    _lastSelected = '';
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(added ? 'Добавлено в заметки' : 'Уже есть в заметках')));
    setState(() {});
  }

  int get _topChapter => _blocks.isEmpty
      ? 0
      : _blocks[_global.clamp(0, _blocks.length - 1)].sourceChapter;

  Future<void> _addHighlightFromSelection(int colorIndex) async {
    await _saveSelection(_lastSelected, colorIndex);
  }

  Future<void> _copySelection() async {
    final text = _lastSelected.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скопировано в буфер')));
  }

  /// Скопировать выделение как цитату: текст + книга + глава (как в плагине).
  Future<void> _copySelectionAsQuote() async {
    final text = _lastSelected.trim();
    if (text.isEmpty) return;
    final chapter = _topChapter;
    final chapterTitle = _chapterTitleOf(chapter);
    final quote = '"$text"\n\n— ${widget.book.title}'
        '${chapterTitle.isNotEmpty ? ', $chapterTitle' : ''}';
    await Clipboard.setData(ClipboardData(text: quote));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Цитата скопирована (${widget.book.title})')));
  }

  /// Анализ выделенного фрагмента нейросетью (настройки — в приложении).
  Future<void> _analyzeSelection() async {
    final text = _lastSelected.trim();
    if (text.isEmpty) return;
    await _askAi(text, AiPromptKind.analysis);
  }

  /// Объяснение термина/фразы в контексте текущей книги.
  Future<void> _askTerm() async {
    final text = _lastSelected.trim();
    if (text.isEmpty) return;
    await _askAi(text, AiPromptKind.explainTerm);
  }

  Future<void> _askAi(String text, AiPromptKind kind) async {
    final s = await SettingsStore.instance.load();
    if (!mounted) return;
    final chapter = _topChapter;
    final chapterTitle = _chapterTitleOf(chapter);
    await showAiAnalysisDialog(
      context,
      s.ai,
      text,
      kind: kind,
      ctx: AnalysisContext(
        bookTitle: widget.book.title,
        bookAuthor: widget.book.author,
        chapter: chapterTitle.isNotEmpty
            ? chapterTitle
            : 'Глава ${chapter + 1}',
      ),
      onOpenSettings: _openAiSettings,
    );
  }

  Future<void> _openAiSettings() async {
    final s = await SettingsStore.instance.load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: s),
      ),
    );
  }

  Future<void> _copyBlock(ReaderBlock block) async {
    final text = block.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Скопировано в буфер')));
  }

  Future<void> _copyBlockAsQuote(ReaderBlock block) async {
    final text = block.text.trim();
    if (text.isEmpty) return;
    final chapterTitle = _chapterTitleOf(block.sourceChapter);
    final quote = '"$text"\n\n— ${widget.book.title}'
        '${chapterTitle.isNotEmpty ? ', $chapterTitle' : ''}';
    await Clipboard.setData(ClipboardData(text: quote));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Цитата скопирована (${widget.book.title})')));
  }

  /// Меню абзаца по правому клику: копировать / как цитату.
  void _showBlockMenu(ReaderBlock block, Offset globalPos) {
    showMenu<_BlockAction>(
      context: context,
      position: RelativeRect.fromLTRB(globalPos.dx, globalPos.dy,
          globalPos.dx, globalPos.dy),
      items: const [
        PopupMenuItem(
          value: _BlockAction.copy,
          child: Text('Копировать абзац'),
        ),
        PopupMenuItem(
          value: _BlockAction.quote,
          child: Text('Копировать как цитату'),
        ),
      ],
    ).then((v) {
      if (v == null || !mounted) return;
      if (v == _BlockAction.copy) {
        _copyBlock(block);
      } else if (v == _BlockAction.quote) {
        _copyBlockAsQuote(block);
      }
    });
  }


  void _showTopCopy(BuildContext anchorCtx, ReaderColors colors) {
    final box = anchorCtx.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchor = box == null || overlay == null
        ? RelativeRect.fromLTRB(0, 0, 100, 100)
        : RelativeRect.fromRect(
            Rect.fromPoints(
              box.localToGlobal(Offset.zero, ancestor: overlay),
              box.localToGlobal(
                  box.size.bottomRight(Offset.zero), ancestor: overlay),
            ),
            Offset.zero & overlay.size,
          );
    showMenu<_BlockAction>(
      context: context,
      position: anchor,
      items: const [
        PopupMenuItem(
          value: _BlockAction.copy,
          child: Text('Копировать текущий абзац'),
        ),
        PopupMenuItem(
          value: _BlockAction.quote,
          child: Text('Копировать как цитату'),
        ),
      ],
    ).then((v) {
      if (v == null || !mounted) return;
      if (_blocks.isEmpty) return;
      final block = _blocks[_global.clamp(0, _blocks.length - 1)];
      if (v == _BlockAction.copy) {
        _copyBlock(block);
      } else if (v == _BlockAction.quote) {
        _copyBlockAsQuote(block);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _global = widget.initialSpread;
    _loadSettings();
    _buildBlocks();
    widget.library.revision.addListener(_onLibraryChanged);
  }

  /// Заметку могли удалить/изменить на другом экране — перерисовываем книгу,
  /// чтобы снять/поставить подсветку.
  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    double font;
    ReaderTheme theme;
    bool scroll;
    bool cols;
    try {
      final s = ReaderSettingsStore.instance;
      font = await s.fontSize();
      theme = await s.theme();
      scroll = await s.scrollMode();
      cols = await s.twoColumns();
    } catch (_) {
      font = ReaderSettingsStore.defaultFont;
      theme = ReaderTheme.sepia;
      scroll = false;
      cols = false;
    }
    if (!mounted) return;
    setState(() {
      _fontSize = font;
      _theme = theme;
      _scrollMode = scroll;
      _twoColumns = cols;
    });
    _scheduleSave();
  }

  Future<void> _persistSettings() async {
    try {
      final s = ReaderSettingsStore.instance;
      await s.setFontSize(_fontSize);
      await s.setTheme(_theme);
      await s.setScrollMode(_scrollMode);
      await s.setTwoColumns(_twoColumns);
    } catch (_) {}
  }

  @override
  void dispose() {
    _paginatorCancelled = true;
    _saveTimer?.cancel();
    _selPanelTimer?.cancel();
    _reflowTimer?.cancel();
    widget.library.revision.removeListener(_onLibraryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _buildBlocks() {
    final blocks = <ReaderBlock>[];
    for (var c = 0; c < widget.doc.chapters.length; c++) {
      final ch = widget.doc.chapters[c];
      final lines = ch.text.split(RegExp(r'\n{1,}'));
      var first = true;
      var charPos = 0;
      for (final raw in lines) {
        final t = raw.trim();
        if (t.isEmpty) {
          charPos += raw.length + 1;
          continue;
        }
        final isHeading = first && c < widget.doc.chapters.length &&
            t.length < 90 && t == _titleOf(ch);
        final start = charPos;
        final end = start + t.length;
        blocks.add(ReaderBlock(
          text: t,
          sourceChapter: c,
          isHeading: isHeading,
          startChar: start,
          endChar: end,
        ));
        first = false;
        charPos = end + 1;
      }
    }
    _blocks = blocks;
  }

  String _titleOf(TextChapter ch) => ch.title.trim();

  String _chapterTitleOf(int chapter) =>
      (chapter >= 0 && chapter < widget.doc.chapters.length)
          ? _titleOf(widget.doc.chapters[chapter])
          : 'Стр. ${chapter + 1}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_restored) {
        _restored = true;
        await _rebuildPaginator();
        if (!mounted) return;
        setState(() => _loading = false);
        final target = widget.initialHighlight != null
            ? _blockForHighlight(widget.initialHighlight!)
            : _global;
        _jumpToBlock(target, animate: false);
        _scheduleSave();
        if (widget.initialHighlight != null) {
          _highlightTarget = widget.initialHighlight!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
        }
      }
    });
  }

  /// Найти глобальный индекс блока, соответствующий заметке (глава + текст).
  int _blockForHighlight(Highlight h) {
    for (var i = 0; i < _blocks.length; i++) {
      final b = _blocks[i];
      if (b.sourceChapter != h.chapter) continue;
      if (h.text.isNotEmpty && b.text.contains(h.text.trim())) return i;
    }
    for (var i = 0; i < _blocks.length; i++) {
      if (_blocks[i].sourceChapter == h.chapter) return i;
    }
    return h.chapter.clamp(0, _blocks.isEmpty ? 0 : _blocks.length - 1);
  }

  Future<void> _rebuildPaginator() async {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final useSpread = _twoColumns && size.width >= 700 && !_scrollMode;
    final colWidth = useSpread ? (size.width - 24) / 2 - 8 : size.width - 40;
    // Область чтения: между верхней и нижней панелями, с учётом системных
    // отступов — иначе на телефоне текст прячется под статус-бар/панель.
    final topInset = mq.padding.top + 52;
    final bottomInset = mq.padding.bottom + 76;
    final pageHeight = (size.height - topInset - bottomInset - 24)
        .clamp(200.0, double.infinity)
        .toDouble();
    final scaler = readerTextScaler(context);
    final pager = SpreadPaginator(
      blocks: _blocks,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      pageHeight: pageHeight,
      columnWidth: colWidth,
      columns: 1,
      textScaler: scaler,
    );
    _paginator = pager;
    if (mounted) setState(() {}); // показать прогресс-оверлей
    await pager.build(
      onProgress: (p) {
        if (mounted) setState(() => _buildProgress = p);
      },
      isCancelled: () => _paginatorCancelled,
    );
    if (!mounted) return;
    setState(() {
      _buildProgress = 1;
      _spread = useSpread;
      _screenCount = useSpread
          ? (pager.pageCount + 1) ~/ 2
          : pager.pageCount;
      _currentPage = _screenForBlock(_global);
    });
    if (!_scrollMode) {
      _global = _blockForScreen(_currentPage);
    }
  }

  /// Экран (разворот/страницу), которому принадлежит глобальный блок.
  int _screenForBlock(int block) {
    final pager = _paginator;
    if (pager == null) return 0;
    final page = pager.spreadForBlock(block);
    if (!_spread) return page;
    return page ~/ 2;
  }

  /// Глобальный индекс блока в начале левой колонки экрана [_screen].
  int _blockForScreen(int screen) {
    final pager = _paginator;
    if (pager == null) return 0;
    final page = _spread ? screen * 2 : screen;
    return pager.blockForSpread(page.clamp(0, pager.pageCount - 1));
  }

  /// Перелистывание на [delta] экранов (разворотов/страниц).
  void _flipPage(int delta) {
    final pager = _paginator;
    if (pager == null || !pager.isReady) return;
    final next = (_currentPage + delta)
        .clamp(0, max(0, _screenCount - 1))
        .toInt();
    if (next == _currentPage) return;
    setState(() => _currentPage = next);
    _global = _blockForScreen(next);
    _scheduleSave();
  }

  void _jumpToBlock(int block, {bool animate = true}) {
    final pager = _paginator;
    if (pager == null) return;
    if (_scrollMode) {
      if (_scrollController.hasClients) {
        final idx = _blocks.isEmpty
            ? 0
            : block.clamp(0, _blocks.length - 1);
        final target = (idx / _blocks.length) *
            _scrollController.position.maxScrollExtent;
        if (animate) {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
          );
        } else {
          _scrollController.jumpTo(target);
        }
      }
      _global = block;
      setState(() {});
    } else {
      _global = block;
      setState(() => _currentPage = _screenForBlock(block));
      _scheduleSave();
    }
  }

  void _gotoTocBlock(int block) {
    _global = block;
    _scheduleSave();
    _jumpToBlock(block);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      final service = ReaderService(
          library: widget.library, book: widget.book, aiSettings: widget.aiSettings);
      service.savePosition(_global, 0, _blocks.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = resolveThemeColors(context, _theme) ??
        readerThemeColors[ReaderTheme.light]!;
    final pager = _paginator;
    final notReady = _loading ||
        (!_scrollMode && (pager == null || !pager.isReady));
    return Scaffold(
      backgroundColor: colors.background,
      body: Stack(
        children: [
          if (_scrollMode)
            _buildScrollBody(colors)
          else
            _buildPagedBody(colors),
          _buildTopBar(colors),
          _buildBottomBar(colors),
          if (_lastSelected.trim().isNotEmpty) _buildSelectionPanel(colors),
          if (notReady)
            _buildProgressOverlay(colors),
        ],
      ),
    );
  }

  Widget _buildProgressOverlay(ReaderColors colors) {
    return Positioned.fill(
      child: ColoredBox(
        color: colors.background.withValues(alpha: 0.9),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Подготовка книги… ${(_buildProgress * 100).round()}%',
                style: TextStyle(color: colors.text, fontSize: 14),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () {
                  _paginatorCancelled = true;
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Вернуться на главную'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPagedBody(ReaderColors colors) {
    final pager = _paginator;
    if (pager == null || !pager.isReady || pager.pageCount == 0) {
      return const SizedBox.shrink();
    }
    final screen =
        _currentPage.clamp(0, max(0, _screenCount - 1)).toInt();
    final page = _spread ? screen * 2 : screen;
    final rightPage = page + 1;
    final leftLayout =
        pager.pages[page.clamp(0, pager.pageCount - 1).toInt()];
    final rightLayout =
        rightPage < pager.pageCount ? pager.pages[rightPage] : null;

    final content = _spread
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _renderPageContents(
                    pager, leftLayout, colors, isSpread: true),
              ),
              Container(width: 24, color: colors.background),
              Expanded(
                child: rightLayout != null
                    ? _renderPageContents(
                        pager, rightLayout, colors, isSpread: true)
                    : ColoredBox(
                        color: colors.background,
                        child: const SizedBox.expand()),
              ),
            ],
          )
        : _renderPageContents(
            pager, leftLayout, colors, isSpread: false);

    final body = _selectMode
        ? content
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _flipPage(1),
              child: content,
            ),
          );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.pageDown) {
            _flipPage(1);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.pageUp) {
            _flipPage(-1);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.keyC &&
              HardwareKeyboard.instance.isControlPressed) {
            final text = _lastSelected.trim();
            if (text.isNotEmpty) {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Скопировано в буфер (Ctrl+C)')));
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
  }

  Widget _renderPageContents(SpreadPaginator pager, PageLayout layout,
      ReaderColors colors,
      {required bool isSpread}) {
    final col = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = layout.startBlock; i < layout.endBlock; i++)
          _renderBlock(pager.blocks[i], colors, index: i),
      ],
    );
    final content = _selectMode ? _buildSelectionRegion(col) : col;
    final topInset = MediaQuery.of(context).padding.top + 52;
    return Container(
      color: colors.background,
      alignment: Alignment.topLeft,
      padding: EdgeInsets.fromLTRB(
          isSpread ? 8 : 20, topInset + 12, isSpread ? 8 : 20, 12),
      child: content,
    );
  }

  Widget _renderBlock(ReaderBlock block, ReaderColors colors, {int? index}) {
    if (block.isPageBreak) return const SizedBox(height: 24);
    final spans = _blockSpans(block, colors);
    final t = _highlightTarget;
    final isTarget = t != null &&
        t.chapter == block.sourceChapter &&
        (t.text.isEmpty || block.text.contains(t.text.trim()));
    final isSearchBlock = _searchBlockIndex != null &&
        _searchBlockIndex! >= 0 &&
        _searchBlockIndex! < _blocks.length &&
        identical(_blocks[_searchBlockIndex!], block);

    final lineStyle = TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      color: colors.text,
      fontWeight: block.isHeading ? FontWeight.bold : FontWeight.normal,
    );
    Widget blockContent() {
      final span = TextSpan(style: lineStyle, children: spans);
      final scaler = readerTextScaler(context);
      if (_selectMode) {
        // В режиме выделения — лёгкий Text.rich: SelectionArea умеет выделять
        // по символам в несколько абзацев, без тяжёлого EditableText.
        return Text.rich(span, textScaler: scaler);
      }
      // Режим перелистывания: тап по блоку — контекстное меню по правой
      // кнопке; листание страницы обрабатывается снаружи в _buildPagedBody.
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapDown: (details) =>
            _showBlockMenu(block, details.globalPosition),
        child: RichText(text: span, textScaler: scaler),
      );
    }

    Widget rich() => blockContent();

    if (!isTarget && !isSearchBlock) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: rich(),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSearchBlock
              ? const Color(0xFFFFF176).withValues(alpha: 0.45)
              : colors.accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(6),
        ),
        child: rich(),
      ),
    );
  }

  List<TextSpan> _blockSpans(ReaderBlock block, ReaderColors colors) {
    final text = block.text;
    if (text.isEmpty) return const [];
    // Закрашенные заметки этой главы, попадающие в диапазон блока.
    final ranges = <(int, int, int)>[]; // (start, end, colorIndex)
    for (final h in _hmanager.highlights) {
      if (h.chapter != block.sourceChapter) continue;
      final hs = h.start.clamp(block.startChar, block.endChar);
      final he = h.end.clamp(hs, block.endChar);
      if (he > hs) ranges.add((hs, he, h.colorIndex));
    }
    if (ranges.isEmpty) return [TextSpan(text: text)];
    ranges.sort((a, b) {
      final c = a.$1.compareTo(b.$1);
      return c != 0 ? c : b.$2.compareTo(a.$2);
    });
    final spans = <TextSpan>[];
    var pos = 0;
    for (final r in ranges) {
      final rs = r.$1 - block.startChar;
      final re = r.$2 - block.startChar;
      if (re <= pos) continue; // полностью перекрыт — не дублируем закраску
      final start = max(rs, pos);
      if (start > pos) spans.add(TextSpan(text: text.substring(pos, start)));
      spans.add(TextSpan(
        text: text.substring(start, re),
        style: TextStyle(
          backgroundColor:
              highlightColors[r.$3.clamp(0, highlightColors.length - 1)],
        ),
      ));
      pos = re;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return spans;
  }

  Widget _buildScrollBody(ReaderColors colors) {
    final twoCol = _twoColumns &&
        (MediaQuery.of(context).size.width >= 700);
    final colCount = twoCol ? 2 : 1;
    final list = ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 64, 20, 120),
      itemCount: colCount == 1 ? _blocks.length : ((_blocks.length + 1) ~/ 2),
      itemBuilder: (context, r) {
        if (colCount == 1) {
          return _renderBlock(_blocks[r], colors, index: r);
        }
        final left = r * 2;
        final right = left + 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _renderBlock(_blocks[left], colors, index: left),
            ),
            if (right < _blocks.length)
              Expanded(
                child: _renderBlock(_blocks[right], colors, index: right),
              ),
          ],
        );
      },
    );
    if (!_selectMode) return list;
    return _buildSelectionRegion(list);
  }

  Widget _buildTopBar(ReaderColors colors) {
    return Positioned(
      top: MediaQuery.of(context).padding.top,
      left: 0,
      right: 0,
      child: Container(
        color: colors.ui.withValues(alpha: 0.95),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: colors.text,
              onPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: Text(
                widget.book.title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.text, fontSize: 15),
              ),
            ),
            // На узких экранах (телефоны) 7 кнопок не помещаются — группа
            // скроллится горизонтально, чтобы поиск и настройки были доступны.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.view_list_outlined),
                    color: colors.text,
                    tooltip: 'Оглавление',
                    onPressed: () => _showToc(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    color: colors.text,
                    tooltip: 'Поиск по книге',
                    onPressed: () => _showSearch(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.sticky_note_2_outlined),
                    color: colors.text,
                    tooltip: 'Заметки',
                    onPressed: () => _openNotesManager(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.bookmarks_outlined),
                    color: colors.text,
                    tooltip: 'Закладки',
                    onPressed: () => _showBookmarks(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.ios_share),
                    color: colors.text,
                    tooltip: 'Экспорт цитат в Markdown',
                    onPressed: () => _exportQuotes(),
                  ),
                  Builder(builder: (btnCtx) {
                    return IconButton(
                      icon: const Icon(Icons.content_copy),
                      color: colors.text,
                      tooltip: 'Копировать текущий абзац / как цитату',
                      onPressed: () => _showTopCopy(btnCtx, colors),
                    );
                  }),
                  IconButton(
                    icon: const Icon(Icons.format_size),
                    color: colors.text,
                    tooltip: 'Настройки текста',
                    onPressed: () => _showTextSettings(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(ReaderColors colors) {
    final pager = _paginator;
    final totalPages =
        pager != null && pager.isReady ? max(1, _screenCount) : 1;
    final canPrev = _currentPage > 0;
    final canNext = _scrollMode
        ? _global < _blocks.length - 1
        : _currentPage < totalPages - 1;
    final progress = _scrollMode
        ? (_blocks.isEmpty ? 0.0 : ((_global + 1) / _blocks.length))
        : (totalPages > 0 ? _currentPage / totalPages : 0.0);
    final label = _scrollMode
        ? '${(progress * 100).round()}%'
        : '${_currentPage + 1}/$totalPages';
    final remaining = _formatTime(_remainingReading());
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        color: colors.ui.withValues(alpha: 0.95),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 6,
          top: 4,
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              color: colors.text,
              tooltip: 'Назад',
              onPressed: canPrev
                  ? () => _scrollMode
                      ? _jumpToBlock(max(0, _global - 8))
                      : _flipPage(-1)
                  : null,
            ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$label · осталось ~$remaining',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.text, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 4,
                        backgroundColor: colors.border.withValues(alpha: 0.5),
                        valueColor: AlwaysStoppedAnimation(colors.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                _selectMode
                    ? Icons.text_fields
                    : Icons.text_fields_outlined,
              ),
              color: _selectMode ? colors.accent : colors.text,
              tooltip: 'Режим выделения: '
                  '${_selectMode ? 'вкл — выделяйте текст мышью' : 'выкл — листайте'}',
              onPressed: () => setState(() {
                _selectMode = !_selectMode;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              color: colors.text,
              tooltip: 'Вперёд',
              onPressed: canNext
                  ? () => _scrollMode
                      ? _jumpToBlock(min(_blocks.length - 1, _global + 8))
                      : _flipPage(1)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Оценка оставшегося времени чтения в секундах.
  ///
  /// Примерно 250 слов/мин при ~5 символов на слово → ~50 символов/сек.
  double _remainingReading() {
    final total = widget.doc.totalChars;
    if (total <= 0) return 0;
    final progress = _scrollMode
        ? (_blocks.isEmpty ? 0.0 : ((_global + 1) / _blocks.length))
        : (_paginator != null && _paginator!.isReady && _paginator!.pageCount > 0
            ? _currentPage / _paginator!.pageCount
            : 0.0);
    final remainingChars = total * (1 - progress.clamp(0.0, 1.0));
    return remainingChars / 50.0;
  }

  String _formatTime(double seconds) {
    if (seconds < 60) return '${seconds.round()} сек';
    final mins = (seconds / 60).round();
    if (mins < 60) return '$mins мин';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '$h ч $m мин';
  }

  void _openNotesManager() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const NotesScreen(),
      ),
    );
  }

  Future<void> _exportQuotes() async {
    final highlights = _hmanager.highlights;
    if (highlights.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('В этой книге пока нет выделений.')));
      return;
    }
    final sb = StringBuffer();
    sb.writeln('# ${widget.book.title}');
    if (widget.book.author.isNotEmpty) {
      sb.writeln('*${widget.book.author}*');
    }
    sb.writeln();
    sb.writeln('_Экспорт цитат из QutZem Reader — '
        '${DateTime.now().toIso8601String()}_');
    sb.writeln();
    String? lastChapter;
    for (final h in highlights) {
      final ch = h.chapterTitle ?? 'Глава ${h.chapter + 1}';
      if (ch != lastChapter) {
        lastChapter = ch;
        sb.writeln();
        sb.writeln('## $ch');
      }
      sb.writeln('> ${h.text.trim()}');
      if (h.note != null && h.note!.trim().isNotEmpty) {
        sb.writeln();
        sb.writeln('Заметка: ${h.note!.trim()}');
      }
      sb.writeln();
    }
    final dir = await getDownloadsDirectory();
    final targetDir =
        dir ?? Directory(p.join((await Library.instance.root).path, 'exports'));
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    final safe = widget.book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File(p.join(targetDir.path, '$safe-цитаты.md'));
    file.writeAsStringSync(sb.toString());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Экспортировано: ${file.path}'),
        duration: const Duration(seconds: 4)));
  }

  void _showToc() {
    final colors = resolveThemeColors(context, _theme) ??
        readerThemeColors[ReaderTheme.light]!;
    showTocSheet(
      context,
      _blocks,
      widget.doc,
      colors,
      _global,
      (block) => _gotoTocBlock(block),
    );
  }

  void _showSearch() {
    final colors = resolveThemeColors(context, _theme) ??
        readerThemeColors[ReaderTheme.light]!;
    showBookSearchSheet(
      context,
      _blocks,
      [for (final c in widget.doc.chapters) c.title],
      colors,
      (block) {
        _gotoSearchBlock(block);
      },
    );
  }

  void _gotoSearchBlock(int block) {
    setState(() => _searchBlockIndex = block);
    _jumpToBlock(block);
    _scheduleSave();
  }

  ReaderService get _service => ReaderService(
      library: widget.library,
      book: widget.book,
      aiSettings: widget.aiSettings);

  String _fmtTs(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}.${t.month}.${t.year}';
  }

  void _addBookmark() {
    _service.addBookmark(chapter: _topChapter, offset: _global);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Закладка добавлена'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showBookmarks() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: resolveThemeColors(context, _theme)?.ui,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final colors = resolveThemeColors(context, _theme) ??
                readerThemeColors[ReaderTheme.light]!;
            final service = _service;
            final bookmarks = service.bookmarks.reversed.toList();
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Row(
                      children: [
                        Text('Закладки',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: colors.text)),
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
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Пока нет закладок.\nНажмите «Добавить», чтобы отметить место.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.muted, fontSize: 13),
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
                            leading:
                                Icon(Icons.bookmark, color: colors.accent),
                            title: Text(
                              b.label.isEmpty
                                  ? 'Раздел ${b.chapter + 1}'
                                  : b.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: colors.text),
                            ),
                            subtitle: Text(
                              _fmtTs(b.createdAt),
                              style: TextStyle(
                                  color: colors.muted, fontSize: 12),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              color: colors.muted,
                              onPressed: () async {
                                await service.removeBookmark(b);
                                if (ctx.mounted) setSheetState(() {});
                              },
                            ),
                            onTap: () {
                              Navigator.pop(ctx);
                              _jumpToBlock(
                                  b.offset.clamp(0, _blocks.length - 1));
                              _scheduleSave();
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

  void _showTextSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: resolveThemeColors(context, _theme)?.ui,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Текст',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: resolveThemeColors(context, _theme)?.text)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.text_decrease),
                          onPressed: () {
                            setSheetState(() {
                              _fontSize =
                                  (_fontSize - 1).clamp(readerMinFont, readerMaxFont);
                            });
                            setState(() {});
                            _reflow();
                          },
                        ),
                        Expanded(
                          child: Slider(
                            min: readerMinFont,
                            max: readerMaxFont,
                            value: _fontSize,
                            onChanged: (v) {
                              setSheetState(() => _fontSize = v);
                              setState(() {});
                              _reflow();
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.text_increase),
                          onPressed: () {
                            setSheetState(() {
                              _fontSize =
                                  (_fontSize + 1).clamp(readerMinFont, readerMaxFont);
                            });
                            setState(() {});
                            _reflow();
                          },
                        ),
                      ],
                    ),
                    Text('${_fontSize.round()} pt',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: resolveThemeColors(context, _theme)?.text)),
                    const Divider(),
                    Text('Тема',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: resolveThemeColors(context, _theme)?.text)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in ReaderTheme.values)
                          ChoiceChip(
                            label: Text(t.label),
                            selected: t == _theme,
                            onSelected: (_) {
                              setSheetState(() {});
                              setState(() => _theme = t);
                              _persistSettings();
                            },
                          ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      children: [
                        Text('Режим',
                            style: TextStyle(
                                color: resolveThemeColors(context, _theme)?.text)),
                        const Spacer(),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('Страницы')),
                            ButtonSegment(value: true, label: Text('Прокрутка')),
                          ],
                          selected: {_scrollMode},
                          onSelectionChanged: (s) {
                            setSheetState(() {});
                            setState(() => _scrollMode = s.first);
                            _reflow();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('Колонки',
                            style: TextStyle(
                                color: resolveThemeColors(context, _theme)?.text)),
                        const Spacer(),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('1')),
                            ButtonSegment(value: true, label: Text('2')),
                          ],
                          selected: {_twoColumns},
                          onSelectionChanged: (s) {
                            setSheetState(() {});
                            setState(() => _twoColumns = s.first);
                            _reflow();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
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

  Timer? _reflowTimer;

  void _reflow() {
    _persistSettings();
    if (_scrollMode) {
      // В прокрутке пагинатор не нужен — просто перерисовываем текст.
      if (mounted) setState(() {});
      return;
    }
    // Постраничный режим: переразбивку делаем с задержкой, чтобы ползунок
    // шрифта не запускал тяжёлую пагинацию на каждое тик (крупные PDF это
    // подвешивают).
    _reflowTimer?.cancel();
    _reflowTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _rebuildPaginator();
    });
  }
}
