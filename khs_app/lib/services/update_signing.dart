import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Ключ проверки цифровой подписи обновлений (Ed25519).
/// Свой СООТВЕТСТВУЕТ приватному ключу в tool/sign_update.dart /
/// на диске владельца. Не публикуйте приватный ключ.
const String kUpdatePublicKeyBase64 =
    'kjJ38XL3j/gHPLsN1bz3U6XKuQIfcJ8QNsaqqGUEPBU=';

SimplePublicKey get kUpdatePublicKey => SimplePublicKey(
      base64Decode(kUpdatePublicKeyBase64),
      type: KeyPairType.ed25519,
    );

/// Каноническая строка, которая подписывается. ТОЛЬКО ЭТОТ ФОРМАТ
/// понимает tool/sign_update.dart и приложение. Менять нельзя — сломаются
/// все проверки.
String buildUpdateMessage(Map<String, dynamic> meta) {
  final parts = <String>[
    meta['version'] as String? ?? '',
    meta['android'] as String? ?? '',
    '${meta['android_size'] ?? ''}',
    (meta['android_sha256'] as String? ?? '').trim().toLowerCase(),
    meta['windows'] as String? ?? '',
    '${meta['windows_size'] ?? ''}',
    (meta['windows_sha256'] as String? ?? '').trim().toLowerCase(),
  ];
  return parts.join('\n');
}

/// True только если update.json подписан нашим приватным ключом.
Future<bool> verifyUpdateSignature(Map<String, dynamic> meta) async {
  final sigB64 = meta['signature'] as String?;
  if (sigB64 == null || sigB64.trim().isEmpty) return false;
  try {
    final signature = Signature(
      base64Decode(sigB64.trim()),
      publicKey: kUpdatePublicKey,
    );
    return await Ed25519().verifyString(
      buildUpdateMessage(meta),
      signature: signature,
    );
  } catch (_) {
    return false;
  }
}