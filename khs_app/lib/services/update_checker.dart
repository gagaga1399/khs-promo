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

/// Ходит на ПК (тот же адрес, что и синк) и спрашивает про обновления.
class UpdateChecker {
  final String host; // например 192.168.1.5:4680
  final String token;

  UpdateChecker({required this.host, required this.token});

Map<String, String> _authHeaders() =>
    token.isEmpty ? const <String, String>{} : {'X-KHS-Token': token};

  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 4)
    ..idleTimeout = const Duration(seconds: 20);

  /// Возвращает метаданные обновления или null, если ПК недоступен
  /// или обновление не настроено.
  Future<UpdateInfo?> fetch() async {
    final client = _client();
    try {
      final req = await client.getUrl(
        Uri.parse('http://$host/api/v1/update'),
      );
      _authHeaders().forEach(req.headers.set);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final text = await utf8.decoder.bind(res).join();
      final json = jsonDecode(text) as Map<String, dynamic>;
      // Без валидной подписи обновление не предлагаем вообще — так
      // «по дороге» нельзя подменить update.json или файлы.
      if (!await verifyUpdateSignature(json)) return null;
      return UpdateInfo.fromJson(json);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  Uri _fileUrl(String filename) =>
      Uri.parse('http://$host/files/${_safeName(filename)}');

  /// Скачивает файл обновления с ПК в [targetDir]. Если задан [expectedSha256],
  /// файл проверяется по SHA-256 и при несовпадении удаляется.
  Future<File> download(
    String filename,
    Directory targetDir, {
    String? expectedSha256,
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
      final sink = file.openWrite();
      try {
        await res.pipe(sink);
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
