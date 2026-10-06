import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agenda_nails/dominio/cifratura.dart';
import 'package:agenda_nails/dominio/cloud.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vettori generati con WebCrypto (Node), cioè con lo stesso codice della versione web:
/// se questi test passano, cloud e backup cifrati sono compatibili tra web, iOS e Android.
void main() {
  final v = jsonDecode(File('test/dati/vettori.json').readAsStringSync()) as Map<String, dynamic>;
  Uint8List b(String k) => base64Decode(v[k] as String);

  test('PBKDF2-SHA256 310000 → chiavi AES e HMAC come la web app', () async {
    final k = await Cloud.derivaChiavi(v['password'] as String, v['sale'] as String);
    expect(base64Encode(k.aes), v['aes']);
    expect(base64Encode(k.hmac), v['hmac']);
    final k256 = await Cifratura.pbkdf2(v['password'] as String, b('sale'), 310000, 256);
    expect(base64Encode(k256), v['chiaveBackup256']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('AES-GCM: stesso risultato di WebCrypto e decifratura', () async {
    final c = await Cifratura.cifra(b('aes'), b('pacchetto'), iv: b('iv'));
    expect(base64Encode(c), v['cifrato']);
    final p = await Cifratura.decifra(b('aes'), b('cifrato'));
    expect(base64Encode(p), v['pacchetto']);
  });

  test('password sbagliata → ErroreCifratura', () async {
    final altra = Uint8List.fromList(List.filled(32, 7));
    await expectLater(Cifratura.decifra(altra, b('cifrato')), throwsA(isA<ErroreCifratura>()));
  });

  test('chiave del record (HMAC, base64url senza "=")', () async {
    expect(await Cloud.chiaveRecord(b('hmac'), 'clienti', 'c1'), v['chiaveRecord']);
  });

  test('verificatore della password', () async {
    final iv = Uint8List.fromList(List.generate(12, (i) => 0xb1 + i));
    final ver = await Cifratura.cifra(b('aes'), utf8.encode('agenda-nails:password-ok'), iv: iv);
    expect(base64Encode(ver), v['verificatore']);
    expect(await Cloud.controllaVerificatore(b('aes'), v['verificatore'] as String), isTrue);
    expect(await Cloud.controllaVerificatore(Uint8List(32), v['verificatore'] as String), isFalse);
  });

  test('pacchetto del record: impacchetta/spacchetta', () {
    final p = Cloud.spacchetta(b('pacchetto'));
    expect(p.oggetto['a'], 'clienti');
    expect((p.oggetto['r'] as Map)['nome'], 'Anna');
    expect(p.binario == null || p.binario!.isEmpty, isTrue);
    final rifatto = Cloud.impacchetta(p.oggetto);
    expect(base64Encode(rifatto), v['pacchetto']);
    final conFoto = Cloud.impacchetta({'a': 'foto', 'r': {'id': 'f1'}}, Uint8List.fromList([1, 2, 3]));
    final x = Cloud.spacchetta(conFoto);
    expect(x.binario, [1, 2, 3]);
  });
}
