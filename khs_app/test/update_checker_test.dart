import 'dart:async';
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
    test(
      'интернет читает update.json со страницы, а файл качает из релиза',
      () {
        final checker = UpdateChecker(
          host: '192.168.1.5:4680',
          token: '',
          webBaseUrl: 'https://gagaga1399.github.io/khs-promo/',
        );
        expect(
          checker.metaUrl(UpdateSource.web).toString(),
          'https://gagaga1399.github.io/khs-promo/update.json',
        );
        // Файлы лежат в Releases, а не в корне сайта: коммитить 80 МБ в git
        // каждый релиз не нужно, и без этого скачивание отдавало 404.
        expect(
          checker.fileUrl(UpdateSource.web, 'khs-1.2.32.apk').toString(),
          'https://github.com/gagaga1399/khs-promo/releases/latest/download/'
          'khs-1.2.32.apk',
        );
      },
    );

    test('адрес файлов в интернете можно переопределить', () {
      final checker = UpdateChecker(
        host: '192.168.1.5:4680',
        token: '',
        webFileBaseUrl: 'https://cdn.example.com/files/',
      );
      expect(
        checker.fileUrl(UpdateSource.web, 'khs-1.2.32.apk').toString(),
        'https://cdn.example.com/files/khs-1.2.32.apk',
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

  group('UpdateChecker: выбор источника', () {
    UpdateCheckResult ok(String version, UpdateSource source) =>
        UpdateCheckResult(
          UpdateCheckStatus.ok,
          UpdateInfo(
            version: version,
            notes: '',
            androidFile: 'khs-$version.apk',
            androidSha256: '',
          ),
          source,
        );

    test('ПК с более свежей сборкой побеждает интернет', () {
      final web = ok('1.2.32', UpdateSource.web);
      final pc = ok('1.2.33', UpdateSource.pc);
      expect(newestOf(web, pc)!.info!.version, '1.2.33');
      expect(newestOf(web, pc)!.source, UpdateSource.pc);
    });

    test('интернет побеждает, когда он свежее', () {
      final web = ok('1.2.33', UpdateSource.web);
      final pc = ok('1.2.32', UpdateSource.pc);
      expect(newestOf(web, pc)!.info!.version, '1.2.33');
      expect(newestOf(web, pc)!.source, UpdateSource.web);
    });

    test('на равных версиях не важно, кто ответил первым', () {
      final web = ok('1.2.32', UpdateSource.web);
      final pc = ok('1.2.32', UpdateSource.pc);
      expect(newestOf(web, pc)!.source, UpdateSource.web);
    });

    test('сравнение идёт по числам, а не по строкам', () {
      // «1.2.9» меньше «1.2.10», хотя как стрроки наоборот.
      expect(
        newestOf(
          ok('1.2.9', UpdateSource.pc),
          ok('1.2.10', UpdateSource.web),
        )!.info!.version,
        '1.2.10',
      );
    });

    test('без одного из источников берётся другой', () {
      final web = ok('1.2.32', UpdateSource.web);
      expect(newestOf(null, web), web);
      expect(newestOf(web, null), web);
      expect(newestOf(null, null), isNull);
    });

    group('pickUpdateResult: что реально показываем пользователю', () {
      UpdateCheckResult st(UpdateCheckStatus s, [UpdateSource? src]) =>
          UpdateCheckResult(s, null, src);

      test('ПК со свежей сборкой не теряется за интернетом', () {
        // Именно этот случай ломался: интернет отвечал ok и возвращался
        // раньше ПК, поэтому неопубликованная сборка была недоступна.
        final r = pickUpdateResult(
          web: ok('1.2.32', UpdateSource.web),
          pc: ok('1.2.34', UpdateSource.pc),
        );
        expect(r.info!.version, '1.2.34');
        expect(r.source, UpdateSource.pc);
      });

      test(
        'подписанные данные важнее «обновлений нет» с другого источника',
        () {
          final r = pickUpdateResult(
            web: st(UpdateCheckStatus.noUpdate, UpdateSource.web),
            pc: ok('1.2.34', UpdateSource.pc),
          );
          expect(r.status, UpdateCheckStatus.ok);
          expect(r.source, UpdateSource.pc);
        },
      );

      test('выключенный ПК не выдаётся за недоступность сервера', () {
        final r = pickUpdateResult(
          web: st(UpdateCheckStatus.noUpdate, UpdateSource.web),
          pc: st(UpdateCheckStatus.unreachable, UpdateSource.pc),
        );
        expect(r.status, UpdateCheckStatus.noUpdate);
        expect(r.source, UpdateSource.web);
      });

      test('без интернета «обновлений нет» от ПК остаётся «нет»', () {
        final r = pickUpdateResult(
          web: st(UpdateCheckStatus.unreachable, UpdateSource.web),
          pc: st(UpdateCheckStatus.noUpdate, UpdateSource.pc),
        );
        expect(r.status, UpdateCheckStatus.noUpdate);
        expect(r.source, UpdateSource.pc);
      });

      test('оба источника молчат — сообщаем о недоступности', () {
        final r = pickUpdateResult(
          web: st(UpdateCheckStatus.unreachable, UpdateSource.web),
          pc: st(UpdateCheckStatus.unreachable, UpdateSource.pc),
        );
        expect(r.status, UpdateCheckStatus.unreachable);
      });

      test('источник не опрашивался вовсе — null, а не unreachable', () {
        // ПК выключен в настройках (host пустой), интернет ответил.
        expect(
          pickUpdateResult(web: ok('1.2.33', UpdateSource.web)).source,
          UpdateSource.web,
        );
        // Наоборот: интернет отключён, работает только ПК.
        expect(
          pickUpdateResult(pc: ok('1.2.33', UpdateSource.pc)).source,
          UpdateSource.pc,
        );
        // Ни одного источника — честная недоступность.
        expect(pickUpdateResult().status, UpdateCheckStatus.unreachable);
      });

      test('битая подпись видна, а не прячется под «обновлений нет»', () {
        final r = pickUpdateResult(
          web: st(UpdateCheckStatus.badSignature, UpdateSource.web),
          pc: st(UpdateCheckStatus.unreachable, UpdateSource.pc),
        );
        expect(r.status, UpdateCheckStatus.badSignature);
        expect(r.source, UpdateSource.web);
      });

      test('битая подпись важнее «обновлений нет» с другого источника', () {
        final r = pickUpdateResult(
          web: st(UpdateCheckStatus.noUpdate, UpdateSource.web),
          pc: st(UpdateCheckStatus.badSignature, UpdateSource.pc),
        );
        expect(r.status, UpdateCheckStatus.badSignature);
        expect(r.source, UpdateSource.pc);
      });

      test('подписанное обновление важнее битой подписи на другом', () {
        // ПК отдал настоящий релиз, интернет подсунул испорченные данные:
        // обновление всё равно предлагаем, молчание здесь было бы неверным.
        final r = pickUpdateResult(
          web: st(UpdateCheckStatus.badSignature, UpdateSource.web),
          pc: ok('1.2.34', UpdateSource.pc),
        );
        expect(r.status, UpdateCheckStatus.ok);
        expect(r.source, UpdateSource.pc);
      });
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
      // Подпись не сошлась. Обновление не предлагаем — и отдельно говорим,
      // что источнику верить нельзя, вместо прежнего молчаливого
      // «обновлений нет», в котором испорченные данные выглядели как
      // отсутствие обновления.
      expect(result.status, UpdateCheckStatus.badSignature);
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
      final file =
          await UpdateChecker(
            host: '',
            token: 'не-нужен',
            webBaseUrl: 'http://127.0.0.1:${server.port}',
            webFileBaseUrl: 'http://127.0.0.1:${server.port}',
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

  group('UpdateChecker: зависание', () {
    test('сервер, который не отвечает, не держит проверку открытой', () async {
      // Соединение принимается, но заголовков ответа не приходит никогда.
      // Раньше ожидание ответа шло без предела, и окно обновления висело.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final checker = UpdateChecker(
        host: '',
        token: '',
        webBaseUrl: 'http://127.0.0.1:${server.port}',
        responseTimeout: const Duration(milliseconds: 300),
        stallTimeout: const Duration(milliseconds: 300),
      );

      final result = await checker.fetch();

      expect(result.status, UpdateCheckStatus.unreachable);
    });

    test('сервер, который замолчал посреди файла, обрывает загрузку', () async {
      // Заголовки и кусок файла приходят, потом сервер перестаёт писать.
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        req.response.statusCode = 200;
        req.response.add(utf8.encode('начало'));
        await req.response.flush();
        // Дальше намеренно ничего не отправляем и не закрываем соединение.
      });

      final dir = await Directory.systemTemp.createTemp('khs-stall');
      addTearDown(() => dir.delete(recursive: true));
      final checker = UpdateChecker(
        host: '',
        token: '',
        webBaseUrl: 'http://127.0.0.1:${server.port}',
        webFileBaseUrl: 'http://127.0.0.1:${server.port}',
        responseTimeout: const Duration(milliseconds: 500),
        stallTimeout: const Duration(milliseconds: 400),
      );

      await expectLater(
        checker.download('khs-1.2.34.exe', dir, source: UpdateSource.web),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('таймауты заданы и не превратились в вечные', () {
      final checker = UpdateChecker(host: '', token: '');
      expect(checker.responseTimeout, lessThan(const Duration(minutes: 1)));
      expect(checker.stallTimeout, lessThan(const Duration(minutes: 1)));
      // Простой раньше стоял 180 секунд — обрыв выглядел как «идёт загрузка».
      expect(checker.stallTimeout, lessThan(const Duration(seconds: 60)));
    });
  });
}
