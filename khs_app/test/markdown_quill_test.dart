import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:khs/ui/widgets/markdown_quill.dart';

void main() {
  group('markdown -> quill -> markdown round-trip', () {
    String rt(String src) =>
        quillDocumentToMarkdown(markdownToQuillDocument(src));

    void show(String src) {
      final out = rt(src);
      debugPrint('SRC : $src\nSHA256? OUT: ${out.replaceAll('\n', r'\n')}');
    }

    test('жирный, курсив, зачёркнутый, код', () {
      show('**жирный** и _курсив_ и ~~зачёрк~~ и `внутри`');
      final out = rt('**жирный** и _курсив_ и ~~зачёрк~~ и `внутри`');
      expect(out, contains('**жирный**'));
      expect(out, contains('*курсив*'));
      expect(out, contains('~~зачёрк~~'));
      expect(out, contains('`внутри`'));
    });

    test('заголовки H1-H3', () {
      show('# Заголовок 1\n## Заголовок 2\n### Заголовок 3');
      final out = rt('# Заголовок 1\n## Заголовок 2\n### Заголовок 3');
      expect(out, contains('# Заголовок 1'));
      expect(out, contains('## Заголовок 2'));
      expect(out, contains('### Заголовок 3'));
    });

    test('списки, цитата и код-блок', () {
      const src = '- пункт\n- пункт 2\n\n1. раз\n2. два\n\n> цитата\n\n```dart\nvoid main() {}\n```';
      show(src);
      final out = rt(src);
      expect(out, contains('- пункт'));
      expect(out, contains('1. раз'));
      expect(out, contains('> цитата'));
      expect(out, contains('```dart'));
      expect(out, contains('void main() {}'));
      expect(out, contains('```'));
    });

    test('чек-боксы сохраняются', () {
      show('- [ ] задача\n- [x] сделано');
      final out = rt('- [ ] задача\n- [x] сделано');
      expect(out, contains('- [ ] задача'));
      expect(out, contains('- [x] сделано'));
    });

    test('пустой текст', () {
      expect(rt(''), '');
    });
  });
}