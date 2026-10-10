import 'dart:convert';

import 'package:agenda_nails/core/date.dart';
import 'package:agenda_nails/core/util.dart';
import 'package:agenda_nails/dati/copie.dart';
import 'package:agenda_nails/dominio/backup.dart';
import 'package:agenda_nails/dominio/ripristino.dart';
import 'package:agenda_nails/dominio/sicurezza.dart';
import 'package:agenda_nails/servizi/aggiornamenti.dart';
import 'package:agenda_nails/servizi/notifiche.dart';
import 'package:agenda_nails/servizi/widget_home.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'aiuto.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  setUp(() => archivioCopie = ArchivioCopieMemoria());

  // un martedì lontano nel futuro
  const mar = '2030-10-01';
  Map<String, dynamic> app(String k, String da, String a, {String stato = 'prenotato', String nome = 'Anna'}) => {
        'clienteId': 'c-$nome', 'clienteNome': nome, 'servizi': [], 'operatriceId': 'op1', 'inizio': isoJs(D.combina(k, da)), 'fine': isoJs(D.combina(k, a)), 'stato': stato, 'archiviato': false,
      };

  group('PIN', () {
    test('impostato, verificato, rimosso; non finisce nei backup', () async {
      final d = await datiDiProva();
      expect(pinImpostato(d), isFalse);
      expect(pinValido('123'), isFalse);
      expect(pinValido('123456789'), isFalse);
      expect(pinValido('2580'), isTrue);
      await impostaPin(d, '2580');
      expect(pinImpostato(d), isTrue);
      expect(cifrePin(d), 4);
      expect(await verificaPin(d, '2580'), isTrue);
      expect(await verificaPin(d, '0852'), isFalse);
      // il PIN è solo di questo dispositivo
      final b = jsonDecode(utf8.decode(await creaBackup(d, conFoto: false)));
      expect((b['dati']['meta'] as List).any((m) => m['id'] == 'pin'), isFalse);
      await impostaBiometria(d, true);
      expect(biometriaAttiva(d), isTrue);
      // cambiare PIN conserva la scelta della biometria
      await impostaPin(d, '135790');
      expect(cifrePin(d), 6);
      expect(biometriaAttiva(d), isTrue);
      await rimuoviPin(d);
      expect(pinImpostato(d), isFalse);
      expect(biometriaAttiva(d), isFalse);
    });
  });

  group('notifiche', () {
    test('riepilogo la sera prima, solo per appuntamenti attivi', () async {
      final d = await datiDiProva();
      final lun = D.aggiungiGiorniKey(mar, -1);
      await d.salva('appuntamenti', app(mar, '10:00', '11:00'));
      await d.salva('appuntamenti', app(mar, '09:00', '09:30', stato: 'annullato', nome: 'Bea'));
      await d.salva('appuntamenti', app(mar, '15:00', '16:00', nome: 'Carla'));
      final n = calcolaNotifiche(d, ora: D.combina(lun, '08:00'));
      final r = n.where((x) => x.payload == 'oggi').toList();
      expect(r.first.quando, D.combina(lun, '19:30'));
      expect(r.first.titolo, 'Domani: 2 appuntamenti');
      expect(r.first.testo, contains('10:00'));
      expect(r.first.testo, contains('2 promemoria WhatsApp'));
      // dopo l'orario del riepilogo non si programma più per quella sera
      final tardi = calcolaNotifiche(d, ora: D.combina(lun, '20:00'));
      expect(tardi.where((x) => x.payload == 'oggi'), isEmpty);
    });

    test('avviso prima dell\'appuntamento, appunti e opzioni spente', () async {
      final d = await datiDiProva();
      final a = await d.salva('appuntamenti', app(mar, '10:00', '11:00'));
      await d.salva('appunti', {'titolo': 'Chiamare il fornitore', 'promemoria': mar, 'fatto': false});
      await d.salva('appunti', {'titolo': 'Già fatto', 'promemoria': mar, 'fatto': true});
      final c = clonaDoc(d.cfg);
      c['notifiche'] = {...comeDoc(c['notifiche']), 'primaAppuntamento': 30, 'oraPromemoria': '08:30'};
      await d.salvaConfig(c);
      final ora = D.combina(D.aggiungiGiorniKey(mar, -1), '12:00');
      final n = calcolaNotifiche(d, ora: ora);
      final prima = n.singleWhere((x) => x.payload == 'appuntamento:${a['id']}');
      expect(prima.quando, D.combina(mar, '09:30'));
      final promemoria = n.where((x) => x.payload.startsWith('appunto:')).toList();
      expect(promemoria.single.titolo, 'Promemoria');
      expect(promemoria.single.testo, 'Chiamare il fornitore');
      expect(promemoria.single.quando, D.combina(mar, '08:30'));
      // id univoci e mai nel passato
      expect(n.map((x) => x.id).toSet().length, n.length);
      expect(n.every((x) => x.quando.isAfter(ora)), isTrue);

      c['notifiche'] = {'riepilogoSerale': false, 'promemoriaAppunti': false, 'primaAppuntamento': 0, 'magazzino': false};
      await d.salvaConfig(c);
      expect(calcolaNotifiche(d, ora: ora), isEmpty);
    });

    test('cambio dell\'ora: il riepilogo resta alle 19:30 ora italiana', () async {
      final d = await datiDiProva();
      // domenica 27/10/2030 è il cambio dell'ora; lunedì chiuso, martedì 29 aperto
      await d.salva('appuntamenti', app('2030-10-29', '10:00', '11:00'));
      final n = calcolaNotifiche(d, ora: D.combina('2030-10-26', '09:00'), giorni: 5);
      final r = n.singleWhere((x) => x.payload == 'oggi');
      expect(D.key(r.quando), '2030-10-28');
      expect(D.hhmm(r.quando), '19:30');
    });
  });

  group('punti di ripristino', () {
    test('copia giornaliera una volta al giorno, ripristino e copia "prima"', () async {
      final d = await datiDiProva();
      expect(await copiaGiornaliera(d), isFalse, reason: 'archivio vuoto: niente da copiare');
      final cli = await d.salva('clienti', {'nome': 'Anna', 'cognome': 'Rossi'});
      expect(await copiaGiornaliera(d), isTrue);
      expect(await copiaGiornaliera(d), isFalse, reason: 'già fatta oggi');
      final copie = await elencoCopie();
      expect(copie.single['motivo'], 'giornaliera');
      expect(comeDoc(copie.single['conteggi'])['clienti'], 1);

      // errore: la cliente viene cancellata, poi si torna alla copia
      await d.elimina('clienti', comeStr(cli['id']));
      await d.salva('clienti', {'nome': 'Bea'});
      expect(await ripristinaCopia(d, comeStr(copie.single['id'])), isTrue);
      expect(d.elenco('clienti').map((c) => c['nome']), ['Anna']);
      expect(d.cfg['attivita']['nome'], 'Nails Test', reason: 'anche la configurazione torna');
      // prima del ripristino è stata salvata la situazione di allora (con Bea)
      final dopo = await elencoCopie();
      final p = dopo.firstWhere((c) => c['motivo'] == 'prima');
      expect(comeDoc(p['conteggi'])['clienti'], 1);
      expect(await ripristinaCopia(d, comeStr(p['id'])), isTrue);
      expect(d.elenco('clienti').map((c) => c['nome']), ['Bea']);
    });

    test('si tengono solo le ultime copie per motivo; i dati locali restano', () async {
      final d = await datiDiProva();
      await d.salva('clienti', {'nome': 'Anna'});
      await impostaPin(d, '2580');
      for (var i = 0; i < 9; i++) {
        await creaCopia(d, 'giornaliera', ora: DateTime(2030, 1, 1 + i, 12));
      }
      for (var i = 0; i < 7; i++) {
        await creaCopia(d, 'manuale', ora: DateTime(2030, 2, 1, 10, i));
      }
      final c = await elencoCopie();
      expect(c.where((x) => x['motivo'] == 'giornaliera').length, maxCopie['giornaliera']);
      expect(c.where((x) => x['motivo'] == 'manuale').length, maxCopie['manuale']);
      // restano le più recenti
      expect(c.where((x) => x['motivo'] == 'giornaliera').last['giorno'], '2030-01-03');
      // il PIN (dato locale) non è nella copia e sopravvive al ripristino
      final dati = await archivioCopie.dati(comeStr(c.first['id']));
      expect((dati!['meta'] as List).any((m) => m['id'] == 'pin'), isFalse);
      await ripristinaCopia(d, comeStr(c.first['id']));
      expect(pinImpostato(d), isTrue);
    });
  });

  group('widget e aggiornamenti', () {
    test('widget: un testo per ogni giorno, annullati esclusi, righe in eccesso riassunte', () async {
      final d = await datiDiProva();
      for (var h = 9; h < 16; h++) {
        await d.salva('appuntamenti', app(mar, '${D.p2(h)}:00', '${D.p2(h)}:45', nome: 'C$h'));
      }
      await d.salva('appuntamenti', app(mar, '16:00', '17:00', stato: 'annullato', nome: 'Via'));
      final w = datiWidget(d, ora: D.combina(D.aggiungiGiorniKey(mar, -1), '18:00'));
      expect(w.length, 7);
      expect(w.keys.first, D.aggiungiGiorniKey(mar, -1));
      expect(w[D.aggiungiGiorniKey(mar, -1)]!['sottotitolo'], 'Nessun appuntamento');
      final g = w[mar]!;
      expect(g['sottotitolo'], '7 appuntamenti');
      final righe = (g['righe'] as List).cast<String>();
      expect(righe.length, 5);
      expect(righe.first, startsWith('09:00  C9'));
      expect(righe.last, 'e altri 3…');
      expect(righe.any((r) => r.contains('Via')), isFalse);
    });

    test('versione.json: letta solo se valida', () {
      final v = VersioneDisponibile.da({'build': 142, 'versione': '1.1.0', 'apk': 'https://github.com/x/y/releases/download/a/agenda-android.apk', 'data': '2026-10-10T15:00:00Z'});
      expect(v!.build, 142);
      expect(v.data, isNotNull);
      expect(VersioneDisponibile.da({'build': 'x', 'apk': 'https://a'}), isNull);
      expect(VersioneDisponibile.da({'build': 3, 'apk': 'http://non-sicuro'}), isNull);
    });
  });
}
