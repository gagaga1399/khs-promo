import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/qutzem_reader/src/library.dart';
import 'package:path/path.dart' as p;

/// Готовит старую библиотеку: папка с индексом, одной книгой, обложкой и
/// данными чтения.
String _makeLegacy(String root) {
  for (final d in ['books', 'covers', 'data']) {
    Directory(p.join(root, d)).createSync(recursive: true);
  }
  File(p.join(root, 'books', 'b1.pdf')).writeAsStringSync('pdf');
  File(p.join(root, 'covers', 'b1.bin')).writeAsStringSync('cover');
  File(p.join(root, 'data', 'b1.json')).writeAsStringSync('{}');
  File(p.join(root, 'index.json')).writeAsStringSync(
    jsonEncode([
      {
        'id': 'b1',
        'title': 'Книга',
        'author': '',
        'format': 'pdf',
        'fileName': 'b1.pdf',
        'sizeBytes': 3,
        'coverPath': p.join(root, 'covers', 'b1.bin'),
        'addedAt': 1700000000000,
      },
    ]),
  );
  return root;
}

void main() {
  late String legacy;
  late String target;
  late File index;

  setUp(() {
    final base = Directory.systemTemp.createTempSync('khs_lib').path;
    legacy = _makeLegacy(p.join(base, 'old', 'library'));
    target = p.join(base, 'new', 'library');
    Directory(target).createSync(recursive: true);
    index = File(p.join(target, 'index.json'));
  });

  tearDown(() {
    final base = p.dirname(p.dirname(legacy));
    if (Directory(base).existsSync()) {
      Directory(base).deleteSync(recursive: true);
    }
  });

  test('переносит книги, обложки и данные', () {
    final moved = migrateLegacyLibrary(legacy, target, index);

    expect(moved, isTrue);
    expect(File(p.join(target, 'books', 'b1.pdf')).existsSync(), isTrue);
    expect(File(p.join(target, 'covers', 'b1.bin')).existsSync(), isTrue);
    expect(File(p.join(target, 'data', 'b1.json')).existsSync(), isTrue);
  });

  test('coverPath переставляется на новую папку', () {
    migrateLegacyLibrary(legacy, target, index);

    final list = jsonDecode(index.readAsStringSync()) as List<dynamic>;
    final cover = (list.first as Map<String, dynamic>)['coverPath'] as String;
    expect(cover, p.join(target, 'covers', 'b1.bin'));
    expect(cover, isNot(contains('old')));
    // Файл обложки по новому пути обязан существовать, иначе карточки
    // книги останутся без обложек.
    expect(File(cover).existsSync(), isTrue);
  });

  test('исходная папка остаётся нетронутой', () {
    migrateLegacyLibrary(legacy, target, index);

    expect(File(p.join(legacy, 'books', 'b1.pdf')).existsSync(), isTrue);
    expect(File(p.join(legacy, 'index.json')).existsSync(), isTrue);
  });

  test('повторный перенос не трогает уже скопированные книги', () {
    migrateLegacyLibrary(legacy, target, index);
    // Пользователь заменил книгу в новой папке — перенос не должен её
    // затирать, иначе можно потерять данные.
    File(p.join(target, 'books', 'b1.pdf')).writeAsStringSync('changed');

    migrateLegacyLibrary(legacy, target, index);

    expect(
      File(p.join(target, 'books', 'b1.pdf')).readAsStringSync(),
      'changed',
    );
  });

  test('без старой библиотеки ничего не происходит', () {
    final empty = p.join(p.dirname(p.dirname(legacy)), 'nothing');

    final moved = migrateLegacyLibrary(empty, target, index);

    expect(moved, isFalse);
    expect(index.existsSync(), isFalse);
  });

  test('битая запись индекса не роняет перенос', () {
    File(p.join(legacy, 'index.json')).writeAsStringSync('{ не json');

    final moved = migrateLegacyLibrary(legacy, target, index);

    expect(moved, isFalse);
  });

  test('неизвестный формат книги не ломает индекс', () {
    File(p.join(legacy, 'index.json')).writeAsStringSync(
      jsonEncode([
        {
          'id': 'x',
          'title': 't',
          'author': '',
          'fileName': 'x',
          'sizeBytes': 1,
          'addedAt': 1,
        },
        'не объект',
      ]),
    );

    migrateLegacyLibrary(legacy, target, index);

    final list = jsonDecode(index.readAsStringSync()) as List<dynamic>;
    expect(list.length, 1);
  });
}
