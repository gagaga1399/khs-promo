import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'releases.dart';
import 'update_signing.dart';

/// Метаданные обновления, которое раздаёт ПК (файл update.json на сервере).
class UpdateInfo {
  final String version;
  final String notes;
  final String? androidFile;
  final int? androidSize;
  final String? androidSha256;
  final String? windowsFile;
  final int? windowsSize;
  final String? windowsSha256;

  /// Связанная читалка QutZem Reader: файл и целевая версия с ПК.
  final String? readerFile;
  final int? readerSize;
  final String? readerSha256;
  final String? readerVersion;

  /// Полная история версий с сервера (актуальная даже на старых клиентах).
  final List<ReleaseInfo> history;

  const UpdateInfo({
    required this.version,
    required this.notes,
    this.androidFile,
    this.androidSize,
    this.androidSha256,
    this.windowsFile,
    this.windowsSize,
    this.windowsSha256,
    this.readerFile,
    this.readerSize,
    this.readerSha256,
    this.readerVersion,
    this.history = const [],
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) => UpdateInfo(
    version: json['version'] as String? ?? '',
    notes: json['notes'] as String? ?? '',
    androidFile: json['android'] as String?,
    androidSize: json['android_size'] as int?,
    androidSha256: json['android_sha256'] as String?,
    windowsFile: json['windows'] as String?,
    windowsSize: json['windows_size'] as int?,
    windowsSha256: json['windows_sha256'] as String?,
    readerFile: json['reader'] as String?,
    readerSize: json['reader_size'] as int?,
    readerSha256: json['reader_sha256'] as String?,
    readerVersion:
        (json['reader_version'] as String? ?? '').trim().isNotEmpty
            ? (json['reader_version'] as String).trim()
            : null,
    history: [
      for (final row in (json['history'] as List? ?? []))
        if (row is Map<String, dynamic>)
          ReleaseInfo(
            version: row['version'] as String? ?? '',
            date: row['date'] as String? ?? '',
            changes: [
              for (final c in (row['changes'] as List? ?? []))
                if (c is String) ChangeEntry(c),
            ],
          ),
    ],
  );
}

/// Состояние ответа сервера на проверку обновления: чтобы отличать «сервер
/// недоступен» от «сервер доступен, но обновление на нём не настроено».
enum UpdateCheckStatus { ok, unreachable, noUpdate }

/// Откуда пришли метаданные обновления и откуда качать сами файлы.
enum UpdateSource {
  /// Интернет: публичная страница проекта с update.json и файлами.
  web,

  /// Домашний ПК по Wi-Fi (как раньше).
  pc,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? info;

  /// Источник, на котором ответил сервер; null, если ответа не было.
  final UpdateSource? source;

  const UpdateCheckResult(this.status, [this.info, this.source]);
}

/// Где лежат обновления в интернете по умолчанию.
const String kUpdateWebBaseUrl = 'https://gagaga1399.github.io/khs-promo';

/// Спрашивает про обновления сначала в интернете, а если там не вышло —
/// у ПК по Wi-Fi (тот же адрес, что и у синхронизации).
class UpdateChecker {
  final String host; // например 192.168.1.5:4680
  final String token;

  /// Адрес публичной страницы с update.json и файлами. Пусто — только ПК.
  final String? webBaseUrl;

  UpdateChecker({
    required this.host,
    required this.token,
    this.webBaseUrl = kUpdateWebBaseUrl,
  });

  /// Интернет без HTTPS опасен: подпись проверяет файл, но не защищает от
  /// подмены самого ответа. Поэтому молча уходим на ПК, а не качаем.
  /// Исключение — сам компьютер (127.0.0.1): такие адреса не выходят в сеть,
  /// на них удобно гонять локальный сервер при разработке и в тестах.
  bool get webUsable {
    final base = (webBaseUrl?.trim() ?? '').toLowerCase();
    if (base.isEmpty) return false;
    if (base.startsWith('https://')) return true;
    final hostPart = base.replaceFirst(RegExp(r'^https?://'), '').split('/').first;
    final hostOnly = hostPart.split(':').first;
    return hostOnly == '127.0.0.1' || hostOnly == 'localhost';
  }

  Map<String, String> _authHeaders() =>
      token.isEmpty ? const <String, String>{} : {'X-KHS-Token': token};

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    // Большой APK качается не мгновенно — не срывать загрузку между чанками.
    ..idleTimeout = const Duration(seconds: 180);

