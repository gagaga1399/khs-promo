import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

const _kChecked = 'checked';
const _kUnchecked = 'unchecked';
const _kBlockKeys = {'header', 'blockquote', 'list', 'code-block', 'indent'};

// ────────────────────────── markdown → delta ──────────────────────────

/// Переводит markdown в документ Quill.
Document markdownToQuillDocument(String source) {
  final s = source.trimRight();
  if (s.isEmpty) {
    return Document();
  }
  final nodes = md.Document().parse(s);
  final delta = Delta();
  for (final node in nodes) {
    _emitBlock(node, delta);
  }
  _ensureTrailingNewline(delta);
  return Document.fromDelta(delta);
}

void _emitBlock(md.Node node, Delta delta) {
  if (node is! md.Element) {
    if (node is md.Text && node.text.trim().isNotEmpty) {
      _emitInline(node.text, delta, null);
      delta.insert('\n');
    }
    return;
  }
  final tag = node.tag;
  if (tag == 'h1' || tag == 'h2' || tag == 'h3') {
    final level = int.parse(tag[1]);
    for (final run in _flattenParagraphs(node)) {
      delta.insert(run.text, run.attrs);
    }
    delta.insert('\n', {'header': level});
    return;
  }
  if (tag == 'ul' || tag == 'ol') {
    for (final li in node.children ?? const []) {
      if (li is! md.Element) continue;
      var runs = _flattenParagraphs(li);
      final raw = _rawText(node: li).trim().toLowerCase();
      final String? flag;
      if (tag == 'ul' && raw.startsWith('[ ] ')) {
        flag = _kUnchecked;
      } else if (tag == 'ul' && raw.startsWith('[x] ')) {
        flag = _kChecked;
      } else {
        flag = null;
      }
      if (flag != null) {
        final first = runs.first;
        runs[0] = _Run(
          first.text.length >= 4 ? first.text.substring(4) : first.text,
          first.attrs,
        );
      }
      for (final run in runs) {
        _emitInline(run.text, delta, run.attrs);
      }
      delta.insert('\n', {
        'list': flag ?? (tag == 'ol' ? 'ordered' : 'bullet'),
      });
    }
    return;
  }
  if (tag == 'blockquote') {
    for (final child in node.children ?? const []) {
      if (child is! md.Element) continue;
      final runs = _flattenParagraphs(child);
      for (final run in runs) {
        _emitInline(run.text, delta, run.attrs);
      }
      delta.insert('\n', {'blockquote': true});
    }
    return;
  }
  if (tag == 'pre') {
    final lang = _codeLang(node);
    for (final child in node.children ?? const []) {
      if (child is md.Element && child.tag == 'code') {
        final lines = child.textContent.split('\n');
        for (var i = 0; i < lines.length; i++) {
          delta.insert(lines[i]);
          delta.insert('\n', {'code-block': lang});
        }
      }
    }
    return;
  }
  // paragraph / unknown → plain
  final runs = _flattenParagraphs(node);
  if (runs.isEmpty) {
    final t = _rawText(node: node);
    if (t.trim().isNotEmpty) delta.insert(t);
    delta.insert('\n');
    return;
  }
  for (final run in runs) {
    _emitInline(run.text, delta, run.attrs);
  }
  delta.insert('\n');
}

void _emitInline(String text, Delta delta, Map<String, dynamic>? attrs) {
  delta.insert(text, attrs);
}

String _rawText({required md.Node node}) {
  return node.textContent;
}

String? _codeLang(md.Element node) {
  for (final child in node.children ?? const []) {
    if (child is md.Element && child.tag == 'code') {
      final cls = child.attributes['class'] ?? '';
      if (cls.startsWith('language-')) {
        return cls.substring(9);
      }
    }
  }
  return null;
}

List<_Run> _flattenParagraphs(md.Element node) {
  final result = <_Run>[];
  if (node.children == null || node.children!.isEmpty) {
    result.add(_Run(node.textContent, const {}));
    return result;
  }
  for (final child in node.children!) {
    _collectRuns(child, [], result);
  }
  return result;
}

void _collectRuns(
  md.Node node,
  List<md.Element> stack,
  List<_Run> out,
) {
  if (node is md.Text) {
    out.add(_Run(node.text, _stackAttrs(stack)));
  } else if (node is md.Element) {
    stack.add(node);
    for (final child in node.children ?? const []) {
      _collectRuns(child, stack, out);
    }
    stack.removeLast();
  }
}

Map<String, dynamic> _stackAttrs(List<md.Element> stack) {
  final attrs = <String, dynamic>{};
  for (final el in stack) {
    switch (el.tag) {
      case 'strong':
        attrs['bold'] = true;
      case 'em':
        attrs['italic'] = true;
      case 'del':
        attrs['strike'] = true;
      case 'code':
        attrs['code'] = true;
      case 'a':
        final href = el.attributes['href'];
        if (href != null) attrs['link'] = href;
    }
  }
  return attrs;
}

