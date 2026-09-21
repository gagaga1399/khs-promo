import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ai.dart';
import '../library.dart';
import '../models.dart';
import '../reader/highlight_manager.dart';
import '../reader/reader_screen.dart';
import '../settings.dart';
import 'settings_screen.dart';

enum _NotesTab { notes, quotes, bookmarks }

/// Файловый менеджер заметок по всем книгам.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  AiSettings _ai = AiSettings();
  _NotesTab _tab = _NotesTab.notes;

  @override
  void initState() {
    super.initState();
    _load();
    Library.instance.revision.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    Library.instance.revision.removeListener(_onLibraryChanged);
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final s = await SettingsStore.instance.load();
    if (mounted) setState(() => _ai = s.ai);
  }

  List<({Book book, Highlight highlight})> get _notes =>
      Library.instance.allNotes();

  String _formatDate(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}.${t.month}.${t.year}';
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _exportAll(String? bookId) async {
    final notes = _notes.where((n) => bookId == null || n.book.id == bookId);
    final sb = StringBuffer('QutZem Reader — заметки\n');
    sb.writeln('Создано: ${DateTime.now().toIso8601String()}');
    sb.writeln();
    String? lastBook;
    for (final n in notes) {
      if (bookId == null && n.book.id != lastBook) {
        lastBook = n.book.id;
        sb.writeln('══════════════════════════════════');
        sb.writeln('КНИГА: ${n.book.title}');
        sb.writeln('══════════════════════════════════');
      }
      if (n.highlight.chapterTitle != null) {
        sb.writeln('[${n.highlight.chapterTitle}]');
      }
      sb.writeln('» ${n.highlight.text}');
      if (n.highlight.note != null && n.highlight.note!.trim().isNotEmpty) {
        sb.writeln('  ↳ ${n.highlight.note}');
      }
      sb.writeln();
    }
    final dir = await Directory.systemTemp.createTemp('qutzem_notes_');
    final file = File('${dir.path}\\notes.txt');
    file.writeAsStringSync(sb.toString());
    _snack('Экспортировано в ${file.path}');
    debugPrint('NOTES EXPORTED: ${file.path}');
  }

  Future<void> _openBook(Book book, Highlight h) async {
    final data = Library.instance.dataOf(book.id);
    if (data == null) return;
    final path = Library.instance.bookFilePath(book);
    if (!File(path).existsSync()) {
      _snack('Файл книги отсутствует');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: Library.instance,
          book: book,
          aiSettings: _ai,
          initialHighlight: h,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openBookmark(Book book, Bookmark bm) async {
    final data = Library.instance.dataOf(book.id);
    if (data == null) return;
    final path = Library.instance.bookFilePath(book);
    if (!File(path).existsSync()) {
      _snack('Файл книги отсутствует');
      return;
    }
    data.reading.chapter = bm.chapter;
    data.reading.charOffset = bm.offset;
    await Library.instance.saveBookData(data);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastBookId', book.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: Library.instance,
          book: book,
          aiSettings: _ai,
          initialBookmark: bm,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _deleteBookmark(Book book, Bookmark bm) async {
    await ReaderService(
      library: Library.instance,
      book: book,
      aiSettings: _ai,
    ).removeBookmark(bm);
    if (mounted) setState(() {});
  }

  Future<void> _editNote(({Book book, Highlight highlight}) n) async {
    final controller = TextEditingController(text: n.highlight.note ?? '');
    final color = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Заметка'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(n.highlight.text,
                  style: const TextStyle(fontStyle: FontStyle.italic)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Текст заметки (пусто = удалить)'),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < highlightColors.length; i++)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, 100 + i),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: highlightColors[i],
                        child: n.highlight.colorIndex == i
                            ? const Icon(Icons.check, size: 16)
                            : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, -1),
            child: const Text('Удалить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final note = controller.text.trim();
              Navigator.pop(ctx, note.isEmpty ? -2 : 1);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (color == null || color < 0) {
      if (color == -1) await _deleteNote(n);
      return;
    }
    final note = controller.text.trim();
    final hm = HighlightManager(library: Library.instance, book: n.book);
    if (color == -2) {
      await hm.update(n.highlight, note: null);
    } else {
      final colorIndex = color - 100;
      await hm.update(n.highlight,
          note: note, colorIndex: colorIndex);
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteNote(({Book book, Highlight highlight}) n) async {
    await HighlightManager(library: Library.instance, book: n.book)
        .remove(n.highlight);
    if (mounted) setState(() {});
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _snack('Скопировано');
  }

  Future<void> _openAiSettings() async {
    final s = await SettingsStore.instance.load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: s),
      ),
    );
    await _load();
  }

  void _showBookMenu(({Book book, Highlight highlight}) n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new),
                title: Text('Открыть в книге «${n.book.title}»'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openBook(n.book, n.highlight);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_all),
                title: const Text('Копировать текст'),
                onTap: () {
                  Navigator.pop(ctx);
                  _copyText(n.highlight.text);
                },
              ),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('Что значит термин'),
                subtitle: const Text('Объяснение выделенной фразы по настройкам ИИ'),
                onTap: () {
                  final chapterTitle = n.highlight.chapterTitle;
                  Navigator.pop(ctx);
                  showAiAnalysisDialog(
                    context,
                    _ai,
                    n.highlight.text,
                    kind: AiPromptKind.explainTerm,
                    ctx: AnalysisContext(
                      bookTitle: n.book.title,
                      bookAuthor: n.book.author,
                      chapter: chapterTitle != null &&
                              chapterTitle.trim().isNotEmpty
                          ? chapterTitle.trim()
                          : '',
                    ),
                    onOpenSettings: _openAiSettings,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.psychology),
                title: const Text('Анализ нейросети'),
                subtitle: const Text('Разбор фрагмента по настройкам ИИ'),
                onTap: () {
                  final chapterTitle = n.highlight.chapterTitle;
                  Navigator.pop(ctx);
                  showAiAnalysisDialog(
                    context,
                    _ai,
                    n.highlight.text,
                    ctx: AnalysisContext(
                      bookTitle: n.book.title,
                      bookAuthor: n.book.author,
                      chapter: chapterTitle != null &&
                              chapterTitle.trim().isNotEmpty
                          ? chapterTitle.trim()
                          : '',
                    ),
                    onOpenSettings: _openAiSettings,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Редактировать'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editNote(n);
                },
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Экспорт заметок этой книги'),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportAll(n.book.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteNote(n);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = _notes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Заметки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить',
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Экспорт всех заметок в файл',
            onPressed: notes.isEmpty ? null : () => _exportAll(null),
          ),
        ],
      ),
      body: Column(
        children: [
          _tabSelector(),
          Expanded(
            child: switch (_tab) {
              _NotesTab.notes => _buildNotes(notes),
              _NotesTab.quotes => _buildQuotes(notes),
              _NotesTab.bookmarks => _buildBookmarks(),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          SegmentedButton<_NotesTab>(
            segments: const [
              ButtonSegment(
                value: _NotesTab.notes,
                label: Text('Заметки'),
                icon: Icon(Icons.sticky_note_2_outlined),
              ),
              ButtonSegment(
                value: _NotesTab.quotes,
                label: Text('Цитаты'),
                icon: Icon(Icons.format_quote),
              ),
              ButtonSegment(
                value: _NotesTab.bookmarks,
                label: Text('Закладки'),
                icon: Icon(Icons.bookmarks_outlined),
              ),
            ],
            selected: {_tab},
            onSelectionChanged: (s) =>
                setState(() => _tab = s.first),
          ),
        ],
      ),
    );
  }

  Widget _buildBookmarks() {
    final bookmarks = Library.instance.allBookmarks();
    final grouped = <String, List<({Book book, Bookmark bookmark})>>{};
    final order = <String>[];
    for (final n in bookmarks) {
      final id = n.book.id;
      if (!grouped.containsKey(id)) {
        grouped[id] = [];
        order.add(id);
      }
      grouped[id]!.add(n);
    }
    return bookmarks.isEmpty
        ? const Center(
            child: Text(
              'Пока нет закладок.\nВ книге нажмите «Закладки» и «Добавить».',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
          )
        : ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final id in order) _bookmarkSection(grouped[id]!),
            ],
          );
  }

  Widget _bookmarkSection(
      List<({Book book, Bookmark bookmark})> items) {
    final book = items.first.book;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.menu_book, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  book.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${items.length}',
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        for (final it in items)
          ListTile(
            dense: true,
            leading: const Icon(Icons.bookmark, color: Colors.amber),
            title: Text(
              it.bookmark.label.isNotEmpty
                  ? it.bookmark.label
                  : 'Раздел ${it.bookmark.chapter + 1}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              _formatDate(it.bookmark.createdAt),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _deleteBookmark(book, it.bookmark),
            ),
            onTap: () => _openBookmark(book, it.bookmark),
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildQuotes(
      List<({Book book, Highlight highlight})> notes) {
    if (notes.isEmpty) {
      return const Center(
        child: Text(
          'Пока нет цитат.\nВыдели текст в книге и сохрани его в заметки.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),
      );
    }
    final grouped = <String, List<({Book book, Highlight highlight})>>{};
    final order = <String>[];
    for (final n in notes) {
      final id = n.book.id;
      if (!grouped.containsKey(id)) {
        grouped[id] = [];
        order.add(id);
      }
      grouped[id]!.add(n);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final id in order) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              children: [
                const Icon(Icons.menu_book, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    grouped[id]!.first.book.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('${grouped[id]!.length}',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          for (final n in grouped[id]!)
            _QuoteCard(
              note: n,
              onTap: () => _showBookMenu(n),
              onCopy: () => _copyQuotesText(n),
              formatDate: _formatDate,
            ),
          const Divider(height: 1),
        ],
      ],
    );
  }

  /// Копирование цитаты вместе с атрибуцией (книга · глава).
  Future<void> _copyQuotesText(({Book book, Highlight highlight}) n) async {
    final chapterTitle = n.highlight.chapterTitle;
    final source =
        chapterTitle != null && chapterTitle.trim().isNotEmpty
            ? '${n.book.title}, $chapterTitle'
            : n.book.title;
    await Clipboard.setData(
        ClipboardData(text: '"${n.highlight.text.trim()}"\n\n— $source'));
    _snack('Цитата скопирована');
  }

  Widget _buildNotes(
      List<({Book book, Highlight highlight})> notes) {
    final grouped = <String, List<({Book book, Highlight highlight})>>{};
    final order = <String>[];
    for (final n in notes) {
      final id = n.book.id;
      if (!grouped.containsKey(id)) {
        grouped[id] = [];
        order.add(id);
      }
      grouped[id]!.add(n);
    }
    return notes.isEmpty
        ? const Center(
            child: Text(
              'Пока нет заметок.\nВыдели текст в книге и сохрани его.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15),
            ),
          )
        : ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final id in order)
                _BookSection(
                  book: grouped[id]!.first.book,
                  notes: grouped[id]!,
                  onTapNote: _showBookMenu,
                  formatDate: _formatDate,
                ),
            ],
          );
  }
}

