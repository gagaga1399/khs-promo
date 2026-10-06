import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:khs/services/obsidian_service.dart';
import 'package:khs/services/sync_server.dart';
import 'package:khs/services/task_database.dart';

/// Тесты привязки сервера к адресу.
///
/// Отдельный файл намеренно: проверка не трогает базу (TaskDatabase открывает
/// файл лениво, при первом запросе), поэтому не может помешать тестам
/// синхронизации, которые жонглируют путями sqflite.
///
/// Токен — тот же, что в sync_roundtrip_test: состояние сервера лежит в общей
/// папке .khs-data, и другой токен приводил к тому, что сервер из соседнего
/// файла отвергал запросы своих тестов (401).
const String bindTestToken = 'test-access-key';

Future<int> _freePort() async {
  final srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = srv.port;
  await srv.close();
  return port;
}

void main() {
  late Directory vault;

  setUpAll(() async {
    TaskDatabase.useStableDesktopPath = false;
    vault = await Directory.systemTemp.createTemp('khs_bind_vault');
  });

  Future<SyncServer> make(String bindHost) async => SyncServer(
    db: TaskDatabase(),
    obsidian: ObsidianService(vault.path),
    port: await _freePort(),
    token: bindTestToken,
    bindHost: bindHost,
    onChanged: () async {},
  );

  test('опечатка в адресе не открывает сервер на всех интерфейсах', () async {
    // Раньше неудачный InternetAddress() молча уводил сервер на 0.0.0.0:
    // синхронизация и раздача обновлений становились доступны любой сети,
    // до которой дотягивается компьютер, а не только домашней.
    final server = await make('не адрес');
    await expectLater(server.start(), throwsA(isA<FormatException>()));
    expect(server.isRunning, isFalse);
  });

  test('не-IP адрес не проходит: никаких имён, IPv6 и мусора', () async {
    for (final bad in [
      'example.com',
      '::1',
      '256.256.256.256',
      ' localhost',
      'localhost',
    ]) {
      final server = await make(bad);
      await expectLater(
        server.start(),
        throwsA(isA<FormatException>()),
        reason: 'адрес «$bad» должен отклоняться',
      );
      expect(server.isRunning, isFalse, reason: 'сервер не должен подняться');
    }
  });

  test('корректный адрес поднимается', () async {
    final server = await make('127.0.0.1');
    await server.start();
    expect(server.isRunning, isTrue);
    await server.stop();
  });

  test('старый формат «IP:порт» поднимает сервер, хвост отброшен', () async {
    // Так реально занесён адрес на одном из компьютеров: 192.168.0.107:4680.
    // Порт здесь ни при чём — он задаётся отдельно, поэтому брать его не надо,
    // но и ронять из-за него сервер нельзя.
    final server = await make('127.0.0.1:4680');
    await server.start();
    expect(server.isRunning, isTrue);
    await server.stop();
  });

  test('порт не спасает не-IP адрес: мусор по-прежнему отклоняется', () async {
    for (final bad in ['256.256.256.256:4680', 'example.com:4680', '::1:4680']) {
      final server = await make(bad);
      await expectLater(
        server.start(),
        throwsA(isA<FormatException>()),
        reason: 'адрес «$bad» должен отклоняться',
      );
      expect(server.isRunning, isFalse, reason: 'сервер не должен подняться');
    }
  });

  test(
    'пустое поле и явный 0.0.0.0 — осознанный выбор слушать везде',
    () async {
      // Это не опечатка, а решение пользователя, поэтому его не блокируем.
      for (final host in ['', '0.0.0.0']) {
        final server = await make(host);
        await server.start();
        expect(server.isRunning, isTrue, reason: 'адрес «$host» допустим');
        await server.stop();
      }
    },
  );
}
