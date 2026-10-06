import '../core/config.dart';
import '../core/date.dart';
import '../core/telefono.dart';
import '../core/util.dart';
import '../dati/dati.dart';

/* =====================================================================================
   MAGAZZINO — come la web app: la giacenza NON è un campo salvato, è sempre la somma
   dei movimenti. Ogni movimento ha la quantità già con il segno (+ entra, − esce;
   la rettifica salva la differenza tra quanto contato e quanto risultava).
   ===================================================================================== */

/// Quantità di magazzino con al massimo 3 decimali (i numeri interi restano interi, come in JS).
num qta(num? n) {
  final r = ((n ?? 0) * 1000).round() / 1000;
  return r == r.roundToDouble() && r.abs() < 1e15 ? r.toInt() : r;
}

num numero(dynamic v) => comeDouble(v) ?? 0;

/// "1,5 ml"
String fmtQta(dynamic n, [String? u]) {
  final v = qta(numero(n));
  return '${v.toString().replaceAll('.', ',')} ${unita[u] ?? u ?? 'pz'}'.trim();
}

/// Testo di una quantità per un campo (senza unità).
String testoQta(dynamic n) => n == null || n == '' ? '' : qta(numero(n)).toString().replaceAll('.', ',');

/// "1,5" → 1.5; testo non valido → null
num? qtaDaTesto(String? s) {
  final t = (s ?? '').trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final n = double.tryParse(t);
  return n == null || !n.isFinite ? null : qta(n);
}

String nomeProdotto(Doc? p) {
  if (p == null) return 'Prodotto';
  return [comeStr(p['nome']), if (comeStr(p['codiceColore']).isNotEmpty) '(${p['codiceColore']})'].where((x) => x.isNotEmpty).join(' ');
}

String nomeProdottoConMarca(Doc p) => nomeProdotto(p) + (comeStr(p['marca']).isNotEmpty ? ' — ${p['marca']}' : '');
String descrProdotto(Doc p) => [comeStr(p['marca']), comeStr(p['linea'])].where((x) => x.isNotEmpty).join(' · ');
String nomeFornitore(Doc? f) => f == null ? '' : (comeStr(f['ragioneSociale']).isEmpty ? 'Fornitore senza nome' : comeStr(f['ragioneSociale']));

Map<String, num> mappaGiacenze(Dati d) {
  final m = <String, num>{};
  for (final x in d.elenco('movimenti_magazzino', archiviati: true)) {
    final id = comeStr(x['prodottoId']);
    m[id] = qta((m[id] ?? 0) + numero(x['quantita']));
  }
  return m;
}

num giacenzaDi(Dati d, String prodottoId) =>
    qta(d.elenco('movimenti_magazzino', archiviati: true).where((x) => x['prodottoId'] == prodottoId).fold<num>(0, (t, x) => t + numero(x['quantita'])));

List<Doc> movimentiDi(Dati d, String prodottoId) =>
    d.elenco('movimenti_magazzino', archiviati: true).where((x) => x['prodottoId'] == prodottoId).toList()..sort((a, b) => comeStr(b['data']).compareTo(comeStr(a['data'])));

List<Doc> prodottiAttivi(Dati d) => d.elenco('prodotti')
  ..sort((a, b) {
    final c = comeStr(a['categoria']).compareTo(comeStr(b['categoria']));
    return c != 0 ? c : norm(nomeProdotto(a)).compareTo(norm(nomeProdotto(b)));
  });

List<Doc> fornitoriAttivi(Dati d) => d.elenco('fornitori')..sort((a, b) => norm(nomeFornitore(a)).compareTo(norm(nomeFornitore(b))));

/// Scadenza del PAO: data di apertura + mesi (chiave AAAA-MM-GG) oppure null.
/// 31 gennaio + 1 mese → ultimo giorno di febbraio, come nella web app.
String? scadenzaPAO(Doc p) {
  final ap = comeStr(p['dataApertura']);
  final mesi = comeInt(p['paoMesi']) ?? 0;
  if (ap.isEmpty || mesi <= 0) return null;
  final d = D.daKey(ap);
  var r = DateTime(d.year, d.month + mesi, d.day);
  if (r.day != d.day) r = DateTime(r.year, r.month, 0);
  return D.key(r);
}

