import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'theme_data.dart';

// ignore_for_file: prefer_initializing_formals

/// Структура абзаца в потоке чтения.
class ReaderBlock {
  final String text;
  final int sourceChapter;
  final bool isHeading;
  final bool isPageBreak;

  /// Смещение [text] внутри текста исходной главы.
  final int startChar;
  final int endChar;

  const ReaderBlock({
    required this.text,
    required this.sourceChapter,
    this.isHeading = false,
    this.isPageBreak = false,
    this.startChar = 0,
    this.endChar = 0,
  });

  ParagraphStyle get style =>
      ParagraphStyle(isHeading: isHeading, isPageBreak: isPageBreak);
}

/// Одна страница (экран) — диапазон блоков глобального потока.
class PageLayout {
  final int startBlock;
  final int endBlock;
  final int pageNo;

  const PageLayout({
    required this.startBlock,
    required this.endBlock,
    required this.pageNo,
  });

  bool get isEmpty => startBlock >= endBlock;
  int get length => endBlock - startBlock;
}

/// Движок разбиения потока на страницы.
///
/// Меряет высоту каждого абзаца (TextPainter) и «набивает» страницы.
/// Измерение выполняется [build] — асинхронно, пачками между кадрами,
/// чтобы не блокировать UI на больших книгах. До завершения [build]
/// [pages] возвращает пустой список, а [isReady] равен false.
class SpreadPaginator {
  final List<ReaderBlock> blocks;
  final double fontSize;
  final double lineHeight;
  final TextScaler textScaler;
  double _pageHeight;
  double _columnWidth;
  final int columns;

  bool _built = false;
  List<PageLayout>? _pages;
  final List<double> _heights = [];
  bool _building = false;
  int _measured = 0;

  double get pageHeight => _pageHeight;
  set pageHeight(double v) {
    if ((v - _pageHeight).abs() > 0.5) {
      _pageHeight = v;
      _invalidate();
    }
  }

  double get columnWidth => _columnWidth;
  set columnWidth(double v) {
    if ((v - _columnWidth).abs() > 0.5) {
      _columnWidth = v;
      _invalidate();
    }
  }

  double get columnPageHeight => _pageHeight / columns;

  /// Готов ли движок отдавать страницы.
  bool get isReady => _built;

  void _invalidate() {
    _built = false;
    _pages = null;
    _heights.clear();
  }

  SpreadPaginator({
    required this.blocks,
    required this.fontSize,
    required this.lineHeight,
    required double pageHeight,
    required double columnWidth,
    this.columns = 1,
    this.textScaler = TextScaler.noScaling,
  })  : _pageHeight = pageHeight,
        _columnWidth = columnWidth;

  TextPainter _measure(String text) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, height: lineHeight),
      ),
      textDirection: ui.TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: (_columnWidth - 8).clamp(40.0, 1 << 20).toDouble());
  }

  double _styleHeight(ReaderBlock b) {
    if (b.isPageBreak) return 24;
    if (b.isHeading) return _measure(b.text).height + 12;
    return _measure(b.text).height + 10;
  }

  /// Совет: сколько блоков уже измерено (для прогресса).
  double get progress => _heights.isEmpty
      ? 0
      : (_measured / blocks.length).clamp(0.0, 1.0);

  /// Асинхронное измерение высот + построение страниц.
  ///
  /// Измеряет пачками по [batch] блоков, отдавая управление между кадрами,
  /// чтобы UI не «зависал» на больших книгах. [onProgress] вызывается между
  /// пачками с долей 0..1.
  Future<void> build({
    int batch = 30,
    bool Function()? isCancelled,
    void Function(double p)? onProgress,
  }) async {
    if (_built) return;
    if (_building) {
      while (_building) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return;
    }
    _building = true;
    _heights
      ..clear()
      ..addAll(List<double>.filled(blocks.length, 0));
    _measured = 0;
    try {
      for (var i = 0; i < blocks.length; i++) {
        if (isCancelled?.call() ?? false) {
          onProgress?.call(1.0);
          return;
        }
        final b = blocks[i];
        _heights[i] = b.isPageBreak ? 24 : _styleHeight(b);
        _measured = i + 1;
        if (i > 0 && (i % batch) == 0) {
          onProgress?.call(i / blocks.length);
          // Отдаём управление, чтобы кадр успел отрисоваться и UI не висел.
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      _pages = _buildPages();
      _built = true;
      onProgress?.call(1.0);
    } finally {
      _building = false;
    }
  }

  List<PageLayout> _buildPages() {
    final result = <PageLayout>[];
    var pageNo = 0;
    var i = 0;
    while (i < blocks.length) {
      var used = 0.0;
      final start = i;
      while (i < blocks.length) {
        final h = _heights[i];
        // Не отрываем заголовок в конец страницы.
        if (used > 0 && blocks[i].isHeading && used + h > columnPageHeight * 0.9) {
          break;
        }
        if (used + h > columnPageHeight) {
          if (used == 0) i++; // блок выше страницы — кладём обрезанным
          break;
        }
        used += h;
        i++;
      }
      result.add(PageLayout(startBlock: start, endBlock: i, pageNo: pageNo));
      pageNo++;
    }
    return result;
  }

  List<PageLayout> get pages =>
      _built ? (_pages ?? const []) : const [];

  int get pageCount => pages.length;

  /// По какому индексу блока лежит этот блок.
  int spreadForBlock(int blockIndex) {
    final p = pages;
    if (p.isEmpty) return 0;
    for (var i = 0; i < p.length; i++) {
      if (blockIndex >= p[i].startBlock && blockIndex < p[i].endBlock) {
        return i;
      }
    }
    return (p.length - 1).clamp(0, p.length - 1);
  }

  /// Глобальный индекс блока в начале страницы [pageNo].
  int blockForSpread(int pageNo) {
    final p = pages;
    if (pageNo < 0 || pageNo >= p.length) return 0;
    return p[pageNo].startBlock;
  }

  /// Доля прогресса (0..1) по индексу блока.
  double progressForBlock(int blockIndex) {
    final p = pages;
    if (p.isEmpty) return 0;
    final s = spreadForBlock(blockIndex);
    return (s / (p.length - 1)).clamp(0.0, 1.0);
  }
}

