import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'library.dart';
import 'models.dart';

class SearchResult {
  final String title;
  final String author;
  final String? coverUrl;
  final String? downloadUrl; // direct link to file
  final String source;
  final int? sizeBytes;
  final BookFormat format;

  SearchResult({
    required this.title,
    required this.author,
    this.coverUrl,
    this.downloadUrl,
    required this.source,
    this.sizeBytes,
    this.format = BookFormat.epub,
  });

  String get subtitle {
    final parts = <String>[
      if (author.isNotEmpty) author,
      source,
      if (sizeBytes != null) '~${Config.formatSize(sizeBytes!)}',
    ];
    return parts.join(' · ');
  }
}

class OpdsCatalog {
  final String name;
  final String url;

  OpdsCatalog({required this.name, required this.url});

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  factory OpdsCatalog.fromJson(Map<String, dynamic> json) => OpdsCatalog(
        name: json['name'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );
}

class SearchService {
  /// Каталоги по умолчанию. Надёжные источники (Gutenberg, Archive.org,
  /// Book2You) встраиваются безусловно — см. [search].
  static final defaultCatalogs = <OpdsCatalog>[
    OpdsCatalog(
      name: 'Book2You',
      url: 'https://book2you.net',
    ),
  ];

  static const _timeout = Duration(seconds: 10);

  static const _chromeUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0 Safari/537.36';

  /// Специальные источники, не работающие по протоколу OPDS.
  static final catalogBuilders = <String, String>{
    'Book2You': 'book2you',
  };

  final List<OpdsCatalog> catalogs;

  SearchService({List<OpdsCatalog>? catalogs})
      : catalogs = catalogs ?? defaultCatalogs;

  Map<String, String> _headers() => {
        'User-Agent': _chromeUa,
        'Accept':
            'text/html,application/atom+xml,application/xml,application/json;q=0.9,*/*;q=0.8',
      };

  OpdsCatalog get _book2youCatalog {
    for (final c in catalogs) {
      if (c.name == 'Book2You') return c;
    }
    return defaultCatalogs.first;
  }

  Future<List<SearchResult>> search(String query,
      {int maxResults = 20}) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    // Встроенные надёжные источники + OPDS-каталоги из настроек.
    // Все ищем параллельно с общим таймаутом, чтобы поиск не «зависал».
    final futures = <String, Future<List<SearchResult>>>{
      'Project Gutenberg': _searchGutenberg(q, maxResults),
      'Archive.org': _searchArchiveOrg(q, maxResults),
      'Book2You': _searchBook2You(_book2youCatalog, q, maxResults),
      for (final catalog in catalogs)
        if (catalogBuilders[catalog.name] == null)
          catalog.name: _searchOpds(catalog, q, maxResults),
    };
    final failed = <String>[];
    Future<List<SearchResult>> guard(
        String name, Future<List<SearchResult>> f) async {
      try {
        return await f.timeout(_timeout * 2);
      } catch (_) {
        failed.add(name);
        return const [];
      }
    }

    List<List<SearchResult>> settled;
    try {
      settled = await Future.wait(
          futures.entries.map((e) => guard(e.key, e.value))).timeout(
              const Duration(seconds: 30),
              onTimeout: () => <List<SearchResult>>[]);
    } on TimeoutException {
      throw Exception(
          'Поиск не уложился в 30 секунд. Проверьте интернет и повторите.');
    }
    final results = <SearchResult>[];
    for (final list in settled) {
      results.addAll(list);
    }
    if (results.isEmpty && failed.isNotEmpty) {
      throw Exception(
          'Не удалось найти книги: нет доступа к каталогам '
          '(${failed.join(', ')}). Проверьте интернет и повторите.');
    }
    // Уникальные по ссылке.
    final seen = <String>{};
    final unique = <SearchResult>[];
    for (final r in results) {
      if (r.downloadUrl != null && !seen.add(r.downloadUrl!)) continue;
      unique.add(r);
    }
    return unique.take(maxResults).toList();
  }

