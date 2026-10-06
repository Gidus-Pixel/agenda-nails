import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:agenda_nails/dominio/backup.dart';
import 'package:agenda_nails/dominio/cifratura.dart';
import 'package:agenda_nails/dominio/demo.dart';
import 'package:agenda_nails/dominio/privacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'aiuto.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('backup → ripristino su un altro dispositivo (foto incluse)', () async {
    final a = await datiDiProva();
    await caricaDatiDemo(a);
    await a.salva('foto', {'id': 'f1', 'clienteId': a.elenco('clienti').first['id'], 'tipo': 'dopo', 'blobTipo': 'image/jpeg'});
    await a.salvaBytesFoto('f1', Uint8List.fromList([9, 8, 7, 6]));
    await a.scriviMeta('cloud', {'token': 'segreto'}); // dato locale: NON deve finire nel backup
    final b = await creaBackup(a);
    expect(utf8.decode(b).contains('segreto'), isFalse);

    final nuovo = await datiDiProva(orari: false);
    await applicaBackup(nuovo, leggiBackup(b));
    for (final c in ['clienti', 'appuntamenti', 'schede_lavoro', 'servizi', 'blocchi', 'foto']) {
      expect(nuovo.conta(c), a.conta(c), reason: c);
    }
    expect(await nuovo.bytesFoto('f1'), [9, 8, 7, 6]);
    expect(nuovo.cfg['orari'], isA<Map>());
    expect(nuovo.nomeAttivita, 'Nails Test');
  });

  test('backup cifrato: stesso formato della web app', () async {
    final a = await datiDiProva();
    await caricaDatiDemo(a);
    final chiaro = await creaBackup(a, conFoto: false);
    final cifrato = await cifraBackup(chiaro, 'una-password-lunga');
    expect(eBackupCifrato(cifrato), isTrue);
    expect(await decifraBackup(cifrato, 'una-password-lunga'), chiaro);
    await expectLater(decifraBackup(cifrato, 'sbagliata'), throwsA(isA<ErroreCifratura>()));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('ripristino di un backup creato dalla versione web (anche cifrato)', () async {
    final web = File('test/dati/backup_web.json').readAsBytesSync();
    final d = await datiDiProva(orari: false);
    await applicaBackup(d, leggiBackup(web));
    expect(d.get('clienti', 'c1')?['nome'], 'Anna');
    expect(d.nomeAttivita, 'Nails Web');
    final png = await d.bytesFoto('f1');
    expect(png!.sublist(1, 4), utf8.encode('PNG'));
    expect(d.get('foto', 'f1')?['blobTipo'], 'image/png');

    final cifrato = File('test/dati/backup_web.agendabak').readAsBytesSync();
    expect(eBackupCifrato(cifrato), isTrue);
    final chiaro = await decifraBackup(cifrato, 'prova-backup-1');
    expect(chiaro, web);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('file non validi', () {
    expect(() => leggiBackup(Uint8List.fromList(utf8.encode('{"app":"altro"}'))), throwsA(isA<FormatException>()));
    expect(() => leggiBackup(Uint8List.fromList(utf8.encode('non json'))), throwsA(isA<FormatException>()));
    expect(() => leggiBackup(Uint8List.fromList(utf8.encode('{"app":"agenda-nails","tipo":"backup-completo","schemaVersion":99,"dati":{}}'))), throwsA(isA<FormatException>()));
  });

  test('dati di prova: caricati e rimossi senza toccare i dati veri', () async {
    final d = await datiDiProva();
    await d.salva('clienti', {'nome': 'Vera', 'cognome': 'Cliente', 'archiviato': false});
    await caricaDatiDemo(d);
    expect(d.conta('clienti'), greaterThan(1));
    expect(d.conta('appuntamenti'), greaterThan(5));
    await rimuoviDatiDemo(d);
    expect(d.elenco('clienti').single['nome'], 'Vera');
    expect(d.conta('appuntamenti'), 0);
  });

  test('cancellazione di una cliente con anonimizzazione', () async {
    final d = await datiDiProva();
    await caricaDatiDemo(d);
    final c = d.elenco('clienti').firstWhere((c) => d.elenco('schede_lavoro').any((s) => s['clienteId'] == c['id']));
    final id = c['id'] as String;
    final nApp = d.elenco('appuntamenti').where((a) => a['clienteId'] == id).length;
    final esp = await esportaDatiCliente(d, id);
    expect((esp['appuntamenti'] as List).length, nApp);
    await eliminaClienteConAnonimizzazione(d, id);
    expect(d.get('clienti', id), isNull);
    expect(d.elenco('appuntamenti').where((a) => a['clienteNome'] == 'Cliente eliminata').length, nApp);
    expect(d.meta('elim:clienti:$id'), isNotNull);
  });
}
