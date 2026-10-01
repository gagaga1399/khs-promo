import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/qutzem_reader/src/reader/selection_utils.dart';
import 'package:khs/qutzem_reader/src/text_document.dart';

void main() {
  test('locateSelectionParts: точные офсеты на реальном FB2', () {
    final book = TextDocument.fromFb2File(
        r'C:\Users\user\AppData\Roaming\QutZem\QutZem Reader\library\books\b1789935904373410.fb2');
    // Блоки строятся ровно как в SpreadReader._buildBlocks.
    final blocks = <SelectionBlock>[];
    for (var c = 0; c < book.chapters.length; c++) {
      for (final m in RegExp(r'[^\n]+').allMatches(book.chapters[c].text)) {
        final raw = m.group(0)!;
        final t = raw.trim();
        if (t.isEmpty) continue;
        final start = m.start + (raw.length - raw.trimLeft().length);
        blocks.add((
          chapter: c,
          start: start,
          end: start + t.length,
          text: t
        ));
      }
    }
    expect(blocks.length, greaterThan(1000));

    // Выделение через три абзаца: хвост + целый + начало. Склейка без
    // разделителя — как это делает Flutter.
    var checked = 0;
    for (var i = 5; i < blocks.length - 3; i += 37) {
      final a = blocks[i];
      final b = blocks[i + 1];
      final c = blocks[i + 2];
      if (a.chapter != b.chapter || b.chapter != c.chapter) continue;
      if (a.text.length < 30 || c.text.length < 30) continue;
      final want = [
        a.text.substring(a.text.length - 20),
        b.text,
        c.text.substring(0, 18),
      ];
      final parts = locateSelectionParts(
        selection: want.join(),
        blocks: blocks.sublist(max(0, i - 5), i + 5),
        from: 5,
      );
      expect(parts.length, 3, reason: 'абзац #$i не разложился на 3 части');
      final chText = book.chapters[a.chapter].text;
      for (var k = 0; k < 3; k++) {
        expect(chText.substring(parts[k].$2, parts[k].$3).trim(), want[k].trim(),
            reason: 'часть $k абзаца #$i');
        expect(parts[k].$1, a.chapter);
      }
      checked++;
    }
    expect(checked, greaterThan(20));

    // Повторяющийся абзац: диапазон должен указывать на выбранное место,
    // а не на первое вхождение в главе.
    var rep = 0;
    for (var i = 10; i < blocks.length - 2; i++) {
      if (blocks[i].text.length < 12) continue;
      if (blocks[i].chapter != blocks[i + 2].chapter) continue;
      if (blocks[i].text != blocks[i + 2].text) continue;
      final piece = blocks[i].text.substring(3, 11).trim();
      if (piece.isEmpty) continue;
      final at = blocks[i].text.indexOf(piece);
      final parts = locateSelectionParts(
        selection: piece,
        blocks: blocks.sublist(i, i + 3),
      );
      expect(parts.length, 1);
      expect(parts[0].$2, blocks[i].start + at);
      expect(parts[0].$3, blocks[i].start + at + piece.length);
      rep++;
      if (rep > 15) break;
    }
    expect(rep, greaterThan(0), reason: 'в книге нет повторяющихся абзацев');

    // Реальный случай из «Формулы бессмертия»: выделение через границу двух
    // абзацев. Flutter склеивает их без разделителя («…заколачивают…В
    // общем…»), раньше такое выделение вообще не находилось (start=0, end=0).
    final tail = 'гвоздями заколачивают…';
    final head = 'В общем, настороженное и негативное';
    int a = -1, b = -1;
    for (var i = 0; i < blocks.length - 1; i++) {
      if (a < 0 && blocks[i].text.endsWith(tail)) a = i;
      if (a >= 0 && blocks[i + 1].text.startsWith(head)) {
        b = i + 1;
        break;
      }
    }
    expect(a, greaterThanOrEqualTo(0), reason: 'не найден абзац с «…заколачивают…»');
    expect(b, greaterThan(a), reason: 'следующий абзац не найден');
    final glued = tail + head; // ровно то, что отдаёт SelectionArea
    final parts2 = locateSelectionParts(
      selection: glued,
      blocks: blocks.sublist(max(0, a - 2), b + 2),
      from: 2,
    );
    expect(parts2.length, 2, reason: 'ожидались два абзаца, получено ${parts2.length}');
    final chText = book.chapters[blocks[a].chapter].text;
    expect(chText.substring(parts2[0].$2, parts2[0].$3), tail);
    expect(chText.substring(parts2[1].$2, parts2[1].$3), head);
    expect(parts2[0].$1, blocks[a].chapter);
    expect(parts2[1].$1, blocks[b].chapter);
  });
}
