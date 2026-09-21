import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../ai.dart';
import '../info.dart';
import '../library.dart';
import '../models.dart';
import 'notes_screen.dart';
import '../reader/reader_screen.dart';
import '../search.dart';import '../settings.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  bool _init = false;
  AiSettings _ai = AiSettings();
  List<OpdsCatalog> _catalogs = SearchService.defaultCatalogs;
  bool _autoOpenedContinue = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await Library.instance.init();
    final settings = await SettingsStore.instance.load();
    _catalogs = settings.catalogs;
    _ai = settings.ai;
    if (mounted) setState(() => _init = true);
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString('lastBookId');
    if (lastId != null && !_autoOpenedContinue) {
      _autoOpenedContinue = true;
      final last = Library.instance.books
          .where((b) => b.id == lastId)
          .toList();
      if (last.isNotEmpty) {
        final book = last.first;
        if (File(Library.instance.bookFilePath(book)).existsSync()) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openBook(book);
          });
        }
      }
    }
  }

  Future<void> _importBook() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub', 'fb2', 'zip'],
    );
    if (result == null || result.isEmpty) return;
    final path = result.single.path;
    if (path == null) return;
    await _addBookFromPath(path);
  }

  Future<void> _addBookFromPath(String path) async {
    final fi = File(path);
    if (!fi.existsSync()) {
      _snack('Файл не найден');
      return;
    }
    if (fi.lengthSync() > SettingsStore.instance.oo.maxBookSizeBytes) {
      _snack(
          'Книга больше лимита (${Config.formatSize(fi.lengthSync())}). '
          'Измените лимит в настройках.');
      return;
    }
    final format = BookFormatExt.fromPath(path);
    if (format == null) {
      _snack('Неподдерживаемый формат');
      return;
    }
    final filePath =
        format == BookFormat.fb2 && path.toLowerCase().endsWith('.zip')
            ? await _extractFb2Zip(path)
            : path;
    if (filePath == null) return;
    final info = await InfoExtractor.of(filePath, format);
    if (!mounted) return;
    setState(() {});
    final id = 'b${DateTime.now().microsecondsSinceEpoch}';
    final book = Book(
      id: id,
      title: info.title,
      author: info.author,
      format: format,
      fileName: p.basename(path),
      sizeBytes: fi.lengthSync(),
      addedAt: DateTime.now(),
    );
    // copy source, then set cover from extracted
    await Library.instance.addBook(book, filePath);
    if (info.coverBytes != null) {
      final coversDir = Library.instance.coversDir;
      final coverFile = File(p.join(coversDir.path, '$id.bin'));
      coverFile.writeAsBytesSync(info.coverBytes!);
      book.coverPath = coverFile.path;
      await Library.instance.updateBook(book);
    }
    if (filePath != path) {
      try {
        File(filePath).deleteSync();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {});
      _snack('Книга добавлена');
    }
  }

  Future<String?> _extractFb2Zip(String zipPath) async {
    try {
      final tempDir =
          Directory.systemTemp.createTempSync('qutzem_fb2_');
      final dest = p.join(tempDir.path, '${DateTime.now().microsecondsSinceEpoch}.fb2');
      final root = await ArchiveService.extractFb2FromZip(zipPath, dest);
      return root ?? dest;
    } catch (_) {
      return null;
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openBook(Book book) async {
    final data = Library.instance.dataOf(book.id);
    if (data == null) return;
    final path = Library.instance.bookFilePath(book);
    if (!File(path).existsSync()) {
      _snack('Файл книги отсутствует');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastBookId', book.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: Library.instance,
          book: book,
          aiSettings: _ai,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_init) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final books = Library.instance.books;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Библиотека'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Заметки',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const NotesScreen()),
              );
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Настройки',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(settings: SettingsStore.instance.oo)),
              );
              if (mounted) {
                final s = await SettingsStore.instance.load();
                _ai = s.ai;
                _catalogs = s.catalogs;
                setState(() {});
              }
            },
          ),
        ],
      ),
      body: books.isEmpty
          ? _emptyState()
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 210,
                mainAxisExtent: 270,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: books.length,
              itemBuilder: (context, i) {
                final book = books[i];
                return _BookCard(
                  book: book,
                  library: Library.instance,
                  onTap: () => _openBook(book),
                  onDelete: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Удалить книгу?'),
                        content: Text('«${book.title}» будет удалена.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Удалить'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await Library.instance.removeBook(book.id);
                      if (mounted) setState(() {});
                    }
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importBook,
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book, size: 72,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          const Text('Библиотека пуста',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Добавьте PDF, EPUB или FB2',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _importBook,
            icon: const Icon(Icons.add),
            label: const Text('Добавить книгу'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SearchScreen(catalogs: _catalogs),
              )).then((_) {
                if (mounted) setState(() {});
              });
            },
            icon: const Icon(Icons.search),
            label: const Text('Найти книги онлайн'),
          ),
        ],
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  final Library library;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.library,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final data = library.dataOf(book.id);
    final progress = data?.reading.progress ?? 0.0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapUp: (details) {
          final overlay =
              Overlay.of(context).context.findRenderObject()! as RenderBox;
          showMenu<int>(
            context: context,
            position: RelativeRect.fromRect(
              details.globalPosition & const Size(1, 1),
              Offset.zero & overlay.size,
            ).inflate(4.0),
            items: [
              PopupMenuItem<int>(
                value: 1,
                child: Row(
                  children: const [
                    Icon(Icons.delete_outline),
                    SizedBox(width: 12),
                    Text('Удалить книгу'),
                  ],
                ),
              ),
            ],
          ).then((v) {
            if (v == 1) onDelete();
          });
        },
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete,
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _cover(context)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (book.author.isNotEmpty)
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.grey.shade300,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(progress * 100).round()}%',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final path = book.coverPath;
    if (path != null && File(path).existsSync()) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 44, color: Colors.grey.shade500),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                book.format.label,
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsStorePersistent {
  final double maxBookSizeBytes;
  SettingsStorePersistent({required this.maxBookSizeBytes});
}

