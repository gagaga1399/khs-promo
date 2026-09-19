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

/// Состояние ответа ПК на проверку обновления: чтобы отличать «ПК недоступен»
/// от «ПК доступен, но обновление на нём не настроено» (нет update.json).
enum UpdateCheckStatus { ok, unreachable, noUpdate }

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final UpdateInfo? info;
  const UpdateCheckResult(this.status, [this.info]);
}

/// Ходит на ПК (тот же адрес, что и синк) и спрашивает про обновления.
class UpdateChecker {
  final String host; // например 192.168.1.5:4680
  final String token;

  UpdateChecker({required this.host, required this.token});

Map<String, String> _authHeaders() =>
    token.isEmpty ? const <String, String>{} : {'X-KHS-Token': token};

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    // Большой APK качается не мгновенно — не срывать загрузку между чанками.
    ..idleTimeout = const Duration(seconds: 180);

  /// Спрашивает ПК про обновление. [UpdateCheckResult.status] различает:
  /// `ok` — сервер ответил подписанными данными; `noUpdate` — сервер
  /// доступен, но обновления на нём нет (404/запрет/плохая подпись);
  /// `unreachable` — до ПК не достучаться или ответ не похож на обновление.
  Future<UpdateCheckResult> fetch() async {
    final client = _client();
    try {
      final req = await client.getUrl(
        Uri.parse('http://$host/api/v1/update'),
      );
      _authHeaders().forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode == 404 ||
          res.statusCode == 403 ||
          res.statusCode == 429) {
        return const UpdateCheckResult(UpdateCheckStatus.noUpdate);
      }
      if (res.statusCode != 200) {
        return const UpdateCheckResult(UpdateCheckStatus.unreachable);
      }
      final text = await utf8.decoder.bind(res).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      // Без валидной подписи обновление не предлагаем вообще — так
      // «по дороге» нельзя подменить update.json или файлы.
      if (!await verifyUpdateSignature(json)) {
        return const UpdateCheckResult(UpdateCheckStatus.noUpdate);
      }
      final info = UpdateInfo.fromJson(json);
      if (info.version.isEmpty) {
        return UpdateCheckResult(UpdateCheckStatus.noUpdate, info);
      }
      return UpdateCheckResult(UpdateCheckStatus.ok, info);
    } catch (_) {
      return const UpdateCheckResult(UpdateCheckStatus.unreachable);
    } finally {
      client.close();
    }
  }

  Uri _fileUrl(String filename) =>
      Uri.parse('http://$host/files/${_safeName(filename)}');

  /// Скачивает файл обновления с ПК в [targetDir]. Если задан [expectedSha256],
  /// файл проверяется по SHA-256 и при несовпадении удаляется.
  /// [onProgress] вызывается с (получено байт, всего байт); всего = 0,
  /// если сервер не сообщил длину.
  Future<File> download(
    String filename,
    Directory targetDir, {
    String? expectedSha256,
    void Function(int received, int total)? onProgress,
  }) async {
    final file = File(
      '${targetDir.path}${Platform.pathSeparator}${_safeName(filename)}',
    );
    final client = _client();
    try {
      final req = await client.getUrl(_fileUrl(filename));
      _authHeaders().forEach(req.headers.set);
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
