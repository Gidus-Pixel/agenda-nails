import 'package:agenda_nails/core/date.dart';
import 'package:agenda_nails/core/util.dart';
import 'package:agenda_nails/dominio/agenda.dart';
import 'package:agenda_nails/dominio/appunti.dart';
import 'package:agenda_nails/dominio/demo.dart';
import 'package:agenda_nails/dominio/magazzino.dart';
import 'package:agenda_nails/dominio/report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'aiuto.dart';

void main() {
  setUpAll(() => initializeDateFormatting('it'));

  test('quantità: 3 decimali, interi restano interi, formato italiano', () {
    expect(qta(0.1 + 0.2), 0.3);
    expect(qta(2.0), 2);
    expect(qta(2.0) is int, isTrue);
    expect(fmtQta(1.5, 'ml'), '1,5 ml');
    expect(qtaDaTesto('0,25'), 0.25);
    expect(qtaDaTesto('x'), isNull);
  });

  test('la giacenza è la somma dei movimenti (con segno dal tipo)', () async {
    final d = await datiDiProva();
    final p = await d.salva('prodotti', {...prodottoVuoto(), 'nome': 'Gel', 'unita': 'ml', 'scortaMinima': 5});
    final id = comeStr(p['id']);
    await registraMovimento(d, prodottoId: id, tipo: 'carico', quantita: 10);
    await registraMovimento(d, prodottoId: id, tipo: 'consumo', quantita: 2.5);
    await registraMovimento(d, prodottoId: id, tipo: 'vendita', quantita: 1, importoCent: 900);
    expect(giacenzaDi(d, id), 6.5);
    // rettifica: si salva la differenza tra contato e risultante
    await registraMovimento(d, prodottoId: id, tipo: 'rettifica', quantita: qta(4 - giacenzaDi(d, id)), nota: 'inventario');
    expect(giacenzaDi(d, id), 4);
    expect(mappaGiacenze(d)[id], 4);
    final avv = avvisiMagazzino(d);
    expect(avv.sottoScorta.single.p['id'], id);
    expect(venditeTra(d, D.oggiKey(), D.oggiKey()), 900);
  });

  test('scadenze e PAO (31 gennaio + 1 mese = fine febbraio)', () async {
    expect(scadenzaPAO({'dataApertura': '2027-01-31', 'paoMesi': 1}), '2027-02-28');
    expect(scadenzaPAO({'dataApertura': '2026-10-07', 'paoMesi': 12}), '2027-10-07');
    expect(scadenzaPAO({'dataApertura': '', 'paoMesi': 12}), isNull);
    final d = await datiDiProva();
    final oggi = D.oggiKey();
    final a = await d.salva('prodotti', {...prodottoVuoto(), 'nome': 'Top', 'scadenza': D.aggiungiGiorniKey(oggi, 10)});
    final b = await d.salva('prodotti', {...prodottoVuoto(), 'nome': 'Base', 'dataApertura': D.aggiungiGiorniKey(oggi, -400), 'paoMesi': 12});
    for (final p in [a, b]) {
      await registraMovimento(d, prodottoId: comeStr(p['id']), tipo: 'carico', quantita: 1);
    }
    final avv = avvisiMagazzino(d);
    expect(avv.inScadenza.single.p['nome'], 'Top');
    expect(avv.paoSuperato.single.p['nome'], 'Base');
  });

  test('riordino dai sotto scorta e ricevimento con carico automatico', () async {
    final d = await datiDiProva();
    final f = await d.salva('fornitori', {...fornitoreVuoto(), 'ragioneSociale': 'Fornitore', 'speseSpedizioneCent': 500});
    final p = await d.salva('prodotti', {...prodottoVuoto(), 'nome': 'Lime', 'scortaMinima': 10, 'costoCent': 45, 'fornitoreId': f['id']});
    final id = comeStr(p['id']);
    await registraMovimento(d, prodottoId: id, tipo: 'carico', quantita: 4);
    final r = proposteRiordino(d);
    expect(r.gruppi[f['id']]!.single.q, 16); // 2 × 10 − 4
    final creati = await creaBozzeRiordino(d, r.gruppi);
    expect(creati.single['speseSpedizioneCent'], 500);
    expect(totaleOrdine(creati.single), 16 * 45 + 500);
    expect(proposteRiordino(d).gruppi, isEmpty); // già in un ordine aperto
    expect(proposteRiordino(d).giaInOrdine, 1);

    final o = creati.single..['stato'] = 'inviato';
    await d.salva('ordini_fornitore', o);
    final parz = await riceviOrdine(d, o, {0: (quantita: 6, lotto: 'L1', scadenza: '')});
    expect(o['stato'], 'parziale');
    expect(giacenzaDi(d, id), 10);
    expect(d.get('prodotti', id)!['lotto'], 'L1');
    expect(spesaOrdine(o), 6 * 45 + 500);
    await riceviOrdine(d, o, {0: (quantita: 10, lotto: '', scadenza: '')});
    expect(o['stato'], 'ricevuto');
    expect(giacenzaDi(d, id), 20);
    expect(parz.movimenti.single['riferimento'], {'tipo': 'ordine', 'id': o['id']});
    expect(testoOrdine(d, o, f), contains('16 × Lime'));
  });

  test('consumi della scheda lavoro: ricalcolati a ogni salvataggio', () async {
    final d = await datiDiProva();
    final p = await d.salva('prodotti', {...prodottoVuoto(), 'nome': 'Gel', 'unita': 'ml'});
    final s = await d.salva('servizi', {'nome': 'Refill', 'durata': 90, 'prezzoCent': 4000, 'prodottiDefault': [{'prodottoId': p['id'], 'quantita': 2}], 'archiviato': false});
    final proposti = prodottiDaServizi(d, [{'servizioId': s['id'], 'quantita': 2}]);
    expect(proposti.single['quantita'], 4);
    final scheda = {'id': 'sc1', 'data': '2026-10-07', 'ora': '10:00', 'prodotti': [{...proposti.single, 'quantita': '4'}]};
    final c1 = consumiScheda(d, scheda, 'Anna');
    expect(c1.precedenti, isEmpty);
    await d.salvaMolti('movimenti_magazzino', c1.nuovi);
    expect(giacenzaDi(d, comeStr(p['id'])), -4);
    final c2 = consumiScheda(d, {...scheda, 'prodotti': [{...proposti.single, 'quantita': '3'}]}, 'Anna');
    expect(c2.precedenti.length, 1);
    expect(c2.nuovi.single['quantita'], -3);
  });

  test('appunti: promemoria, ordinamento, ricerca', () async {
    final d = await datiDiProva();
    final oggi = D.oggiKey();
    await d.salva('appunti', {...appuntoVuoto(), 'titolo': 'Ordinare top', 'promemoria': D.aggiungiGiorniKey(oggi, -1)});
    await d.salva('appunti', {...appuntoVuoto(), 'titolo': 'Fissato', 'fissato': true, 'tag': ['idee']});
    await d.salva('appunti', {...appuntoVuoto(), 'titolo': 'Fatto', 'promemoria': oggi, 'fatto': true});
    expect(promemoriaInArrivo(d).single['titolo'], 'Ordinare top');
    expect(statoPromemoria(promemoriaInArrivo(d).single)!.$2, 'pericolo');
    expect(ordinaAppunti(d.elenco('appunti')).first['titolo'], 'Fissato');
    expect(appuntoCorrisponde(d.elenco('appunti').firstWhere((a) => a['titolo'] == 'Fissato'), 'idee fiss'), isTrue);
  });

  test('report con i dati di prova e CSV per Excel', () async {
    final d = await datiDiProva();
    await caricaDatiDemo(d);
    final oggi = D.oggiKey();
    final r = calcolaReport(d, D.aggiungiGiorniKey(oggi, -60), oggi);
    expect(r.gruppo, 'settimana');
    expect(r.visite, greaterThan(0));
    expect(r.totServizi, r.chiavi.fold<int>(0, (t, k) => t + r.perGruppo[k]!.servizi));
    expect(r.totVendite, 900);
    expect(r.completati, greaterThan(0));
    expect(r.consumi, isNotEmpty);
    final tab = tabellaCsv(r, 'servizi');
    final csv = String.fromCharCodes(creaCsv(tab.intestazioni, tab.righe));
    expect(csv.startsWith('ï»¿'), isTrue); // BOM UTF-8
    expect(csv, contains('Servizio;Volte;'));
    expect(csvCampo('a;b'), '"a;b"');
    expect(csvCampo(1.5), '1,5');
    expect(periodoReport('mesescorso', ora: DateTime(2026, 3, 15)), ('2026-02-01', '2026-02-28'));
    expect(chiaviPeriodo('2026-10-01', '2026-10-31', 'settimana').first, '2026-09-28');
  });
}
