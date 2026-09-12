import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

import '../lib/services/update_signing.dart' show buildUpdateMessage;

/// Инструмент владельца KHS:
///   dart run tool/sign_update.dart gen-key <file>
///     — создаёт Ed25519-ключ, пишет приватный (base64) в <file>,
///       печатает ПУБЛИЧНЫЙ для встраивания в update_signing.dart.
///   dart run tool/sign_update.dart sign <update.json> <privKeyFile>
///     — считает SHA-256 и размеры файлов (android/windows), заполняет
///       update.json, подписывает и сохраняет (UTF-8, без BOM).
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('usage: gen-key <file> | sign <update.json> <privKeyFile>');
    exit(2);
  }
  if (args[0] == 'gen-key') {
    final out = File(args[1]);
    final keyPair = await Ed25519().newKeyPair();
    final privBytes = await keyPair.extractPrivateKeyBytes();
    final pub = await keyPair.extractPublicKey();
    await out.writeAsString(base64Encode(privBytes), flush: true);
    stdout.writeln('PRIVATE_KEY_WRITTEN=${out.absolute.path}');
    stdout.writeln('PUBLIC=' + base64Encode(pub.bytes));
    return;
  }
  if (args[0] == 'sign') {
    final jsonFile = File(args[1]);
    final privFile = File(args[2]);
    if (!await jsonFile.exists()) {
      stdout.writeln('not found: ${jsonFile.path}');
      exit(2);
    }
    if (!await privFile.exists()) {
      stdout.writeln('not found: ${privFile.path}');
      exit(2);
    }
    var text = await jsonFile.readAsString();
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final meta = jsonDecode(text) as Map<String, dynamic>;

    var changed = false;
    for (final key in ['android', 'windows']) {
      final name = meta[key] as String?;
      if (name == null || name.trim().isEmpty) continue;
      final f = File('${jsonFile.parent.path}${Platform.pathSeparator}$name');
      if (!await f.exists()) {
        stdout.writeln('file for "$key" not found: ${f.path}');
        exit(2);
      }
      final bytes = await f.readAsBytes();
      meta['${key}_size'] = bytes.length;
      meta['${key}_sha256'] = sha256.convert(bytes).toString().toLowerCase();
      changed = true;
    }
    if (!changed) {
      stdout.writeln('nothing to sign (no android/windows entries)');
      exit(2);
    }

    final privB64 = (await privFile.readAsString()).trim();
    final keyPair = await Ed25519().newKeyPairFromSeed(base64Decode(privB64));
    final message = buildUpdateMessage(meta);
    final sig = await Ed25519().signString(message, keyPair: keyPair);
    meta['signature'] = base64Encode(sig.bytes);

    final buf = StringBuffer('{\n');
    final keys = meta.keys.toList()..sort();
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final v = meta[k];
      final kv = jsonEncode(k);
      final vv = v is String ? jsonEncode(v) : '$v';
      final comma = i < keys.length - 1 ? ',' : '';
      buf.writeln('    $kv:  $vv$comma');
    }
    buf.write('}\n');
    await jsonFile.writeAsString(buf.toString(), flush: true);
    stdout.writeln('SIGNED ${jsonFile.path}');
    stdout
        .writeln('SIZE android=${meta['android_size']} windows=${meta['windows_size']}');
    stdout.writeln('SHA android=${meta['android_sha256']}');
    stdout.writeln('SHA windows=${meta['windows_sha256']}');
    return;
  }
  stdout.writeln('unknown command: ${args[0]}');
  exit(2);
}