class VoceAvviso {
  VoceAvviso(this.p, this.g, [this.pao]);
  final Doc p;
  final num g;
  final String? pao;
}

class AvvisiMagazzino {
  final sottoScorta = <VoceAvviso>[], inScadenza = <VoceAvviso>[], scaduti = <VoceAvviso>[], paoSuperato = <VoceAvviso>[], negativi = <VoceAvviso>[];
  int get totale => {for (final l in [sottoScorta, inScadenza, scaduti, paoSuperato, negativi]) for (final x in l) x.p['id']}.length;
}

AvvisiMagazzino avvisiMagazzino(Dati d) {
  final gia = mappaGiacenze(d);
  final oggi = D.oggiKey();
  final limite = D.aggiungiGiorniKey(oggi, comeInt(comeDoc(d.cfg['avvisi'])['scadenzaGiorni']) ?? 30);
  final out = AvvisiMagazzino();
  for (final p in d.elenco('prodotti')) {
    final g = gia[comeStr(p['id'])] ?? 0;
    final scorta = numero(p['scortaMinima']);
    if (g < 0) out.negativi.add(VoceAvviso(p, g));
    if (scorta > 0 && g <= scorta) out.sottoScorta.add(VoceAvviso(p, g));
    final sc = comeStr(p['scadenza']);
    if (sc.isNotEmpty && g > 0) {
      if (sc.compareTo(oggi) < 0) {
        out.scaduti.add(VoceAvviso(p, g));
      } else if (sc.compareTo(limite) <= 0) {
        out.inScadenza.add(VoceAvviso(p, g));
      }
    }
    final pao = scadenzaPAO(p);
    if (pao != null && pao.compareTo(oggi) < 0 && g > 0) out.paoSuperato.add(VoceAvviso(p, g, pao));
  }
  return out;
}

/// Valore del magazzino a costo (le giacenze negative contano zero).
int valoreMagazzino(List<Doc> prodotti, Map<String, num> gia) =>
    prodotti.fold<num>(0, (t, p) => t + ((gia[comeStr(p['id'])] ?? 0) < 0 ? 0 : (gia[comeStr(p['id'])] ?? 0)) * (comeInt(p['costoCent']) ?? 0)).round();

/// Etichette di stato del prodotto: (testo, tipo) con tipo pericolo | avviso | info.
List<(String, String)> etichetteProdotto(Dati d, Doc p, num g) {
  final oggi = D.oggiKey();
  final limite = D.aggiungiGiorniKey(oggi, comeInt(comeDoc(d.cfg['avvisi'])['scadenzaGiorni']) ?? 30);
  final out = <(String, String)>[];
  final scorta = numero(p['scortaMinima']);
  if (g < 0) {
    out.add(('giacenza negativa', 'pericolo'));
  } else if (scorta > 0 && g <= scorta) {
    out.add(('sotto scorta', 'avviso'));
  }
  final sc = comeStr(p['scadenza']);
  if (sc.isNotEmpty && g > 0) {
    if (sc.compareTo(oggi) < 0) {
      out.add(('scaduto ${F.dataKey(sc)}', 'pericolo'));
    } else if (sc.compareTo(limite) <= 0) {
      out.add(('scade ${F.dataKey(sc)}', 'avviso'));
    }
  }
  final pao = scadenzaPAO(p);
  if (pao != null && g > 0) out.add(pao.compareTo(oggi) < 0 ? ('PAO superato', 'pericolo') : ('aperto · PAO al ${F.dataKey(pao)}', 'info'));
  if (p['uso'] == 'vendita' || p['uso'] == 'entrambi') out.add(('in vendita', 'info'));
  if (p['demo'] == true) out.add(('PROVA', 'info'));
  return out;
}

