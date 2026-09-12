import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Транспортное шифрование тела синхронизации.
///
/// Ключ выводится из ключа доступа (token) — он есть и на ПК, и на телефоне
/// и БОЛЬШЕ НЕ ПЕРЕДАЁТСЯ по сети. Зашифрованное тело само является
/// аутентификацией: не зная ключа, сообщение не расшифровать и не подделать.
///
/// Формат сообщения в JSON-поле data: base64( nonce(12) || ciphertext || mac(16) ).
class SyncCrypto {
  static final AesGcm _gcm = AesGcm.with256bits();
  static final Random _rnd = Random.secure();

  static const List<int> _salt = [
    107, 104, 115, 58, 115, 121, 110, 99, 58, 116, 114, 97, 110, 115, 112,
    111, 114, 116, 58, 118, 49, // 'khs:sync:transport:v1'
  ];
  static const List<int> _aad = [
    107, 104, 115, 58, 115, 121, 110, 99, 58, 97, 97, 100, 58, 118, 49, //
  ]; // 'khs:sync:aad:v1'

  static const int _nonceLen = 12;
  static const int _macLen = 16;
  static const int _pbkdf2Iterations = 30000;

  static Future<SecretKey> _deriveKey(String token) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(token)),
      nonce: _salt,
    );
  }

  /// Шифрует [plaintext] в строку base64 (nonce||ct||mac).
  static Future<String> encrypt(String token, String plaintext) async {
    final key = await _deriveKey(token);
    final nonce = List<int>.generate(_nonceLen, (_) => _rnd.nextInt(256));
    final box = await _gcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
      aad: _aad,
    );
    final blob = <int>[...nonce, ...box.cipherText, ...box.mac.bytes];
    return base64Encode(blob);
  }

  /// Расшифровывает [dataB64] (base64 nonce||ct||mac). Бросает исключение
  /// при неверном ключе или повреждении данных.
  static Future<String> decrypt(String token, String dataB64) async {
    final blob = base64Decode(dataB64);
    if (blob.length < _nonceLen + _macLen) {
      throw const FormatException('khs: bad ciphertext');
    }
    final nonce = blob.sublist(0, _nonceLen);
    final ct = blob.sublist(_nonceLen, blob.length - _macLen);
    final mac = blob.sublist(blob.length - _macLen);
    final key = await _deriveKey(token);
    final box = SecretBox(
      ct,
      nonce: nonce,
      mac: Mac(mac),
    );
    final clear = await _gcm.decrypt(box, secretKey: key, aad: _aad);
    return utf8.decode(clear);
  }
}