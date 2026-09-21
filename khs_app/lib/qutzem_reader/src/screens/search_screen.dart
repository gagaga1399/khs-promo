import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../info.dart';
import '../library.dart';
import '../models.dart';
import '../reader/reader_screen.dart';
import '../search.dart';
import '../settings.dart';

class SearchScreen extends StatefulWidget {
  final List<OpdsCatalog> catalogs;
  const SearchScreen({super.key, required this.catalogs});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  List<SearchResult>? _results;
  List<Book>? _localBooks;
  bool _loading = false;
  String? _error;
  String? _downloadingUrl;
  List<OpdsCatalog> get _catalogs => widget.catalogs;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    final local = _localSearch(q);
    setState(() {
      _loading = true;
      _error = null;
      _results = null;
      _localBooks = local;
    });
    final service = SearchService(catalogs: _catalogs);
    try {
      final r = await service.search(q);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Поиск по своей библиотеке: результат виден сразу, даже без интернета.
  List<Book> _localSearch(String q) {
    final needle = q.toLowerCase();
    return Library.instance.books.where((b) {
      return (b.title.toLowerCase().contains(needle) ||
              b.author.toLowerCase().contains(needle));
    }).toList();
  }

  Future<void> _openLocalBook(Book book) async {
    final data = Library.instance.dataOf(book.id);
    if (data == null) return;
    final path = Library.instance.bookFilePath(book);
    if (!File(path).existsSync()) {
      _snack('Файл книги отсутствует');
      return;
    }
    final settings = await SettingsStore.instance.load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: Library.instance,
          book: book,
          aiSettings: settings.ai,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _download(SearchResult result, int index) async {
    final limit = SettingsStore.instance.oo.maxBookSizeBytes;
    final id = 'b${DateTime.now().microsecondsSinceEpoch}$index';
    final ext = result.format.extension;
    final tmpDir = await Directory.systemTemp.createTemp('qutzem_dl_');
    final tmpPath = p.join(tmpDir.path, '$id.$ext');
    setState(() => _downloadingUrl = result.downloadUrl);
    final service = SearchService(catalogs: _catalogs);
    try {
      await service.download(result, tmpPath, onProgress: (got, total) {
        if (total > limit && got > limit) {
          throw DownloadTooBigException();
        }
      });
      final fstat = File(tmpPath);
      final size = fstat.lengthSync();
      if (size > limit) {
        throw DownloadTooBigException();
      }
      if (!mounted) {
        fstat.deleteSync();
        return;
      }
      final info = await InfoExtractor.of(tmpPath, result.format);
      if (!mounted) {
        fstat.deleteSync();
        return;
      }
      final book = Book(
        id: id,
        title: info.title,
        author: info.author,
        format: result.format,
        fileName: '${sanitize(info.title)}.$ext',
        sizeBytes: size,
        addedAt: DateTime.now(),
      );
      await Library.instance.addBook(book, tmpPath);
      if (info.coverBytes != null) {
        final coverFile =
            File(p.join(Library.instance.coversDir.path, '$id.bin'));
        coverFile.writeAsBytesSync(info.coverBytes!);
        book.coverPath = coverFile.path;
        await Library.instance.updateBook(book);
      }
      fileDeleteQuiet(tmpDir.path);
      if (!mounted) return;
      setState(() => _downloadingUrl = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Скачано: ${book.title}'),
          action: SnackBarAction(
            label: 'Читать',
            onPressed: () {
              Navigator.pop(context);
            },
          )));
    } on DownloadTooBigException {
      fileDeleteQuiet(tmpDir.path);
      if (!mounted) return;
      setState(() => _downloadingUrl = null);
      _error =
          'Книга «${result.title}» больше лимита ${Config.formatSize(limit.round())} '
          'и не была скачана. Увеличьте лимит в настройках, если хотите её '
          'сохранить.';
      setState(() {});
    } catch (e) {
      fileDeleteQuiet(tmpDir.path);
      if (!mounted) return;
      setState(() => _downloadingUrl = null);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Ошибка скачивания: $e')));
    }
  }

  String sanitize(String s) {
    final cleaned =
        s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'book' : cleaned.substring(0, cleaned.length > 80 ? 80 : cleaned.length);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск книг')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Название, автор…',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                      suffixIcon: Icon(Icons.cloud_done_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _search, child: const Text('Искать')),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Project Gutenberg, Archive.org, Book2You'
                    '${widget.catalogs.where((c) => c.name != 'Book2You').isNotEmpty ? ' + ${widget.catalogs.where((c) => c.name != 'Book2You').map((c) => c.name).join(', ')}' : ''}. '
                    'Поиск в интернете; скачанные книги читаются офлайн.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final local = _localBooks ?? const <Book>[];
    final remote = _results;
    if (_localBooks == null && remote == null && _error == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('Введите запрос для поиска'),
            const SizedBox(height: 6),
            const Text(
                'сначала ищем в вашей библиотеке, затем в интернете',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final tiles = <Widget>[];
    if (local.isNotEmpty) {
      tiles.add(_listHeader('В вашей библиотеке', Icons.library_books));
      tiles.addAll(local.map((b) => _localTile(b)));
    }
    if (remote != null && remote.isNotEmpty) {
      tiles.add(_listHeader('На сайтах', Icons.cloud_done_outlined));
      tiles.addAll(remote.asMap().entries.map((e) => _remoteTile(e.key, e.value)));
    }
    if (tiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error ?? 'Ничего не найдено.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _error!,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          ),
        ...tiles,
      ],
    );
  }

  Widget _listHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _localTile(Book b) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.book, color: Colors.blueGrey),
      title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (b.author.isNotEmpty) b.author, 'в вашей библиотеке']
            .join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openLocalBook(b),
    );
  }

  Widget _remoteTile(int index, SearchResult r) {
    final downloading = _downloadingUrl == r.downloadUrl;
    return ListTile(
      leading: SizedBox(
        width: 46,
        height: 64,
        child: r.coverUrl != null
            ? Image.network(
                r.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    _coverPlaceholder(r.format),
              )
            : _coverPlaceholder(r.format),
      ),
      title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(r.subtitle,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: downloading
          ? const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2))
          : IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Скачать',
              onPressed: () => _download(r, index),
            ),
      onTap: () => r.downloadUrl != null
          ? _download(r, index)
          : null,
    );
  }

  Widget _coverPlaceholder(BookFormat format) {
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: Text(
        format.label,
        style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.grey.shade600),
      ),
    );
  }
}

class DownloadTooBigException implements Exception {
  @override
  String toString() => 'file is too large';
}

void fileDeleteQuiet(String path) {
  try {
    final dir = Directory(path);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {}
}