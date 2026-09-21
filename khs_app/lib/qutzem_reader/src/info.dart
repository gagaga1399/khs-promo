import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:epubx/epubx.dart';
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart';
import 'package:xml/xml.dart';

import 'models.dart';

class BookInfo {
  final String title;
  final String author;
  final Uint8List? coverBytes;

  BookInfo({required this.title, required this.author, this.coverBytes});
}

class InfoExtractor {
  static Future<BookInfo> of(String path, BookFormat format) async {
    switch (format) {
      case BookFormat.pdf:
        return _fromPdf(path);
      case BookFormat.epub:
        return _fromEpub(path);
      case BookFormat.fb2:
        return _fromFb2(path);
    }
  }

  static Future<BookInfo> _fromPdf(String path) async {
    var title = fileNameWithoutExt(path);
    var author = '';
    Uint8List? cover;
    try {
      final doc = await PdfDocument.openFile(path);
      final page = await doc.getPage(1);
      final pageImage = await page.render(
        width: 300,
        height: 430,
        format: PdfPageImageFormat.png,
      );
      cover = pageImage?.bytes;
      await page.close();
      await doc.close();
    } catch (_) {}
    return BookInfo(title: title, author: author, coverBytes: cover);
  }

  static Future<BookInfo> _fromEpub(String path) async {
    final bytes = File(path).readAsBytesSync();
    var title = fileNameWithoutExt(path);
    var author = '';
    try {
      final book = await EpubReader.openBook(bytes);
      if (book.Title != null && book.Title!.trim().isNotEmpty) {
        title = book.Title!.trim();
      }
      author = book.Author ?? '';
      img.Image? cover;
      try {
        final epub = await EpubReader.readBook(bytes);
        cover = epub.CoverImage;
      } catch (_) {}
      if (cover != null) {
        final pngBytes = Uint8List.fromList(img.encodePng(cover));
        return BookInfo(
            title: title, author: author, coverBytes: pngBytes);
      }
    } catch (_) {}
    return BookInfo(title: title, author: author, coverBytes: null);
  }

  static Future<BookInfo> _fromFb2(String path) async {
    var title = fileNameWithoutExt(path);
    var author = '';
    Uint8List? coverBytes;
    try {
      final doc = XmlDocument.parse(File(path).readAsStringSync());
      final description = doc.findAllElements('description').firstOrNull;
      if (description != null) {
        final t = description.findAllElements('book-title').firstOrNull;
        if (t != null && t.innerText.trim().isNotEmpty) {
          title = t.innerText.trim();
        }
        final f = description
            .findAllElements('first-name')
            .map((e) => e.innerText.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final l = description
            .findAllElements('last-name')
            .map((e) => e.innerText.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final parts = <String>[...f, ...l];
        if (parts.isNotEmpty) {
          author = parts.join(' ');
        }
      }
      final cover = doc.findAllElements('coverpage').firstOrNull;
      if (cover != null) {
        final image = cover.findAllElements('image').firstOrNull;
        final href = image?.getAttribute('l:href') ??
            image?.getAttribute('href') ??
            image?.getAttribute('{http://www.w3.org/1999/xlink}href');
        if (href != null && href.isNotEmpty) {
          final id = href.startsWith('#') ? href.substring(1) : href;
          final binary = doc.findAllElements('binary').firstWhere(
                (e) =>
                    e.getAttribute('id') == id ||
                    e.getAttribute('l:id') == id,
                orElse: () => XmlElement(XmlName('none'), [], []),
              );
          final raw = binary.innerText.trim();
          if (raw.isNotEmpty) {
            final data = raw.contains(',') ? raw.split(',').last : raw;
            try {
              coverBytes =
                  Uint8List.fromList(base64Decode(data).toList());
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return BookInfo(title: title, author: author, coverBytes: coverBytes);
  }

  static String fileNameWithoutExt(String path) {
    final segments = File(path).uri.pathSegments;
    final name = segments.isNotEmpty ? segments.last : path;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }
}