import '../core/config.dart';
import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import 'agenda.dart';

bool ciSonoDatiDemo(Dati d) => ['clienti', 'appuntamenti', 'servizi', 'schede_lavoro', 'blocchi'].any((c) => d.elenco(c, archiviati: true).any((r) => r['demo'] == true));

/// Dati di prova, tutti segnati `demo: true` (stessa logica della web app).
Future<void> caricaDatiDemo(Dati d, {bool configura = false}) async {
  if (ciSonoDatiDemo(d)) return;
  await d.inBlocco(() async {
    if (configura && d.cfg['orari'] is! Map) {
      final c = clonaDoc(d.cfg);
      c['attivita'] = {...comeDoc(c['attivita']), 'nome': comeStr(comeDoc(c['attivita'])['nome']).isEmpty ? 'Studio Unghie Prova' : comeDoc(c['attivita'])['nome'], 'titolare': comeStr(comeDoc(c['attivita'])['titolare']).isEmpty ? 'Giulia' : comeDoc(c['attivita'])['titolare']};
      c['orari'] = {
        'lun': [], 'dom': [],
        for (final g in ['mar', 'mer', 'gio', 'ven']) g: [['09:00', '13:00'], ['14:30', '19:30']],
        'sab': [['09:00', '14:00']],
      };
      await d.salvaConfig(c);
    }
    var servizi = serviziAttivi(d);
    if (servizi.isEmpty) {
      const base = [
        ('Ricostruzione gel', 'Ricostruzione', 120, 5500, 21), ('Refill gel', 'Ricostruzione', 90, 4000, 21),
        ('Semipermanente mani', 'Semipermanente', 45, 2500, 14), ('Manicure', 'Manicure', 30, 1500, 0),
        ('Pedicure estetica', 'Pedicure', 50, 3000, 30), ('Rimozione', 'Rimozione', 20, 1000, 0), ('Nail art (per unghia)', 'Nail art', 5, 200, 0),
      ];
      final nuovi = <Doc>[];
      for (var i = 0; i < base.length; i++) {
        final b = base[i];
        nuovi.add({'nome': b.$1, 'categoria': b.$2, 'durata': b.$3, 'prezzoCent': b.$4, 'richiamoGiorni': b.$5 == 0 ? null : b.$5, 'cuscinetto': null, 'colore': esadecimale(paletteServizi[i % paletteServizi.length]), 'prodottiDefault': [], 'ordine': i, 'demo': true, 'archiviato': false});
      }
      await d.salvaMolti('servizi', nuovi);
      servizi = serviziAttivi(d);
    }
    Doc sv(int i) {
      final s = servizi[i % servizi.length];
      return {'servizioId': s['id'], 'nome': s['nome'], 'durata': s['durata'], 'prezzoCent': s['prezzoCent'], 'quantita': 1, 'colore': s['colore'], 'richiamoGiorni': s['richiamoGiorni']};
    }

    final oggi = D.oggiKey();
    Doc cons(bool sanitari) => {
          'privacy': {'dato': true, 'data': oggi}, 'sanitari': {'dato': sanitari, 'data': sanitari ? oggi : ''},
          'foto': {'dato': true, 'data': oggi}, 'marketing': {'dato': false, 'data': ''},
        };
    const nomi = ['Anna', 'Beatrice', 'Chiara', 'Daniela', 'Elena', 'Federica', 'Giorgia', 'Ilaria'];
    final clienti = <Doc>[];
    for (var i = 0; i < nomi.length; i++) {
      clienti.add({
        ...nuovaClienteVuota(nome: nomi[i], cognome: 'Prova', telefono: '+3933300000${D.p2(i + 1)}'),
        'consensi': cons(i == 1),
        'avvertenze': i == 1 ? 'DATO DI PROVA — reazione cutanea a un primer acido' : '',
        'preferenze': {'forma': forme[i % forme.length], 'lunghezza': lunghezze[(i + 1) % lunghezze.length], 'colori': i.isOdd ? 'nude rosati' : 'rossi', 'tecnica': tecniche[i % 3]},
        'tag': i < 3 ? ['abituale'] : <String>[],
        'demo': true,
      });
    }
    await d.salvaMolti('clienti', clienti);

    List<List<String>> orariGiorno(String k) {
      final o = d.cfg['orari'];
      final g = D.giornoKey(D.daKey(k));
      if (o is Map) return (o[g] as List? ?? const []).whereType<List>().map((x) => [comeStr(x[0]), comeStr(x[1])]).toList();
      return D.daKey(k).weekday == 7 ? [] : [['09:00', '13:00'], ['14:30', '19:00']];
    }

    final app = <Doc>[], schede = <Doc>[];
    var ci = 0;
    final op = comeStr(d.operatrici.first['id']);
    for (var g = -35; g <= 10; g++) {
      final k = D.aggiungiGiorniKey(oggi, g);
      final iv = orariGiorno(k);
      if (iv.isEmpty || (g < 0 && g % 4 != 0)) continue;
      final s1 = sv(ci + 1);
      final ini = D.combina(k, iv[0][0]);
      final cli = clienti[ci % (clienti.length - 1)];
      ci++;
      final passato = g < 0;
      final a = <String, dynamic>{
        'id': uid(), 'clienteId': cli['id'], 'clienteNome': nomeCliente(cli), 'servizi': [s1], 'operatriceId': op,
        'inizio': isoJs(ini), 'fine': isoJs(D.aggiungiMinuti(ini, comeInt(s1['durata'])!)),
        'stato': passato ? (g == -8 ? 'non_presentata' : 'completato') : (g.isOdd ? 'confermato' : 'prenotato'),
        'prezzoTotaleCent': s1['prezzoCent'], 'accontoCent': g == 2 ? 1000 : 0, 'note': '', 'demo': true, 'archiviato': false, 'schedaId': null,
      };
      if (a['stato'] == 'completato') {
        final p = comeDoc(cli['preferenze']);
        final sc = {
          'id': uid(), 'appuntamentoId': a['id'], 'clienteId': cli['id'], 'data': k, 'ora': iv[0][0], 'servizi': [s1],
          'tecnica': p['tecnica'], 'forma': p['forma'], 'lunghezza': p['lunghezza'], 'colori': 'Codice di prova 012', 'prodotti': [],
          'durataRealeMin': s1['durata'], 'importoCent': s1['prezzoCent'], 'metodoPagamento': 'Contanti', 'note': '',
          'noteProssimaVolta': g == -4 ? 'Dato di prova: provare forma più corta' : '', 'fotoIds': [], 'demo': true, 'archiviato': false,
        };
        a['schedaId'] = sc['id'];
        schede.add(sc);
      }
      app.add(a);
      if (!passato && iv.length > 1) {
        final s2 = sv(ci + 2);
        final i2 = D.combina(k, iv[1][0]);
        final cli2 = clienti[ci % (clienti.length - 1)];
        ci++;
        app.add({
          'id': uid(), 'clienteId': cli2['id'], 'clienteNome': nomeCliente(cli2), 'servizi': [s2], 'operatriceId': op,
          'inizio': isoJs(i2), 'fine': isoJs(D.aggiungiMinuti(i2, comeInt(s2['durata'])!)), 'stato': 'prenotato',
          'prezzoTotaleCent': s2['prezzoCent'], 'accontoCent': 0, 'note': '', 'demo': true, 'archiviato': false, 'schedaId': null,
        });
        // terzo appuntamento a metà mattina, per riempire l'agenda
        final s3 = sv(ci + 3);
        final i3 = D.aggiungiMinuti(D.combina(k, iv[0][0]), (comeInt(s1['durata']) ?? 60) + 15);
        final cli3 = clienti[(ci + 3) % (clienti.length - 1)];
        app.add({
          'id': uid(), 'clienteId': cli3['id'], 'clienteNome': nomeCliente(cli3), 'servizi': [s3], 'operatriceId': op,
          'inizio': isoJs(i3), 'fine': isoJs(D.aggiungiMinuti(i3, comeInt(s3['durata'])!)), 'stato': g.isEven ? 'confermato' : 'prenotato',
          'prezzoTotaleCent': s3['prezzoCent'], 'accontoCent': 0, 'note': '', 'demo': true, 'archiviato': false, 'schedaId': null,
        });
      }
    }
    // una cliente con l'ultima visita ~30 giorni fa → "Da ricontattare"
    final conRichiamo = servizi.firstWhere((x) => (comeInt(x['richiamoGiorni']) ?? 0) > 0, orElse: () => servizi.first);
    final cr = clienti.last;
    final kr = D.aggiungiGiorniKey(oggi, -30);
    final svr = {'servizioId': conRichiamo['id'], 'nome': conRichiamo['nome'], 'durata': conRichiamo['durata'], 'prezzoCent': conRichiamo['prezzoCent'], 'quantita': 1, 'colore': conRichiamo['colore'], 'richiamoGiorni': conRichiamo['richiamoGiorni']};
    final ir = D.combina(kr, '10:00');
    final idA = uid(), idS = uid();
    app.add({'id': idA, 'clienteId': cr['id'], 'clienteNome': nomeCliente(cr), 'servizi': [svr], 'operatriceId': op, 'inizio': isoJs(ir), 'fine': isoJs(D.aggiungiMinuti(ir, comeInt(svr['durata'])!)), 'stato': 'completato', 'prezzoTotaleCent': svr['prezzoCent'], 'accontoCent': 0, 'note': '', 'demo': true, 'archiviato': false, 'schedaId': idS});
    schede.add({'id': idS, 'appuntamentoId': idA, 'clienteId': cr['id'], 'data': kr, 'ora': '10:00', 'servizi': [svr], 'colori': 'Codice di prova 045', 'prodotti': [], 'importoCent': svr['prezzoCent'], 'metodoPagamento': 'Carta / Bancomat', 'fotoIds': [], 'demo': true, 'archiviato': false});
    await d.salvaMolti('appuntamenti', app);
    await d.salvaMolti('schede_lavoro', schede);
    final kb = D.aggiungiGiorniKey(oggi, 3);
    await d.salva('blocchi', {'tipo': 'personale', 'titolo': 'Impegno di prova', 'inizio': isoJs(D.combina(kb, '16:00')), 'fine': isoJs(D.combina(kb, '17:00')), 'tuttoIlGiorno': false, 'ricorrenza': null, 'operatriceId': null, 'demo': true, 'archiviato': false});
  });
}

Future<void> rimuoviDatiDemo(Dati d) async {
  final cliDemo = d.elenco('clienti', archiviati: true).where((c) => c['demo'] == true).map((c) => c['id']).toSet();
  bool via(Doc r) => r['demo'] == true || (r['clienteId'] != null && cliDemo.contains(r['clienteId']));
  await d.inBlocco(() async {
    for (final c in ['clienti', 'appuntamenti', 'schede_lavoro', 'foto', 'blocchi', 'servizi', 'prodotti', 'movimenti_magazzino', 'fornitori', 'ordini_fornitore', 'appunti']) {
      final ids = d.elenco(c, archiviati: true).where(via).map((r) => comeStr(r['id'])).toList();
      await d.eliminaMolti(c, ids);
    }
  });
}
