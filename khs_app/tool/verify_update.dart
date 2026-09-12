import 'dart:convert';
import 'dart:io';

import '../lib/services/update_signing.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stdout.writeln('usage: dart run tool/verify_update.dart <update.json>');
    exit(2);
  }
  final text = await File(args[0]).readAsString();
  final meta = jsonDecode(text) as Map<String, dynamic>;
  final ok = await verifyUpdateSignature(meta);
  stdout.writeln(ok ? 'SIGNATURE_OK' : 'SIGNATURE_BAD');
  exit(ok ? 0 : 1);
}