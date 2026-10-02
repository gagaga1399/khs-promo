import 'dart:io';

import 'package:khs/services/update_checker.dart';

/// Проверка обновления через интернет настоящим кодом приложения.
///
///   dart run tool/check_update_online.dart [https://host/path]
///
/// Печатает, что именно ответил сервер, прошла ли подпись и совпали ли
/// размеры/хэши скачанного файла. Нужен после каждой публикации, чтобы
/// убедиться, что телефон найдёт обновление без ПК.
Future<void> main(List<String> args) async {
  final flags = args.where((a) => a.startsWith('--')).toSet();
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final base = positional.isEmpty ? kUpdateWebBaseUrl : positional.first;
  stdout.writeln('server: $base');
  final checker = UpdateChecker(host: '', token: '', webBaseUrl: base);
  stdout.writeln('https only: ${checker.webUsable}');

  final result = await checker.fetch();
  stdout.writeln('status: ${result.status.name}');
  stdout.writeln('source: ${result.source?.name ?? '-'}');
  final info = result.info;
  if (info == null) {
    stdout.writeln('метаданных нет');
    exit(result.status == UpdateCheckStatus.noUpdate ? 0 : 1);
  }
  stdout.writeln('version: ${info.version}');
  stdout.writeln('notes: ${info.notes}');
  stdout.writeln('android: ${info.androidFile} '
      '${info.androidSize} ${info.androidSha256}');
  stdout.writeln('windows: ${info.windowsFile} '
      '${info.windowsSize} ${info.windowsSha256}');

  final target = info.windowsFile ?? info.androidFile;
  final expected = info.windowsSha256 ?? info.androidSha256;
  if (target == null || info.history.isNotEmpty) {
    stdout.writeln('историю версий не проверяем (файлы не качаем)');
    return;
  }
  if (flags.contains('--no-download')) {
    stdout.writeln('скачивание пропущено (--no-download)');
    return;
  }
  final dir = await Directory.systemTemp.createTemp('khs-upd-check');
  try {
    final file = await checker.download(
      target,
      dir,
      expectedSha256: expected,
      onProgress: (r, t) {
        if (t > 0 && r % (t ~/ 10 + 1) < 65536) {
          stdout.write('\r  ${(r * 100 ~/ t)}%');
        }
      },
      source: result.source ?? UpdateSource.pc,
    );
    stdout.writeln('\nскачано: ${await file.length()} байт, хэш сошёлся');
  } finally {
    await dir.delete(recursive: true);
  }
}