/// Nuovo movimento (non ancora salvato). La quantità prende il segno dal tipo.
Doc nuovoMovimento({required String prodottoId, required String tipo, required num quantita, String nota = '', Doc? riferimento, int? costoCent, int? importoCent, String lotto = '', String? data, bool demo = false}) {
  final t = tipiMovimento[tipo];
  if (t == null) throw ArgumentError('Tipo di movimento sconosciuto');
  final q = t.segno == 0 ? qta(quantita) : qta(quantita.abs() * t.segno);
  return {
    'prodottoId': prodottoId, 'tipo': tipo, 'quantita': q, 'data': data ?? adessoIso(), 'nota': nota, 'riferimento': riferimento,
    'costoCent': costoCent, 'importoCent': importoCent, 'lotto': lotto, 'archiviato': false, if (demo) 'demo': true,
  };
}

Future<Doc> registraMovimento(Dati d, {required String prodottoId, required String tipo, required num quantita, String nota = '', Doc? riferimento, int? costoCent, int? importoCent, String lotto = '', String? data, bool demo = false}) =>
    d.salva('movimenti_magazzino', nuovoMovimento(prodottoId: prodottoId, tipo: tipo, quantita: quantita, nota: nota, riferimento: riferimento, costoCent: costoCent, importoCent: importoCent, lotto: lotto, data: data, demo: demo));

Doc prodottoVuoto() => {
      'nome': '', 'marca': '', 'linea': '', 'codiceColore': '', 'categoria': '', 'unita': 'pz', 'scortaMinima': null, 'costoCent': null, 'prezzoVenditaCent': null,
      'uso': 'interno', 'fornitoreId': null, 'codiceFornitore': '', 'lotto': '', 'scadenza': '', 'paoMesi': null, 'dataApertura': '', 'note': '', 'fotoId': null, 'archiviato': false,
    };

/* ================================ FORNITORI E ORDINI ================================ */
Doc fornitoreVuoto() => {
      'ragioneSociale': '', 'piva': '', 'referente': '', 'telefono': '', 'whatsapp': '', 'email': '', 'sito': '', 'indirizzo': '', 'condizioniPagamento': '', 'tempiConsegna': '',
      'minimoOrdineCent': null, 'speseSpedizioneCent': null, 'sconti': '', 'note': '', 'archiviato': false,
    };

int totaleOrdine(Doc o, {bool soloRicevuto = false}) {
  final righe = comeListaDoc(o['righe']).fold<int>(0, (t, r) => t + (numero(soloRicevuto ? r['ricevuta'] : r['quantita']) * (comeInt(r['costoCent']) ?? 0)).round());
  return righe + (comeInt(o['speseSpedizioneCent']) ?? 0);
}

/// Spesa effettiva: quanto ricevuto (ordini ricevuti o ricevuti in parte).
int spesaOrdine(Doc o) => ['ricevuto', 'parziale'].contains(o['stato']) ? totaleOrdine(o, soloRicevuto: true) : 0;
String dataSpesaOrdine(Doc o) => comeStr(o['dataRicezione'] ?? o['dataInvio'] ?? o['dataCreazione']);
String chiaveData(String iso) => iso.isEmpty ? '' : D.key(D.daIso(iso));

Doc rigaOrdineDa(Doc p, {num? quantita}) => {
      'prodottoId': p['id'], 'nome': nomeProdottoConMarca(p), 'codiceFornitore': comeStr(p['codiceFornitore']),
      'quantita': quantita ?? 1, 'costoCent': p['costoCent'], 'ricevuta': 0,
    };

Doc nuovoOrdine({String? fornitoreId, List<Doc>? righe}) => {
      'fornitoreId': fornitoreId, 'righe': righe ?? <Doc>[], 'stato': 'bozza', 'dataCreazione': adessoIso(), 'dataInvio': null, 'dataRicezione': null,
      'speseSpedizioneCent': null, 'note': '', 'archiviato': false,
    };