class ArchiveService {
  static Future<String?> extractFb2FromZip(String zipPath, String dest) async {
    final bytes = await File(zipPath).readAsBytes();
    // minimal zip reader for fb2 inside archives created by the same format
    final archive = _simpleZipExtract(bytes);
    for (final e in archive) {
      if (e.name.toLowerCase().endsWith('.fb2')) {
        await File(dest).writeAsBytes(e.bytes);
        return dest;
      }
    }
    return null;
  }
}

class _ZipEntry {
  final String name;
  final List<int> bytes;
  _ZipEntry(this.name, this.bytes);
}

List<_ZipEntry> _simpleZipExtract(List<int> data) {
  // Signature check for plain (non-zip) files
  final result = <_ZipEntry>[];
  try {
    // read local file headers
    int i = 0;
    while (i + 30 <= data.length) {
      if (data[i] == 0x50 && data[i + 1] == 0x4B) {
        final sig = data[i + 2] | (data[i + 3] << 8);
        if (sig == 0x0403) {
          final compMethod = data[i + 8] | (data[i + 9] << 8);
          final compSize = data[i + 18] |
              (data[i + 19] << 8) |
              (data[i + 20] << 16) |
              (data[i + 21] << 24);
          final nameLen = data[i + 26] | (data[i + 27] << 8);
          final extraLen = data[i + 28] | (data[i + 29] << 8);
          final name = String.fromCharCodes(
              data.sublist(i + 30, i + 30 + nameLen));
          if (compMethod == 0) {
            final start = i + 30 + nameLen + extraLen;
            final content = data.sublist(start, start + compSize);
            result.add(_ZipEntry(name, content));
          }
          i = i + 30 + nameLen + extraLen + compSize;
          continue;
        }
      }
      i++;
    }
  } catch (_) {}
  return result;
}