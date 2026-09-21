import 'package:flutter/material.dart';

import 'reader_screen.dart';
import 'spread_paginator.dart';
import 'theme_data.dart';

/// Одно совпадение в потоке абзацев.
class SearchMatch {
  final int blockIndex;
  final String chapterTitle;
  final String context;
  final int matchStart;
  final int matchEnd;

  const SearchMatch({
    required this.blockIndex,
    required this.chapterTitle,
    required this.context,
    required this.matchStart,
    required this.matchEnd,
  });
}

/// Полнотекстовый поиск по всему потоку абзацев книги.
List<SearchMatch> searchBlocks(
  List<ReaderBlock> blocks,
  List<String> titles,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  final results = <SearchMatch>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    final lower = b.text.toLowerCase();
    int from = 0;
    while (true) {
      final idx = lower.indexOf(q, from);
      if (idx < 0) break;
      final start = (idx - 40).clamp(0, b.text.length);
      final end = (idx + q.length + 60).clamp(0, b.text.length);
      final title = (b.sourceChapter >= 0 && b.sourceChapter < titles.length)
          ? (titles[b.sourceChapter].trim().isNotEmpty
              ? titles[b.sourceChapter].trim()
              : 'Глава ${b.sourceChapter + 1}')
          : 'Стр. ${b.sourceChapter + 1}';
      results.add(SearchMatch(
        blockIndex: i,
        chapterTitle: title,
        context: b.text.substring(start, end),
        matchStart: idx - start,
        matchEnd: idx - start + q.length,
      ));
      from = idx + q.length;
      if (results.length >= 500) return results;
    }
  }
  return results;
}

/// Панель поиска по книге (bottom sheet).
Future<void> showBookSearchSheet(
  BuildContext context,
  List<ReaderBlock> blocks,
  List<String> chapterTitles,
  ReaderColors colors,
  void Function(int blockIndex) onJump,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: colors.ui,
    builder: (ctx) => _BookSearchSheet(
      blocks: blocks,
      chapterTitles: chapterTitles,
      colors: colors,
      onJump: onJump,
    ),
  );
}

class _BookSearchSheet extends StatefulWidget {
  final List<ReaderBlock> blocks;
  final List<String> chapterTitles;
  final ReaderColors colors;
  final void Function(int blockIndex) onJump;

  const _BookSearchSheet({
    required this.blocks,
    required this.chapterTitles,
    required this.colors,
    required this.onJump,
  });

  @override
  State<_BookSearchSheet> createState() => _BookSearchSheetState();
}

class _BookSearchSheetState extends State<_BookSearchSheet> {
  final _ctrl = TextEditingController();
  List<SearchMatch> _results = const [];
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _search(String q) {
    setState(() {
      _searched = true;
      _results = searchBlocks(widget.blocks, widget.chapterTitles, q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.85,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: TextStyle(color: colors.text),
                decoration: InputDecoration(
                  hintText: 'Поиск по книге…',
                  hintStyle: TextStyle(color: colors.muted),
                  prefixIcon: Icon(Icons.search, color: colors.muted),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          color: colors.muted,
                          onPressed: () {
                            _ctrl.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: colors.border),
                  ),
                ),
                onChanged: _search,
                onSubmitted: _search,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                _results.isEmpty && _searched
                    ? 'Ничего не найдено'
                    : (_searched
                        ? 'Найдено: ${_results.length}'
                        : 'Введите текст для поиска'),
                style: TextStyle(color: colors.muted, fontSize: 13),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final m = _results[i];
                  return ListTile(
                    dense: true,
                    title: Text(
                      m.chapterTitle,
                      style: TextStyle(
                          color: colors.accent, fontWeight: FontWeight.w600),
                    ),
                    subtitle: _HighlightedContext(
                      text: m.context,
                      matchStart: m.matchStart,
                      matchEnd: m.matchEnd,
                      colors: colors,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onJump(m.blockIndex);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightedContext extends StatelessWidget {
  final String text;
  final int matchStart;
  final int matchEnd;
  final ReaderColors colors;

  const _HighlightedContext({
    required this.text,
    required this.matchStart,
    required this.matchEnd,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final spans = <TextSpan>[];
    final start = matchStart.clamp(0, text.length);
    final end = matchEnd.clamp(start, text.length);
    if (start > 0) spans.add(TextSpan(text: '…${text.substring(0, start)}'));
    if (end > start) {
      spans.add(TextSpan(
        text: text.substring(start, end),
        style: TextStyle(
          backgroundColor: highlightColors.first,
          color: Colors.black,
        ),
      ));
    }
    if (end < text.length) spans.add(TextSpan(text: '${text.substring(end)}…'));
    return Text.rich(
      TextSpan(
        style: TextStyle(color: colors.text, fontSize: 13),
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}