/// Testo pronto da inviare al fornitore (WhatsApp / email).
String testoOrdine(Dati d, Doc o, Doc? forn) {
  final att = comeDoc(d.cfg['attivita']);
  final righe = comeListaDoc(o['righe']).where((r) => numero(r['quantita']) > 0).map((r) => '• ${testoQta(r['quantita'])} × ${r['nome']}${comeStr(r['codiceFornitore']).isNotEmpty ? ' (cod. ${r['codiceFornitore']})' : ''}');
  final firma = [comeStr(att['nome']), comeStr(att['titolare']), comeStr(att['telefono'])].where((x) => x.isNotEmpty).join(' — ');
  return [
    compilaModello(comeStr(d.cfg['messaggiOrdine']).isEmpty ? 'Buongiorno, vorrei ordinare quanto segue per {attivita}:' : comeStr(d.cfg['messaggiOrdine']), {'attivita': comeStr(att['nome']), 'fornitore': nomeFornitore(forn), 'referente': comeStr(forn?['referente'])}),
    '', ...righe, '',
    if (comeStr(o['note']).isNotEmpty) 'Note: ${o['note']}',
    if (firma.isNotEmpty) firma,
    'Grazie!',
  ].join('\n');
}

/// Prodotti già in un ordine aperto con quantità ancora da ricevere.
Set<String> prodottiInOrdiniAperti(Dati d) => {
      for (final o in d.elenco('ordini_fornitore'))
        if (statiOrdineAperti.contains(o['stato']))
          for (final r in comeListaDoc(o['righe']))
            if (numero(r['ricevuta']) < numero(r['quantita'])) comeStr(r['prodottoId']),
    };

class PropostaRiordino {
  PropostaRiordino(this.p, this.g, this.q);
  final Doc p;
  final num g, q;
}

/// Prodotti sotto scorta da riordinare, raggruppati per fornitore preferito ('' = senza fornitore).
/// Quantità proposta: riportare la giacenza a N volte la scorta minima (Impostazioni, predefinito 2).
({Map<String, List<PropostaRiordino>> gruppi, int giaInOrdine, int moltiplicatore}) proposteRiordino(Dati d) {
  final avv = avvisiMagazzino(d);
  final inOrdine = prodottiInOrdiniAperti(d);
  final molt = (comeInt(comeDoc(d.cfg['magazzino'])['moltiplicatoreRiordino']) ?? 2).clamp(1, 20);
  final candidati = [...avv.sottoScorta, ...avv.negativi.where((x) => !avv.sottoScorta.any((y) => y.p['id'] == x.p['id']))];
  final gruppi = <String, List<PropostaRiordino>>{};
  var gia = 0;
  for (final c in candidati) {
    if (inOrdine.contains(c.p['id'])) {
      gia++;
      continue;
    }
    final q = qta(((numero(c.p['scortaMinima']) * molt) - c.g).ceil().clamp(1, 1 << 30));
    final f = comeStr(c.p['fornitoreId']);
    final k = f.isNotEmpty && d.get('fornitori', f) != null ? f : '';
    gruppi.putIfAbsent(k, () => []).add(PropostaRiordino(c.p, c.g, q));
  }
  return (gruppi: gruppi, giaInOrdine: gia, moltiplicatore: molt);
}

Future<List<Doc>> creaBozzeRiordino(Dati d, Map<String, List<PropostaRiordino>> gruppi) async {
  final creati = <Doc>[];
  for (final e in gruppi.entries) {
    final f = e.key.isEmpty ? null : d.get('fornitori', e.key);
    final o = nuovoOrdine(fornitoreId: e.key.isEmpty ? null : e.key, righe: [for (final x in e.value) rigaOrdineDa(x.p, quantita: x.q)]);
    o['speseSpedizioneCent'] = f?['speseSpedizioneCent'];
    creati.add(o);
  }
  await d.salvaMolti('ordini_fornitore', creati);
  return creati;
}