  Future<List<SearchResult>> _searchGutenberg(
      String query, int maxResults) async {
    final uri = Uri.https('gutendex.com', '/books',
        {'search': query, 'languages': 'ru,en,fr,de'});
    final resp =
        await http.get(uri, headers: _headers()).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = <SearchResult>[];
    for (final item in data['results'] as List<dynamic>? ?? []) {
      final map = item as Map<String, dynamic>;
      final title = map['title'] as String? ?? '';
      final authors = ((map['authors'] as List<dynamic>? ?? []).map((a) {
        final m = a as Map<String, dynamic>;
        return '${m['name'] ?? ''}'.replaceAll(';', ',');
      }).toList().join(', '));
      final formats = map['formats'] as Map<String, dynamic>? ?? {};
      String? url;
      String? mime;
      formats.forEach((k, v) {
        final kk = k.toLowerCase();
        if (kk.contains('epub') && kk.contains('images') && url == null) {
          url = v as String?;
          mime = 'epub';
        }
      });
      if (url == null) {
        formats.forEach((k, v) {
          if (k.toLowerCase().contains('epub') && url == null) {
            url = v as String?;
            mime = 'epub';
          }
        });
      }
      if (url == null) {
        formats.forEach((k, v) {
          if (k.toLowerCase().contains('pdf') && url == null) {
            url = v as String?;
            mime = 'pdf';
          }
        });
      }
      if (url == null) {
        formats.forEach((k, v) {
          if (k.toLowerCase().contains('plain') &&
              k.contains('charset') && url == null) {
            url = v as String?;
            mime = 'txt';
          }
        });
      }
      if (url == null) continue;
      final size = formats['application/octet-stream'] != null
          ? (formats['application/octet-stream'] as String? ?? '')
              .length
          : null;
      results.add(SearchResult(
        title: title,
        author: authors,
        coverUrl: formats['image/jpeg'] as String?,
        downloadUrl: url,
        source: 'Project Gutenberg',
        sizeBytes: size,
        format: mime == 'pdf' ? BookFormat.pdf : BookFormat.epub,
      ));
      if (results.length >= maxResults) break;
    }
    return results;
  }

  /// Поиск по Internet Archive (стабильный, без ключей). Выбираем только
  /// текстовые издания (mediatype:texts) и берём первый epub/pdf/txt-файл.
  Future<List<SearchResult>> _searchArchiveOrg(
      String query, int maxResults) async {
    final uri = Uri.https('archive.org', '/advancedsearch.php', {
      'q': '$query AND mediatype:texts',
      'fl[]': 'identifier,title,creator',
      'rows': '${maxResults.clamp(1, 12)}',
      'page': '1',
      'output': 'json',
    });
    final resp = await http.get(uri, headers: _headers()).timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final docs = (data['response'] as Map<String, dynamic>?)?['docs']
            as List<dynamic>? ??
        [];
    if (docs.isEmpty) return [];
    final metas = await Future.wait(docs.map((d) async {
      final m = d as Map<String, dynamic>;
      final id = (m['identifier'] as String? ?? '').trim();
      if (id.isEmpty) return <SearchResult>[];
      try {
        return await _archiveMetadata(id);
      } catch (_) {
        return <SearchResult>[];
      }
    }));
    return metas.expand((l) => l).take(maxResults).toList();
  }

