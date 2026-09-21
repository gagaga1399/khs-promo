import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:xml/xml.dart';

import 'pdf_text.dart';

class TextChapter {
  String title;
  String text;

  TextChapter({this.title = '', this.text = ''});
}

class TextDocument {
  final List<TextChapter> chapters;

  TextDocument({required this.chapters});

  int get totalChars =>
      chapters.fold(0, (sum, c) => sum + c.text.length);

  static Future<TextDocument> fromEpubFile(String path) async {
    final bytes = File(path).readAsBytesSync();
    final book = await EpubReader.readBook(bytes);
    final chapters = <TextChapter>[];
    if (book.Chapters != null) {
      for (final ch in book.Chapters!) {
        final html = ch.HtmlContent ?? '';
        chapters.add(TextChapter(
          title: _cleanChapterTitle(ch.Title ?? ''),
          text: _htmlToText(html),
        ));
      }
    }
    if (chapters.isEmpty) {
      final content = book.Content;
      if (content?.Html != null) {
        final htmls = content!.Html!.values.toList()
          ..sort((a, b) => (a.FileName ?? '')
              .compareTo(b.FileName ?? ''));
        for (final h in htmls) {
          chapters.add(TextChapter(text: _htmlToText(h.Content ?? '')));
        }
      }
    }
    return TextDocument(chapters: chapters);
  }

  static Future<TextDocument?> fromPdfFile(String path) async {
    return PdfTextExtractor.tryExtract(path);
  }

  static TextDocument fromFb2File(String path) {
    final doc = XmlDocument.parse(File(path).readAsStringSync());
    final chapters = <TextChapter>[];
    for (final section in doc.findAllElements('section')) {
      final texts = <String>[];
      for (final node in section.descendants) {
        if (node is XmlElement) {
          final name = node.name.local.toLowerCase();
          if (name == 'title') {
            final t = node.innerText.trim();
            if (t.isNotEmpty) {
              texts.add(t);
            }
          } else if (name == 'p' || name == 'poem' || name == 'subtitle') {
            final t = node.innerText.trim();
            if (t.isNotEmpty) {
              texts.add(t);
            }
          }
        }
      }
      if (texts.isNotEmpty) {
        final title = texts.first;
        final body = texts.skip(1).join('\n\n');
        chapters.add(TextChapter(title: title, text: body));
      }
    }
    if (chapters.isEmpty) {
      final body = doc.findAllElements('body').toList().asMap().entries;
      for (final e in body) {
        final nodes = e.value.descendants.whereType<XmlElement>().where((n) {
          final name = n.name.local.toLowerCase();
          return name == 'p' || name == 'title' || name == 'subtitle';
        });
        final text = nodes.map((n) => n.innerText.trim()).where((t) {
          return t.isNotEmpty;
        }).join('\n\n');
        if (text.isNotEmpty) {
          chapters.add(TextChapter(
            title: 'Глава ${e.key + 1}',
            text: text,
          ));
        }
      }
    }
    return TextDocument(chapters: chapters);
  }
}

String _cleanChapterTitle(String raw) {
  var t = raw.trim();
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ');
  return t;
}

String _htmlToText(String html) {
  final buffer = StringBuffer();
  var text = html.replaceAll(RegExp(r'<script\b[^>]*>[\s\S]*?</script>'), '');
  text = text.replaceAll(RegExp(r'<style\b[^>]*>[\s\S]*?</style>'), '');
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</(p|div|h[1-6]|li|tr)>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<(p|div|h[1-6]|li|td)\b[^>]*>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>'), '');
  text = text.replaceAll('&nbsp;', ' ');
  text = text.replaceAll('&amp;', '&');
  text = text.replaceAll('&lt;', '<');
  text = text.replaceAll('&gt;', '>');
  text = text.replaceAll('&quot;', '"');
  text = text.replaceAll('&#39;', "'");
  text = text.replaceAll(r'\u00a0', ' ');
  final lines = text
      .split('\n')
      .map((l) => l.trim())
      .where((l) {
        l = l.replaceAll(RegExp(r'\s+'), ' ');
        return l.isNotEmpty;
      })
      .map((l) => l.replaceAll(RegExp(r'\s+'), ' '));
  buffer.write(lines.join('\n\n'));
  return buffer.toString();
}