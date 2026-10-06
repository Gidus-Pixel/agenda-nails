import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Cifratura identica alla web app (WebCrypto):
/// - PBKDF2-HMAC-SHA256 per ricavare le chiavi dalla password;
/// - AES-GCM 256 con IV di 12 byte, formato "IV | testo cifrato | tag(16)";
/// - HMAC-SHA256 per i nomi dei record nel cloud.
class Cifratura {
  static final _aes = AesGcm.with256bits();
  static final _hmac = Hmac.sha256();

  static Future<Uint8List> pbkdf2(String password, List<int> sale, int iterazioni, int bit) async {
    final algo = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterazioni, bits: bit);
    final k = await algo.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: sale);
    return Uint8List.fromList(await k.extractBytes());
  }

  static Future<Uint8List> cifra(List<int> chiave, List<int> dati, {List<int>? iv}) async {
    final nonce = iv ?? _aes.newNonce();
    final box = await _aes.encrypt(dati, secretKey: SecretKey(chiave), nonce: nonce);
    final out = BytesBuilder(copy: false)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Lancia [ErroreCifratura] se la chiave è sbagliata o i dati sono danneggiati.
  static Future<Uint8List> decifra(List<int> chiave, Uint8List dati) async {
    if (dati.length < 12 + 16) throw ErroreCifratura();
    final iv = dati.sublist(0, 12);
    final ct = dati.sublist(12, dati.length - 16);
    final tag = dati.sublist(dati.length - 16);
    try {
      final chiaro = await _aes.decrypt(SecretBox(ct, nonce: iv, mac: Mac(tag)), secretKey: SecretKey(chiave));
      return Uint8List.fromList(chiaro);
    } on SecretBoxAuthenticationError {
      throw ErroreCifratura();
    }
  }

  /// Decifra con IV e testo cifrato separati (formato dei backup cifrati della web app).
  static Future<Uint8List> decifraSeparato(List<int> chiave, List<int> iv, Uint8List ctConTag) async {
    final dati = BytesBuilder(copy: false)
      ..add(iv)
      ..add(ctConTag);
    return decifra(chiave, dati.toBytes());
  }

  static Future<Uint8List> hmac(List<int> chiave, List<int> dati) async {
    final m = await _hmac.calculateMac(dati, secretKey: SecretKey(chiave));
    return Uint8List.fromList(m.bytes);
  }

  static Uint8List casuali(int n) => Uint8List.fromList(SecretKeyData.random(length: n).bytes);
}

class ErroreCifratura implements Exception {
  @override
  String toString() => 'Password errata oppure dati danneggiati.';
}

String b64(List<int> b) => base64Encode(b);
Uint8List daB64(String s) => base64Decode(s);
String b64url(List<int> b) => base64Url.encode(b).replaceAll('=', '');
