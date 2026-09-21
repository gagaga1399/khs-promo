import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../ai.dart';
import '../info.dart';
import '../library.dart';
import '../models.dart';
import '../reader/reader_screen.dart';
import '../settings.dart';

/// Вкладка «Файлы» — файловый менеджер «всё в одном»:
/// обзор диска, папка книг, добавление книг из любого файла.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({super.key});

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  AiSettings _ai = AiSettings();
  bool _ready = false;
  String _currentPath = '';
  bool _inBooksDir = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await SettingsStore.instance.load();
    if (!mounted) return;
    setState(() {
      _ai = s.ai;
      _ready = true;
    });
    _goToBooksDir();
  }

  void _goToBooksDir() {
    final dir = Library.instance.booksDir;
    if (dir.existsSync()) {
      setState(() {
        _currentPath = dir.path;
        _inBooksDir = true;
      });
    }
  }

  void _goToHome() {
    final home =
        Directory('C:\\Users\\${Platform.environment['USERNAME'] ?? 'user'}');
    final dir = Directory(home.path);
    if (dir.existsSync()) {
      setState(() {
        _currentPath = dir.path;
        _inBooksDir = false;
      });
    }
  }

  void _goToPath(String path) {
    final dir = Directory(path);
    if (dir.existsSync()) {
      setState(() {
        _currentPath = path;
        _inBooksDir = path == Library.instance.booksDir.path;
      });
    }
  }

  void _goUp() {
    final parent = p.dirname(_currentPath);
    if (parent == _currentPath) return;
    _goToPath(parent);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Book? _bookForId(String id) {
    for (final b in Library.instance.books) {
      if (b.id == id) return b;
    }
    return null;
  }

  Future<void> _openFile(File f) async {
    final format = BookFormatExt.fromPath(f.path);
    if (format == null) {
      _snack('Не книжный файл');
      return;
    }
    final id = p.basenameWithoutExtension(f.path);
    final book = _bookForId(id);
    if (book != null) {
      final path = Library.instance.bookFilePath(book);
      if (!File(path).existsSync()) {
        _snack('Файл отсутствует в хранилище');
        return;
      }
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
      return;
    }
    // Новый файл — добавляем в библиотеку.
    final added = await _addBook(f.path);
    if (!mounted) return;
    if (added == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: Library.instance,
          book: added,
          aiSettings: _ai,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<Book?> _addBook(String path) async {
    final fi = File(path);
    if (!fi.existsSync()) {
      _snack('Файл не найден');
      return null;
    }
    if (fi.lengthSync() > SettingsStore.instance.oo.maxBookSizeBytes) {
      _snack('Книга больше лимита');
      return null;
    }
    final format = BookFormatExt.fromPath(path);
    if (format == null) {
      _snack('Неподдерживаемый формат');
      return null;
    }
    final info = await InfoExtractor.of(path, format);
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
    await Library.instance.addBook(book, path);
    if (info.coverBytes != null) {
      final coverFile = File(p.join(Library.instance.coversDir.path, '$id.bin'));
      coverFile.writeAsBytesSync(info.coverBytes!);
      book.coverPath = coverFile.path;
      await Library.instance.updateBook(book);
    }
    _snack('Книга добавлена');
    return book;
  }

  Future<void> _reveal(File f) async {
    try {
      await Process.start('explorer.exe', ['/select,', f.path]);
    } catch (_) {
      _snack(f.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final dir = Directory(_currentPath);
    final entries = dir.existsSync()
        ? dir.listSync().toList()
        : <FileSystemEntity>[];
    entries.sort((a, b) {
      final aDir = a is Directory ? 0 : 1;
      final bDir = b is Directory ? 0 : 1;
      if (aDir != bDir) return aDir - bDir;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Файлы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Домой',
            onPressed: _goToHome,
          ),
          IconButton(
            icon: const Icon(Icons.folder_special_outlined),
            tooltip: 'Папка книг',
            onPressed: _goToBooksDir,
          ),
        ],
      ),
      body: Column(
        children: [
          // Строка быстрого доступа.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _quickChip(Icons.home, 'Домой', _goToHome),
                _quickChip(Icons.menu_book, 'Папка книг', _goToBooksDir),
                _quickChip(Icons.description, 'Документы', () {
                  final docs = Directory(
                      'C:\\Users\\${Platform.environment['USERNAME'] ?? 'user'}\\Documents');
                  _goToPath(docs.path);
                }),
                _quickChip(Icons.monitor, 'Рабочий стол', () {
                  final desk = Directory(
                      'C:\\Users\\${Platform.environment['USERNAME'] ?? 'user'}\\Desktop');
                  _goToPath(desk.path);
                }),
              ],
            ),
          ),
          // Текущий путь.
          ListTile(
            dense: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Вверх',
              onPressed: _goUp,
            ),
            title: Text(
              _currentPath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            trailing: _inBooksDir
                ? const Chip(
                    label: Text('Папка книг', style: TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                  )
                : null,
          ),
          const Divider(height: 1),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('Папка пуста'))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      if (e is Directory) {
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined,
                              color: Colors.amber),
                          title: Text(p.basename(e.path),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _goToPath(e.path),
                        );
                      }
                      final f = e as File;
                      final isBook = BookFormatExt.fromPath(f.path) != null;
                      final inBook = _bookForId(p.basenameWithoutExtension(f.path)) != null;
                      return ListTile(
                        leading: Icon(
                          isBook
                              ? Icons.menu_book
                              : _extIcon(f.path),
                          color: isBook ? Colors.teal : Colors.grey,
                        ),
                        title: Text(p.basename(f.path),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(_size(f),
                            style: const TextStyle(fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isBook)
                              IconButton(
                                icon: Icon(
                                  inBook
                                      ? Icons.check_circle_outline
                                      : Icons.add_circle_outline,
                                  size: 20,
                                  color: inBook ? Colors.green : Colors.teal,
                                ),
                                tooltip: inBook
                                    ? 'Уже в библиотеке'
                                    : 'Добавить в библиотеку',
                                onPressed: inBook
                                    ? null
                                    : () async {
                                        await _addBook(f.path);
                                        if (mounted) setState(() {});
                                      },
                              ),
                            if (isBook)
                              IconButton(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                tooltip: 'Читать',
                                onPressed: () => _openFile(f),
                              ),
                            IconButton(
                              icon: const Icon(Icons.folder_open, size: 20),
                              tooltip: 'Показать в проводнике',
                              onPressed: () => _reveal(f),
                            ),
                          ],
                        ),
                        onTap: isBook ? () => _openFile(f) : () {},
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _quickChip(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}

IconData _extIcon(String path) {
  final ext = p.extension(path).toLowerCase();
  switch (ext) {
    case '.txt':
    case '.md':
      return Icons.description;
    case '.pdf':
      return Icons.picture_as_pdf;
    case '.epub':
      return Icons.menu_book;
    case '.fb2':
      return Icons.notes;
    case '.zip':
    case '.rar':
    case '.7z':
      return Icons.folder_zip_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _size(File f) {
  final b = f.lengthSync();
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
  return '${(b / (1024 * 1024)).toStringAsFixed(2)} МБ';
}
