import 'package:agenda_nails/core/date.dart';
import 'package:agenda_nails/core/util.dart';
import 'package:agenda_nails/dominio/agenda.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'aiuto.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));
  // un martedì lontano nel futuro, per non avere l'avviso "nel passato"
  const mar = '2030-10-01';

  Map<String, dynamic> app(String k, String da, String a, {String stato = 'prenotato', String nome = 'Anna'}) => {
        'clienteId': 'c-$nome', 'clienteNome': nome, 'servizi': [], 'operatriceId': 'op1', 'inizio': isoJs(D.combina(k, da)), 'fine': isoJs(D.combina(k, a)), 'stato': stato, 'archiviato': false,
      };

  test('slot libero dentro l\'orario: nessun problema', () async {
    final d = await datiDiProva();
    expect(D.giornoKey(D.daKey(mar)), 'mar');
    expect(controllaSlot(d, inizio: D.combina(mar, '10:00'), fine: D.combina(mar, '11:00')), isEmpty);
  });

  test('giorno di chiusura, fuori orario, pausa', () async {
    final d = await datiDiProva();
    final lun = D.aggiungiGiorniKey(mar, -1);
    expect(controllaSlot(d, inizio: D.combina(lun, '10:00'), fine: D.combina(lun, '11:00')).single.msg, contains('chiusura'));
    expect(controllaSlot(d, inizio: D.combina(mar, '19:00'), fine: D.combina(mar, '20:00')).single.msg, contains('Fuori'));
    expect(controllaSlot(d, inizio: D.combina(mar, '12:30'), fine: D.combina(mar, '15:00')).single.msg, contains('a cavallo della pausa'));
    expect(controllaSlot(d, inizio: D.combina(mar, '13:30'), fine: D.combina(mar, '14:00')).single.msg, contains('cade nella pausa'));
  });

  test('sovrapposizione e tempo di pulizia', () async {
    final d = await datiDiProva();
    await d.salva('appuntamenti', app(mar, '10:00', '11:00'));
    final sovr = controllaSlot(d, inizio: D.combina(mar, '10:30'), fine: D.combina(mar, '11:30'));
    expect(sovr.map((p) => p.tipo), contains('sovrapposizione'));
    final cusc = controllaSlot(d, inizio: D.combina(mar, '11:05'), fine: D.combina(mar, '12:00'));
    expect(cusc.single.tipo, 'cuscinetto');
    expect(controllaSlot(d, inizio: D.combina(mar, '11:10'), fine: D.combina(mar, '12:00')), isEmpty);
    // gli annullati non contano
    await d.salva('appuntamenti', app(mar, '15:00', '16:00', stato: 'annullato', nome: 'Bea'));
    expect(controllaSlot(d, inizio: D.combina(mar, '15:00'), fine: D.combina(mar, '16:00')), isEmpty);
  });

  test('blocchi singoli e ricorrenti', () async {
    final d = await datiDiProva();
    await d.salva('blocchi', {'tipo': 'personale', 'inizio': isoJs(D.combina(mar, '16:00')), 'fine': isoJs(D.combina(mar, '17:00')), 'archiviato': false});
    await d.salva('blocchi', {'tipo': 'pausa', 'ricorrenza': {'giorni': [3], 'oraInizio': '11:00', 'oraFine': '11:30', 'dal': '2030-01-01', 'al': null}, 'archiviato': false});
    expect(controllaSlot(d, inizio: D.combina(mar, '16:30'), fine: D.combina(mar, '17:30')).single.tipo, 'blocco');
    final mer = D.aggiungiGiorniKey(mar, 1);
    expect(controllaSlot(d, inizio: D.combina(mer, '11:00'), fine: D.combina(mer, '12:00')).single.tipo, 'blocco');
    expect(controllaSlot(d, inizio: D.combina(mar, '11:00'), fine: D.combina(mar, '12:00')), isEmpty);
  });

  test('cambio dell\'ora: un appuntamento il 25/10 resta alle 10:00', () async {
    final d = await datiDiProva();
    final a = await d.salva('appuntamenti', app('2026-10-24', '10:00', '11:00'));
    final i = inizioApp(a);
    final spostato = D.combina(D.aggiungiGiorniKey(D.key(i), 1), D.hhmm(i));
    expect(D.hhmm(spostato), '10:00');
    expect(D.key(spostato), '2026-10-25');
    expect(D.minutiTra(spostato, D.aggiungiMinuti(spostato, 60)), 60);
  });

  test('primo spazio libero', () async {
    final d = await datiDiProva();
    final r = trovaSlotLiberi(d, durataMin: 60, da: D.combina(mar, '00:00'), quanti: 3);
    expect(r.errore, isNull);
    expect(D.key(r.slot.first), mar);
    expect(D.hhmm(r.slot.first), '09:00');
    await d.salva('appuntamenti', app(mar, '09:00', '12:00'));
    final r2 = trovaSlotLiberi(d, durataMin: 60, da: D.combina(mar, '00:00'), quanti: 1);
    expect(D.hhmm(r2.slot.first), '14:30'); // 12:00+10 di pulizia lascia solo 50 min prima della pausa
    final senza = await datiDiProva(orari: false);
    expect(trovaSlotLiberi(senza, durataMin: 60).errore, isNotNull);
  });

  test('da ricontattare dopo l\'intervallo di richiamo', () async {
    final d = await datiDiProva();
    final c = await d.salva('clienti', nuovaClienteVuota(nome: 'Chiara'));
    final k = D.aggiungiGiorniKey(D.oggiKey(), -30);
    await d.salva('schede_lavoro', {'clienteId': c['id'], 'data': k, 'servizi': [{'nome': 'Refill', 'richiamoGiorni': 21}], 'importoCent': 4000, 'archiviato': false});
    final r = clientiDaRicontattare(d);
    expect(r.single.cliente['id'], c['id']);
    expect(r.single.ritardo, 9);
    final st = statisticheCliente(d, comeStr(c['id']));
    expect(st.visite, 1);
    expect(st.spesaCent, 4000);
  });
}