/// Ricevimento merce: per ogni riga la quantità arrivata ora (+ lotto e scadenza facoltativi).
/// Registra i carichi, aggiorna i prodotti e lo stato dell'ordine. Restituisce cosa serve per "Annulla".
Future<({List<Doc> movimenti, List<Doc> prodottiPrima, Doc ordinePrima})> riceviOrdine(
  Dati d,
  Doc o,
  Map<int, ({num quantita, String lotto, String scadenza})> arrivi, {
  bool aggiornaCosto = true,
}) async {
  final ordinePrima = clonaDoc(o);
  final movimenti = <Doc>[], prodottiPrima = <Doc>[];
  final forn = d.get('fornitori', comeStr(o['fornitoreId']));
  final righe = comeListaDoc(o['righe']);
  await d.inBlocco(() async {
    for (var i = 0; i < righe.length; i++) {
      final r = righe[i];
      final a = arrivi[i];
      final p = d.get('prodotti', comeStr(r['prodottoId']));
      if (a == null || p == null || a.quantita <= 0) continue;
      movimenti.add(await registraMovimento(d,
          prodottoId: comeStr(p['id']), tipo: 'carico', quantita: a.quantita, nota: 'Ordine a ${forn != null ? nomeFornitore(forn) : 'fornitore'}',
          riferimento: {'tipo': 'ordine', 'id': o['id']}, costoCent: comeInt(r['costoCent']), lotto: a.lotto, demo: o['demo'] == true));
      r['ricevuta'] = qta(numero(r['ricevuta']) + a.quantita);
      prodottiPrima.add(clonaDoc(p));
      if (aggiornaCosto && r['costoCent'] != null) p['costoCent'] = r['costoCent'];
      if (a.lotto.isNotEmpty) p['lotto'] = a.lotto;
      if (a.scadenza.isNotEmpty) p['scadenza'] = a.scadenza;
      await d.salva('prodotti', p);
    }
    if (movimenti.isEmpty) return;
    o['righe'] = righe;
    o['stato'] = righe.every((r) => numero(r['ricevuta']) >= numero(r['quantita']) || d.get('prodotti', comeStr(r['prodottoId'])) == null) ? 'ricevuto' : 'parziale';
    o['dataRicezione'] = adessoIso();
    await d.salva('ordini_fornitore', o);
  });
  return (movimenti: movimenti, prodottiPrima: prodottiPrima, ordinePrima: ordinePrima);
}

/* ================================ SCHEDA LAVORO ================================ */
/// Prodotti consumati di default dai servizi (Impostazioni → Servizi), sommati e moltiplicati per la quantità.
List<Doc> prodottiDaServizi(Dati d, List<Doc> servizi) {
  final acc = <String, Doc>{};
  for (final sv in servizi) {
    final def = d.get('servizi', comeStr(sv['servizioId']));
    for (final x in comeListaDoc(def?['prodottiDefault'])) {
      final p = d.get('prodotti', comeStr(x['prodottoId']));
      if (p == null || p['archiviato'] == true) continue;
      final r = acc.putIfAbsent(comeStr(p['id']), () => {'prodottoId': p['id'], 'nome': nomeProdotto(p), 'quantita': 0, 'lotto': comeStr(p['lotto']), 'scala': true});
      r['quantita'] = qta(numero(r['quantita']) + numero(x['quantita']) * (comeInt(sv['quantita']) ?? 1));
    }
  }
  return acc.values.toList();
}

/// Consumi di magazzino di una scheda lavoro: ricalcolati da zero a ogni salvataggio.
/// Restituisce i movimenti precedenti (da eliminare) e i nuovi (da salvare).
({List<Doc> precedenti, List<Doc> nuovi}) consumiScheda(Dati d, Doc scheda, String nomeCliente) {
  final id = comeStr(scheda['id']);
  final precedenti = d.elenco('movimenti_magazzino', archiviati: true).where((m) => comeDoc(m['riferimento'])['tipo'] == 'scheda' && comeDoc(m['riferimento'])['id'] == id).toList();
  final quando = isoJs(D.combina(comeStr(scheda['data']), comeStr(scheda['ora']).isEmpty ? '12:00' : comeStr(scheda['ora'])));
  final nuovi = [
    for (final x in comeListaDoc(scheda['prodotti']))
      if (x['scala'] == true && comeStr(x['prodottoId']).isNotEmpty && numero(x['quantita']) > 0 && d.get('prodotti', comeStr(x['prodottoId'])) != null)
        nuovoMovimento(
            prodottoId: comeStr(x['prodottoId']), tipo: 'consumo', quantita: numero(x['quantita']), nota: 'Scheda lavoro · $nomeCliente', riferimento: {'tipo': 'scheda', 'id': id},
            lotto: comeStr(x['lotto']), data: quando, demo: scheda['demo'] == true),
  ];
  return (precedenti: precedenti, nuovi: nuovi);
}