class _QuoteCard extends StatelessWidget {
  final ({Book book, Highlight highlight}) note;
  final VoidCallback onTap;
  final VoidCallback onCopy;
  final String Function(DateTime) formatDate;

  const _QuoteCard({
    required this.note,
    required this.onTap,
    required this.onCopy,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = note.highlight;
    final accent = highlightColors[highlight.colorIndex.clamp(0, highlightColors.length - 1)];
    final chapterTitle = highlight.chapterTitle;
    final parts = [
      if (chapterTitle != null && chapterTitle.trim().isNotEmpty)
        chapterTitle.trim(),
      formatDate(highlight.createdAt),
    ];
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '«${highlight.text.trim()}»',
                    style: const TextStyle(
                        fontSize: 14, fontStyle: FontStyle.italic, height: 1.35),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '— ${note.book.title}${parts.isNotEmpty ? ' · ${parts.join(' · ')}' : ''}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Копировать цитату',
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}

class _BookSection extends StatelessWidget {
  final Book book;
  final List<({Book book, Highlight highlight})> notes;
  final ValueChanged<({Book book, Highlight highlight})> onTapNote;
  final String Function(DateTime) formatDate;

  const _BookSection({
    required this.book,
    required this.notes,
    required this.onTapNote,
    required this.formatDate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.menu_book, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  book.title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('${notes.length}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        for (final n in notes)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 9,
              backgroundColor: highlightColors[n.highlight.colorIndex],
            ),
            title: Text(
              n.highlight.text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              [
                if (n.highlight.chapterTitle != null)
                  n.highlight.chapterTitle!,
                formatDate(n.highlight.createdAt),
                if (n.highlight.note != null &&
                    n.highlight.note!.trim().isNotEmpty)
                  '📝',
              ].join(' · '),
              style: const TextStyle(fontSize: 12),
            ),
            onTap: () => onTapNote(n),
          ),
        const Divider(height: 1),
      ],
    );
  }
}