void _ensureTrailingNewline(Delta delta) {
  if (delta.isEmpty) {
    delta.insert('\n');
    return;
  }
  final last = delta.last;
  if (last.isInsert && last.data is String && (last.data as String).endsWith('\n')) {
    return;
  }
  delta.insert('\n');
}

// ────────────────────────── delta → markdown ──────────────────────────

String quillDocumentToMarkdown(Document document) {
  return _deltaToMarkdown(document.toDelta());
}

class _Run {
  _Run(this.text, this.attrs);
  final String text;
  final Map<String, dynamic> attrs;
}

String _deltaToMarkdown(Delta delta) {
  final lines = <List<_Run>>[];
  var current = <_Run>[];
  final lineBlocks = <Map<String, dynamic>>[];

  void closeLine(Map<String, dynamic> block) {
    lines.add(List.of(current));
    lineBlocks.add(block);
    current = <_Run>[];
  }

  for (final op in delta.toList()) {
    if (!op.isInsert || op.data is! String) continue;
    final attrs = op.attributes ?? const <String, dynamic>{};
    final inline = <String, dynamic>{
      for (final e in attrs.entries)
        if (e.value != null && !_kBlockKeys.contains(e.key)) e.key: e.value,
    };
    final block = <String, dynamic>{
      for (final e in attrs.entries)
        if (e.value != null && _kBlockKeys.contains(e.key)) e.key: e.value,
    };
    final parts = (op.data as String).split('\n');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) closeLine(block);
      if (parts[i].isEmpty) continue;
      final last = current.isEmpty ? null : current.last;
      if (last != null && _sameAttrs(last.attrs, inline)) {
        current.last = _Run(last.text + parts[i], last.attrs);
      } else {
        current.add(_Run(parts[i], inline));
      }
    }
  }
  closeLine(const <String, dynamic>{});
  return _render(lines, lineBlocks);
}

bool _sameAttrs(Map<String, dynamic> a, Map<String, dynamic> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}

String _render(List<List<_Run>> lines, List<Map<String, dynamic>> blocks) {
  final buf = StringBuffer();
  String? prev;
  var inCode = false;

  for (var i = 0; i < lines.length; i++) {
    final block = blocks[i];
    final type = _typeOf(block);
    final text = _renderLine(lines[i], block);

    if (type == 'code') {
      if (!inCode) {
        final lang = block['code-block'];
        buf.writeln('```${lang == true ? '' : lang}');
        inCode = true;
      }
      var content = _plainText(lines[i]);
      if (content.endsWith('\n')) content = content.substring(0, content.length - 1);
      buf.writeln(content);
      prev = 'code';
      continue;
    }
    if (inCode) {
      buf.writeln('```');
      inCode = false;
      prev = 'code';
    }

    if (text.trim().isEmpty) {
      if (i < lines.length - 1) {
        buf.writeln();
        prev = null;
      }
      continue;
    }
    if (_needsBlank(prev, type)) {
      buf.writeln();
    }
    buf.writeln(text);
    prev = type;
  }
  if (inCode) buf.writeln('```');

  var result = buf.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n');
  result = result.replaceFirst(RegExp(r'^\n'), '');
  result = result.trimRight();
  if (result.isNotEmpty) result += '\n';
  return result;
}

String? _typeOf(Map<String, dynamic> block) {
  if (block.containsKey('list')) return 'list:${block['list']}';
  if (block.containsKey('code-block')) return 'code';
  if (block.containsKey('blockquote')) return 'quote';
  if (block.containsKey('header')) return 'header';
  return 'para';
}

bool _needsBlank(String? prev, String? current) {
  if (prev == null || prev == 'code') return true;
  final cur = current ?? 'para';
  if (prev == 'para') return cur != 'header';
  if (prev == 'quote') return cur != 'quote';
  if (prev == 'header') return cur == 'para';
  if (prev.startsWith('list:')) return prev != cur;
  return false;
}

String _plainText(List<_Run> runs) => runs.map((r) => r.text).join();

String _renderLine(List<_Run> runs, Map<String, dynamic> block) {
  final inline = runs.map(_renderRun).join();
  if (block.containsKey('header')) {
    final n = _parseInt(block['header']);
    final hashes = '#' * (n < 1 ? 1 : n > 6 ? 6 : n);
    return '$hashes $inline';
  }
  if (block.containsKey('blockquote')) return '> $inline';
  final list = block['list'];
  if (list != null) {
    return switch (list) {
      'ordered' => '1. $inline',
      'checked' => '- [x] $inline',
      'unchecked' => '- [ ] $inline',
      _ => '- $inline',
    };
  }
  return inline;
}

int _parseInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 1;
}

String _renderRun(_Run run) {
  var text = run.text;
  final attrs = run.attrs;
  if (attrs['code'] == true) {
    return '`${text.replaceAll('`', r'\`')}`';
  }
  if (attrs['bold'] == true) text = '**$text**';
  if (attrs['italic'] == true) text = '*$text*';
  if (attrs['strike'] == true) text = '~~$text~~';
  final link = attrs['link'];
  if (link is String && link.isNotEmpty) text = '[$text]($link)';
  return text;
}