  /// Спрашивает про обновление. [UpdateCheckResult.status] различает:
  /// `ok` — сервер ответил подписанными данными; `noUpdate` — сервер
  /// доступен, но обновления на нём нет (404/запрет/плохая подпись);
  /// `unreachable` — до сервера не достучаться или ответ не похож на обновление.
  Future<UpdateCheckResult> fetch() async {
    UpdateCheckResult? web;
    if (webUsable) {
      web = await _fetchFrom(UpdateSource.web);
      if (web.status == UpdateCheckStatus.ok) return web;
    }
    if (host.trim().isEmpty) {
      return web ?? const UpdateCheckResult(UpdateCheckStatus.unreachable);
    }
    final pc = await _fetchFrom(UpdateSource.pc);
    if (pc.status == UpdateCheckStatus.ok) return pc;
    // Если ПК просто выключен, а интернет ответил «обновлений нет» —
    // правдивее показать «обновлений нет», а не «сервер недоступен».
    if (pc.status == UpdateCheckStatus.unreachable &&
        web != null &&
        web.status == UpdateCheckStatus.noUpdate) {
      return web;
    }
    return pc;
  }

  Future<UpdateCheckResult> _fetchFrom(UpdateSource source) async {
    final client = _client();
    try {
      final req = await client.getUrl(metaUrl(source));
      if (source == UpdateSource.pc) _authHeaders().forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode == 404 ||
          res.statusCode == 403 ||
          res.statusCode == 429) {
        return UpdateCheckResult(UpdateCheckStatus.noUpdate, null, source);
      }
      if (res.statusCode != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.unreachable);
      }
      final text = await utf8.decoder.bind(res).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      // Без валидной подписи обновление не предлагаем вообще — так
      // «по дороге» нельзя подменить update.json или файлы.
      if (!await verifyUpdateSignature(json)) {
        return UpdateCheckResult(UpdateCheckStatus.noUpdate, null, source);
      }
      final info = UpdateInfo.fromJson(json);
      if (info.version.isEmpty) {
        return UpdateCheckResult(UpdateCheckStatus.noUpdate, info, source);
      }
      return UpdateCheckResult(UpdateCheckStatus.ok, info, source);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.unreachable);
    } finally {
      client.close();
    }
  }

  /// Адрес update.json: в интернете — файл на публичной странице,
  /// у ПК — служебный endpoint синхронизации.
  Uri metaUrl(UpdateSource source) {
    if (source == UpdateSource.web) {
      return Uri.parse('${_normalizeBase(webBaseUrl!)}/update.json');
    }
    return Uri.parse('http://$host/api/v1/update');
  }

  /// Адрес файла: в интернете файл лежит рядом с update.json, у ПК — в
  /// папке раздачи. Токен на ПК по-прежнему нужен, в интернете — нет.
  Uri fileUrl(UpdateSource source, String filename) {
    final name = _safeName(filename);
    if (source == UpdateSource.web) {
      return Uri.parse('${_normalizeBase(webBaseUrl!)}/$name');
    }
    return Uri.parse('http://$host/files/$name');
  }

  static String _normalizeBase(String raw) {
    var v = raw.trim();
    while (v.endsWith('/') && v.isNotEmpty) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// Скачивает файл обновления в [targetDir] из [source] (по умолчанию —
  /// ПК, как раньше). Если задан [expectedSha256], файл проверяется по
  /// SHA-256 и при несовпадении удаляется. [onProgress] вызывается с
  /// (получено байт, всего байт); всего = 0, если сервер не сообщил длину.
  Future<File> download(
    String filename,
    Directory targetDir, {
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
    UpdateSource source = UpdateSource.pc,
  }) async {
    final file = File(
      '${targetDir.path}${Platform.pathSeparator}${_safeName(filename)}',
    );
    final client = _client();
    try {
      final req = await client.getUrl(fileUrl(source, filename));
      if (source == UpdateSource.pc) _authHeaders().forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}');
      }
      final total = res.contentLength > 0 ? res.contentLength : 0;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      final expected = expectedSha256?.trim().toLowerCase();
      if (expected != null && expected.isNotEmpty) {
        final bytes = await file.readAsBytes();
        final actual = sha256.convert(bytes).toString();
        if (actual != expected) {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
          throw HttpException('checksum_mismatch');
        }
      }
      return file;
    } finally {
      client.close();
    }
  }

  String _safeName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'update' : cleaned;
  }
}
