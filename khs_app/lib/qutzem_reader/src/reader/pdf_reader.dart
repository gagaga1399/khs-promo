import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';

import '../ai.dart';
import '../library.dart';
import '../models.dart';
import 'reader_screen.dart';

class PdfReaderWidget extends StatefulWidget {
  final String path;
  final Book book;
  final Library library;
  final AiSettings aiSettings;
  final int initialPage;

  const PdfReaderWidget({
    super.key,
    required this.path,
    required this.book,
    required this.library,
    required this.aiSettings,
    required this.initialPage,
  });

  @override
  State<PdfReaderWidget> createState() => _PdfReaderWidgetState();
}

class _PdfReaderWidgetState extends State<PdfReaderWidget> {
  final bool _isWindows = Platform.isWindows;
  PdfControllerPinch? _pinchController;
  PdfController? _simpleController;
  int _page = 1;
  int _pages = 0;
  Timer? _saveTimer;

  static const double _minZoom = 0.25;
  static const double _maxZoom = 8.0;
  static const double _zoomStep = 1.25;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage;
    if (_isWindows) {
      _simpleController = PdfController(
        document: PdfDocument.openFile(widget.path),
        initialPage: _page,
      );
    } else {
      _pinchController = PdfControllerPinch(
        document: PdfDocument.openFile(widget.path),
        initialPage: _page,
      )..addListener(_onPinchChanged);
    }
  }

  ReaderService get _service => ReaderService(
      library: widget.library,
      book: widget.book,
      aiSettings: widget.aiSettings);

  @override
  void dispose() {
    _saveTimer?.cancel();
    _pinchController?.removeListener(_onPinchChanged);
    _pinchController?.dispose();
    _simpleController?.dispose();
    super.dispose();
  }

  void _onPinchChanged() {
    if (mounted) setState(() {});
  }

  void _onPageChanged(int page) {
    setState(() => _page = page);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _service.savePosition(page, 0, _pages > 0 ? _pages : page);
    });
  }

  void _onLoaded(PdfDocument doc) {
    setState(() => _pages = doc.pagesCount);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.book.title} · $_page/${max(1, _pages)}',
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Закладки',
            onPressed: _showBookmarks,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '$_page / ${max(1, _pages)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  void _addBookmark() {
    _service.addBookmark(chapter: _page, offset: 0, label: 'Стр. $_page');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Закладка добавлена'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _showBookmarks() {
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
                        'Пока нет закладок.\nНажмите «Добавить», чтобы отметить страницу.',
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
                            leading:
                                const Icon(Icons.bookmark, color: Colors.amber),
                            title: Text(
                              b.label.isNotEmpty ? b.label : 'Стр. ${b.chapter}',
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
                              _goToPage(b.chapter);
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

  Future<void> _goToPage(int page) async {
    final p = page.clamp(1, max(1, _pages));
    setState(() => _page = p);
    try {
      if (_isWindows) {
        await _simpleController?.animateToPage(
          p,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        await _pinchController?.animateToPage(
          pageNumber: p,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (_) {}
    _service.savePosition(p, 0, _pages > 0 ? _pages : p);
  }

  String _fmtTs(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return '${t.day}.${t.month}.${t.year}';
  }

  Widget _buildBody() {
    if (_isWindows) {
      final controller = _simpleController;
      if (controller == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return PdfView(
        controller: controller,
        scrollDirection: Axis.vertical,
        backgroundDecoration: const BoxDecoration(color: Color(0xFFF5F5F5)),
        onPageChanged: _onPageChanged,
        onDocumentLoaded: _onLoaded,
        onDocumentError: (e) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Ошибка PDF: $e')));
          });
        },
      );
    }
    final controller = _pinchController;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Positioned.fill(
          child: PdfViewPinch(
            controller: controller,
            onPageChanged: _onPageChanged,
            onDocumentLoaded: _onLoaded,
            onDocumentError: (e) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ошибка PDF: $e')));
              });
            },
          ),
        ),
        _buildControlBar(),
      ],
    );
  }

  Widget _buildControlBar() {
    final canPrev = _page > 1;
    final canNext = _page < max(1, _pages);
    final zoom = _pinchController?.zoomRatio ?? 1.0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          color: Colors.black.withValues(alpha: 0.72),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: Colors.white,
                tooltip: 'Предыдущая страница',
                onPressed: canPrev ? () => _goToPageClamped(_page - 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.zoom_out),
                color: Colors.white,
                tooltip: 'Уменьшить',
                onPressed: () => _zoom(1 / _zoomStep),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$_page / ${max(1, _pages)}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12),
                  ),
                  Text(
                    '${(zoom * 100).round()}%',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.zoom_in),
                color: Colors.white,
                tooltip: 'Увеличить',
                onPressed: () => _zoom(_zoomStep),
              ),
              IconButton(
                icon: const Icon(Icons.fit_screen),
                color: Colors.white,
                tooltip: 'Страница по ширине',
                onPressed: _canZoom
                    ? () => _goToPageClamped(_page)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: Colors.white,
                tooltip: 'Следующая страница',
                onPressed: canNext ? () => _goToPageClamped(_page + 1) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canZoom => _pinchController != null && _pages > 0;

  Future<void> _zoom(double factor) async {
    final controller = _pinchController;
    if (controller == null || _pages <= 0) return;
    try {
      final current = controller.zoomRatio;
      if (current <= 0.001) return;
      final target = (current * factor).clamp(_minZoom, _maxZoom);
      if (target == current) return;
      final size = MediaQuery.sizeOf(context);
      final center = Offset(size.width / 2, size.height / 2);
      final m = _scaleAround(controller.value, target / current, center);
      await controller.goTo(
        destination: m,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    } catch (_) {}
  }

  Matrix4 _scaleAround(Matrix4 base, double factor, Offset center) {
    final tr = Matrix4.identity();
    tr.translateByDouble(center.dx, center.dy, 0.0, 1.0);
    final sc = Matrix4.diagonal3Values(factor, factor, 1);
    final tb = Matrix4.identity();
    tb.translateByDouble(-center.dx, -center.dy, 0.0, 1.0);
    return tr.multiplied(sc.multiplied(tb)).multiplied(base);
  }

  Future<void> _goToPageClamped(int page) async {
    final p = page.clamp(1, max(1, _pages));
    final controller = _pinchController;
    if (controller == null) return;
    try {
      await controller.animateToPage(
        pageNumber: p,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } catch (_) {}
  }
}

int max(int a, int b) => a > b ? a : b;