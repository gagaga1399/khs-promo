import 'package:flutter/material.dart';

import '../text_document.dart';
import 'spread_paginator.dart';
import 'theme_data.dart';

/// Одна запись оглавления — заголовок/глава в потоке.
class TocEntry {
  final int block;
  final String title;
  final ReaderBlock? source;
  const TocEntry({required this.block, required this.title, this.source});
}

/// Сборка списка оглавления из заголовков потока.
List<TocEntry> buildTocEntries(List<ReaderBlock> blocks, TextDocument doc) {
  final entries = <TocEntry>[];
  for (var i = 0; i < blocks.length; i++) {
    final b = blocks[i];
    if (b.isHeading) {
      entries.add(TocEntry(block: i, title: b.text, source: b));
    }
  }
  if (entries.isNotEmpty) return entries;
  // Fallback: по одной записи на исходную главу.
  final seen = <int>{};
  for (var i = 0; i < blocks.length; i++) {
    final ch = blocks[i].sourceChapter;
    if (seen.add(ch)) {
      final title = ch < doc.chapters.length
          ? doc.chapters[ch].title
          : 'Глава ${ch + 1}';
      final t = title.trim();
      entries.add(TocEntry(
          block: i, title: t.isNotEmpty ? t : 'Глава ${ch + 1}', source: blocks[i]));
    }
  }
  return entries;
}

/// Показ оглавления как bottom sheet (mobile) с фильтром и навигацией.
Future<void> showTocSheet(
  BuildContext context,
  List<ReaderBlock> blocks,
  TextDocument doc,
  ReaderColors colors,
  int currentBlock,
  void Function(int block) onJump,
) async {
  final entries = buildTocEntries(blocks, doc);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.ui,
    builder: (ctx) {
      return _TocSheet(
        entries: entries,
        currentBlock: currentBlock,
        colors: colors,
        onJump: onJump,
      );
    },
  );
}

class _TocSheet extends StatefulWidget {
  final List<TocEntry> entries;
  final int currentBlock;
  final ReaderColors colors;
  final void Function(int block) onJump;

  const _TocSheet({
    required this.entries,
    required this.currentBlock,
    required this.colors,
    required this.onJump,
  });

  @override
  State<_TocSheet> createState() => _TocSheetState();
}

class _TocSheetState extends State<_TocSheet> {
  String _filter = '';

  List<TocEntry> get _visible {
    if (_filter.isEmpty) return widget.entries;
    final q = _filter.toLowerCase();
    return widget.entries
        .where((e) => e.title.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = _visible;
    return SafeArea(
      child: Column(
        children: [
          if (widget.entries.length > 12)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                autofocus: false,
                style: TextStyle(color: widget.colors.text),
                decoration: InputDecoration(
                  hintText: 'Фильтр',
                  hintStyle: TextStyle(color: widget.colors.muted),
                  prefixIcon: Icon(Icons.search, color: widget.colors.muted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: widget.colors.border),
                  ),
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            )
          else
            const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Оглавление',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: widget.colors.text)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (ctx, i) {
                final e = list[i];
                final selected = e.block == widget.currentBlock;
                return ListTile(
                  dense: true,
                  title: Text(e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: selected
                              ? widget.colors.accent
                              : widget.colors.text)),
                  selected: selected,
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onJump(e.block);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
