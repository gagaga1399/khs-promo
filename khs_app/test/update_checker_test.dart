import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/services/update_checker.dart';

/// Поднимает раздачу update.json/файла и возвращает её адрес без схемы.
Future<HttpServer> _serve(
  int status,
  String body, {
  String fileName = '',
  List<int>? fileBody,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path;
    if (fileName.isNotEmpty && path.endsWith('/$fileName')) {
      req.response.statusCode = 200;
      req.response.add(fileBody ?? utf8.encode('file'));
    } else {
      req.response.statusCode = status;
      req.response.add(utf8.encode(body));
    }
    await req.response.close();
  });
  return server;
}

String _loopbackPort(HttpServer s) => '127.0.0.1:${s.port}';

void main() {
  group('UpdateChecker: адреса', () {
    test('интернет строит https-адрес update.json и файла', () {
      final checker = UpdateChecker(
        host: '192.168.1.5:4680',
        token: '',
        webBaseUrl: 'https://gagaga1399.github.io/khs-promo/',
      );
      expect(
        checker.metaUrl(UpdateSource.web).toString(),
        'https://gagaga1399.github.io/khs-promo/update.json',
      );
      expect(
        checker.fileUrl(UpdateSource.web, 'khs-1.2.31.apk').toString(),
        'https://gagaga1399.github.io/khs-promo/khs-1.2.31.apk',
      );
    });

    test('ПК строит адрес служебного endpoint и папки раздачи', () {
      final checker = UpdateChecker(
        host: '192.168.1.5:4680',
        token: 'secret',
        webBaseUrl: 'https://example.com',
      );
      expect(
        checker.metaUrl(UpdateSource.pc).toString(),
        'http://192.168.1.5:4680/api/v1/update',
      );
      expect(
        checker.fileUrl(UpdateSource.pc, 'khs-1.2.31.apk').toString(),
        'http://192.168.1.5:4680/files/khs-1.2.31.apk',
      );
    });

    test('имя файла не может вылезти за пределы папки', () {
      final checker = UpdateChecker(host: 'h:1', token: '');
      expect(
        checker.fileUrl(UpdateSource.pc, '../../evil.exe').toString(),
        'http://h:1/files/.._.._evil.exe',
      );
    });

    test('без https в сети интернет не используется — только ПК', () {
      final checker = UpdateChecker(
        host: '192.168.1.5:4680',
        token: '',
        webBaseUrl: 'http://192.168.1.5/khs',
      );
      expect(checker.webUsable, isFalse);
      final loopback = UpdateChecker(
        host: '192.168.1.5:4680',
        token: '',
        webBaseUrl: 'http://127.0.0.1:8080/khs',
      );
      expect(loopback.webUsable, isTrue);
      final https = UpdateChecker(
        host: '192.168.1.5:4680',
        token: '',
        webBaseUrl: 'https://example.com',
      );
      expect(https.webUsable, isTrue);
    });
  });

  group('UpdateChecker: источники', () {
    test('неподписанный update.json из интернета не предлагается', () async {
      final server = await _serve(200, jsonEncode({'version': '9.9.9'}));
      addTearDown(() => server.close(force: true));
      final result = await UpdateChecker(
        host: '',
        token: '',
        webBaseUrl: 'http://127.0.0.1:${server.port}',
      ).fetch();
      // Подпись не сошлась — обновления нет, а не «сервер недоступен».
      expect(result.status, UpdateCheckStatus.noUpdate);
      expect(result.info, isNull);
    });

    test('без адреса ПК интернет-404 — это «обновлений нет»', () async {
      final server = await _serve(404, 'not found');
      addTearDown(() => server.close(force: true));
      final result = await UpdateChecker(
        host: '',
        token: '',
        webBaseUrl: 'http://127.0.0.1:${server.port}',
      ).fetch();
      expect(result.status, UpdateCheckStatus.noUpdate);
    });

    test('интернет недоступен и ПК пуст — «сервер недоступен»', () async {
      final result = await UpdateChecker(
        host: '',
        token: '',
        webBaseUrl: 'http://127.0.0.1:1',
      ).fetch();
      expect(result.status, UpdateCheckStatus.unreachable);
      expect(result.source, isNull);
    });

    test('скачивание с ПК проверяет SHA-256 и удаляет битый файл', () async {
      final server = await _serve(
        200,
        '',
        fileName: 'khs-1.2.31.apk',
        fileBody: utf8.encode('not-the-real-apk'),
      );
      addTearDown(() => server.close(force: true));
      final dir = await Directory.systemTemp.createTemp('khs-upd');
      addTearDown(() => dir.delete(recursive: true));
      final checker = UpdateChecker(
        host: _loopbackPort(server),
        token: '',
        webBaseUrl: '',
      );
      await expectLater(
        checker.download(
          'khs-1.2.31.apk',
          dir,
          expectedSha256: '0' * 64,
          source: UpdateSource.pc,
        ),
        throwsA(isA<HttpException>()),
      );
      expect(
        File('${dir.path}${Platform.pathSeparator}khs-1.2.31.apk').existsSync(),
        isFalse,
      );
    });

    test('скачивание с интернета идёт по https без токена', () async {
      final server = await _serve(
        200,
        '',
        fileName: 'khs-1.2.31.apk',
        fileBody: utf8.encode('payload'),
      );
      addTearDown(() => server.close(force: true));
      final dir = await Directory.systemTemp.createTemp('khs-upd');
      addTearDown(() => dir.delete(recursive: true));
      final progress = <int>[];
      final file = await UpdateChecker(
        host: '',
        token: 'не-нужен',
        webBaseUrl: 'http://127.0.0.1:${server.port}',
      ).download(
        'khs-1.2.31.apk',
        dir,
        onProgress: (r, t) => progress.add(r),
        source: UpdateSource.web,
      );
      expect(await file.readAsString(), 'payload');
      expect(progress, isNotEmpty);
    });
  });
}