  Future<List<SearchResult>> _archiveMetadata(String id) async {
    final resp = await http
        .get(Uri.https('archive.org', '/metadata/$id'), headers: _headers())
        .timeout(_timeout);
    if (resp.statusCode != 200) return [];
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final meta = data['metadata'] as Map<String, dynamic>? ?? {};
    final files = (data['files'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList();

    // Приоритет форматов: epub > fb2 > pdf > текст (djvu.txt).
    String? pick(String needle) {
      for (final f in files) {
        final name = (f['name'] as String? ?? '').toLowerCase();
        if (name.contains(needle)) return f['name'] as String?;
      }
      return null;
    }

    String? file;
    var fmt = BookFormat.epub;
    for (final pref in [('.epub', BookFormat.epub), ('.fb2', BookFormat.fb2)]) {
      file = pick(pref.$1);
      if (file != null) {
        fmt = pref.$2;
        break;
      }
    }
    file ??= pick('.pdf');
    if (file != null) fmt = BookFormat.pdf;
    if (file == null) return [];

    final title = (meta['title'] as String? ?? '').trim();
    if (title.isEmpty) return [];
    final creator = (meta['creator'] as String? ?? '');
    final author = creator.replaceAll(';', ',').trim();
    return [
      SearchResult(
        title: title,
        author: author,
        coverUrl: 'https://archive.org/services/img/$id',
        downloadUrl: 'https://archive.org/download/$id/$file',
        source: 'Archive.org',
        format: fmt,
      ),
    ];
  }

  Future<List<SearchResult>> _searchOpds(
      OpdsCatalog catalog, String query, int maxResults) async {
    if (maxResults <= 0) return [];
    String url;
    if (catalog.url.endsWith('.json')) {
      url = catalog.url;
    } else {
      url = catalog.url.contains('?')
          ? '${catalog.url}&q=$query'
          : '${catalog.url}?q=$query';
      if (catalog.url.toLowerCase().contains('search')) {
        url = _searchUrl(catalog.url, query);
      }
    }
    final body =
        await http.get(Uri.parse(url), headers: _headers()).timeout(_timeout);
    if (body.statusCode != 200) return [];
    final lower = url.toLowerCase();
    if (lower.endsWith('.json') || lower.contains('.json?')) {
      return _parseOpdsJson(body.body, catalog, maxResults);
    }
    return _parseOpdsXml(body.body, catalog, maxResults);
  }

  String _searchUrl(String base, String query) {
    final trimmed = query.replaceAll(' ', '%20');
    return base.replaceFirst(RegExp(r'\{searchTerms\}'), trimmed);
  }

  List<SearchResult> _parseOpdsXml(
      String body, OpdsCatalog catalog, int maxResults) {
    final doc = XmlDocument.parse(body);
    final entries = doc.findAllElements('entry');
    final results = <SearchResult>[];
    for (final entry in entries) {
      final title = entry
          .findAllElements('title')
          .map((e) => e.innerText.trim())
          .firstOrNull;
      if (title == null || title.isEmpty || title == 'Нет книг') continue;
      String? authorName;
      final author = entry.findAllElements('author').firstOrNull;
      if (author != null) {
        authorName = author
            .findAllElements('name')
            .map((e) => e.innerText.trim())
            .firstOrNull;
      }
      String? coverUrl;
      final cover = entry
          .findAllElements('link')
          .where((l) => (l.getAttribute('rel') ?? '') == 'http://opds-spec.org/image')
          .firstOrNull;
      if (cover != null) coverUrl = cover.getAttribute('href');
      if (coverUrl == null) {
        final t = entry
            .findAllElements('link')
            .where((l) => (l.getAttribute('type') ?? '').startsWith('image/'))
            .firstOrNull;
        if (t != null) coverUrl = t.getAttribute('href');
      }
      String? downloadUrl;
      final dl = entry
          .findAllElements('link')
          .where((l) => (l.getAttribute('rel') ?? '')
              .contains('http://opds-spec.org/acquisition'))
          .firstOrNull;
      if (dl != null) downloadUrl = dl.getAttribute('href');
      if (downloadUrl == null) {
        final al = entry
            .findAllElements('link')
            .where((l) => l.getAttribute('href') != null)
            .firstOrNull;
        if (al != null) downloadUrl = al.getAttribute('href');
      }
      if (downloadUrl == null) continue;
      final fmt = _formatFromUrl(downloadUrl);
      results.add(SearchResult(
        title: title,
        author: authorName ?? '',
        coverUrl: coverUrl,
        downloadUrl: _abs(catalog.url, downloadUrl),
        source: catalog.name,
        format: fmt,
      ));
      if (results.length >= maxResults) break;
    }
    return results;
  }

  List<SearchResult> _parseOpdsJson(
      String body, OpdsCatalog catalog, int maxResults) {
    final data = jsonDecode(body);
    List<dynamic> entries = <dynamic>[];
    if (data.containsKey('entries') || data is Map && data['catalog'] != null) {
      entries = data['entries'] as List<dynamic>? ?? [];
    } else if (data is List) {
      entries = data;
    }
    final results = <SearchResult>[];
    for (final e in entries) {
      if (e is! Map) continue;
      final title = (e['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final authorName = (e['author'] is Map
              ? (e['author'] as Map)['name'] ??
                  (e['author'] as Map)['uri'] ??
                  ''
              : e['author']) as String? ??
          '';
      String? downloadUrl;
      String? format = 'epub';
      final formats = e['formats'];
      if (formats is List) {
        for (final f in formats) {
          if (f is Map && f['url'] != null) {
            downloadUrl = f['url'] as String?;
            final type = (f['type'] as String? ?? '').toLowerCase();
            if (type.contains('pdf')) format = 'pdf';
          }
        }
      }
      if (downloadUrl == null) continue;
      final cover = e['cover'] is Map
          ? (e['cover'] as Map)['url']
          : e['cover'];
      results.add(SearchResult(
        title: title,
        author: authorName.toString().trim(),
        coverUrl: cover?.toString(),
        downloadUrl: _abs(catalog.url, downloadUrl),
        source: catalog.name,
        format: _formatFromUrl(downloadUrl, fallback: format!),
      ));
      if (results.length >= maxResults) break;
    }
    return results;
  }

  Future<List<SearchResult>> _searchBook2You(
      OpdsCatalog catalog, String query, int maxResults) async {
    if (maxResults <= 0) return [];
    final base =
        catalog.url.trim().isEmpty ? 'https://book2you.net' : catalog.url;
    final host = Uri.parse(base).host == ''
        ? 'book2you.net'
        : Uri.parse(base).host;
    final searchUrl = Uri(
      scheme: 'https',
      host: host,
      path: '/',
      queryParameters: {'s': query},
    ).toString();
    final page = await _getWithReferer(searchUrl, host);
    if (page.isEmpty) return [];

    // Собираем ссылки на посты книг (не навигация/категории).
    final postHrefs = <String>{};
    for (final m in RegExp(
            r'<a[^>]+href="(https?://' +
                RegExp.escape(host) +
                r'/[^"]+)"[^>]*>')
        .allMatches(page)) {
      final href = m.group(1)!;
      final lower = href.toLowerCase();
      final seg = Uri.parse(href).pathSegments;
      if (seg.isEmpty) continue;
      final slug = seg.last;
      if (slug.isEmpty ||
          slug == 'knigi' ||
          lower.contains('/wp-') ||
          lower.contains('/author/') ||
          lower.contains('/category') ||
          lower.contains('/knigi/') ||
          lower.contains('/bestsellery/') ||
          lower.contains('/avtor/') ||
          lower.contains('/kontakty/') ||
          lower.contains('?s=') ||
          lower == 'https://$host/') {
        continue;
      }
      if (postHrefs.length >= 12) break;
      postHrefs.add(href);
    }

    // Проверяем посты параллельно, но с ограничением одновременных запросов.
    final results = <SearchResult>[];
    final pending = postHrefs.toList();
    var readIndex = 0;
    Future<void> worker() async {
      while (true) {
        if (readIndex >= pending.length) return;
        if (results.length >= maxResults) return;
        final postUrl = pending[readIndex++];
        try {
          final postHtml = await _getWithReferer(postUrl, host);
          final fileUrl = _findBook2YouFile(postHtml);
          if (fileUrl != null && results.length < maxResults) {
            final title = _firstRegex(
                    postHtml,
                    RegExp(
                        r'<meta[^>]+property="og:title"[^>]+content="([^"]+)"')) ??
                _titleFromUrl(postUrl);
            final cover = _firstRegex(
                postHtml,
                RegExp(
                    r'<meta[^>]+property="og:image"[^>]+content="([^"]+)"'));
            results.add(SearchResult(
              title: title.trim(),
              author: '',
              coverUrl: cover,
              downloadUrl: fileUrl,
              source: 'Book2You',
              format: _formatFromUrl(fileUrl),
            ));
          }
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
    return results;
  }

  Future<String> _getWithReferer(String url, String host) async {
    final resp = await http
        .get(Uri.parse(url),
            headers: {'Referer': 'https://$host/', ..._headers()})
        .timeout(_timeout);
    if (resp.statusCode != 200) return '';
    return resp.body;
  }

  String? _findBook2YouFile(String html) {
    // Прямые ссылки на файлы в wp-content/uploads.
    final candidates = <String>[];
    for (final m in RegExp(
        r"""https?://[^"'\s<>]+?\.(pdf|epub|fb2|txt)(?!\.zip)(\?[^"'\s<>]*)?""")
        .allMatches(html)) {
      final u = m.group(0)!
          .replaceAll('&#038;', '&')
          .replaceAll('&amp;', '&');
      if (u.toLowerCase().contains('wp-content/uploads')) {
        candidates.add(u);
      }
    }
    if (candidates.isEmpty) return null;
    // Приоритет: epub, fb2, pdf, txt (текстовые форматы читаются удобнее).
    String? best;
    for (final ext in ['.epub', '.fb2', '.pdf', '.txt']) {
      best = candidates.where((c) => c.toLowerCase().contains(ext)).firstOrNull;
      if (best != null) break;
    }
    return best;
  }

  String? _firstRegex(String html, RegExp re) {
    final m = re.firstMatch(html);
    return m?.group(1);
  }

  String _titleFromUrl(String url) {
    final seg = Uri.parse(url).pathSegments;
    if (seg.isEmpty) return 'Книга';
    final last = seg.last;
    // "martin-iden-dzhek-london" → "Мартин Иден"
    var t = last.replaceAll('-', ' ');
    return t.isEmpty ? 'Книга' : t[0].toUpperCase() + t.substring(1);
  }

  String _abs(String base, String href) {
    if (href.startsWith('http')) return href;
    final uri = Uri.parse(base).resolve(href);
    return uri.toString();
  }

  BookFormat _formatFromUrl(String url, {String fallback = 'epub'}) {
    final lower = url.toLowerCase();
    if (lower.contains('.pdf') || lower.contains('format=pdf')) {
      return BookFormat.pdf;
    }
    if (lower.contains('.fb2')) return BookFormat.fb2;
    if (lower.contains('.epub')) return BookFormat.epub;
    return fallback.toLowerCase().contains('pdf')
        ? BookFormat.pdf
        : BookFormat.epub;
  }

  Future<File> download(SearchResult result, String destPath, {void Function(int, int)? onProgress}) async {
    final req = http.Request('GET', Uri.parse(result.downloadUrl!));
    req.headers.addAll(_headers());
    final streamed = await req.send().timeout(const Duration(seconds: 30));
    if (streamed.statusCode != 200) {
      throw Exception('HTTP ${streamed.statusCode}');
    }
    final total = streamed.contentLength ?? 0;
    final file = File(destPath);
    final sink = file.openWrite();
    var received = 0;
    await for (final chunk in streamed.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (onProgress != null && total > 0) {
        onProgress(received, total);
      }
    }
    await sink.close();
    if (onProgress != null) onProgress(received, total);
    return file;
  }
}

extension FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}