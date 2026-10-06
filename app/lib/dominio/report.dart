import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';

import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import 'agenda.dart';
import 'magazzino.dart';

/* =====================================================================================
   REPORT — incassi, servizi più richiesti, non presentate, consumi, vendite, spesa
   fornitori. Stessi calcoli della web app; CSV con ";" e virgola decimale (Excel italiano).
   ===================================================================================== */

const presetReport = {'mese': 'Questo mese', 'mesescorso': 'Mese scorso', '30': 'Ultimi 30 giorni', '90': 'Ultimi 90 giorni', 'anno': "Quest'anno", 'annoscorso': 'Anno scorso', 'pers': 'Personalizzato'};

(String, String) periodoReport(String preset, {String? da, String? a, DateTime? ora}) {
  final o = ora ?? DateTime.now();
  final k = D.key(o);
  String kk(int y, int m, int g) => D.key(DateTime(y, m, g));
  return switch (preset) {
    'mese' => (kk(o.year, o.month, 1), k),
    'mesescorso' => (kk(o.year, o.month - 1, 1), kk(o.year, o.month, 0)),
    '30' => (D.aggiungiGiorniKey(k, -29), k),
    '90' => (D.aggiungiGiorniKey(k, -89), k),
    'anno' => ('${o.year}-01-01', k),
    'annoscorso' => ('${o.year - 1}-01-01', '${o.year - 1}-12-31'),
    _ => (da ?? kk(o.year, o.month, 1), a ?? k),
  };
}

String gruppoAutomatico(String da, String a) {
  final g = D.diffGiorni(da, a) + 1;
  return g <= 45 ? 'giorno' : (g <= 200 ? 'settimana' : 'mese');
}

String chiaveGruppo(String key, String gruppo) => switch (gruppo) {
      'mese' => key.substring(0, 7),
      'settimana' => D.key(D.inizioSettimana(D.daKey(key))),
      _ => key,
    };

String etichettaGruppo(String k, String gruppo) => switch (gruppo) {
      'mese' => F.maiuscola(DateFormat('MMMM y', 'it').format(DateTime(int.parse(k.substring(0, 4)), int.parse(k.substring(5, 7)), 1))),
      'settimana' => 'Sett. dal ${F.dataKey(k)}',
      _ => F.giornoBreve(D.daKey(k)),
    };

String etichettaBreve(String k, String gruppo) => switch (gruppo) {
      'giorno' => '${int.parse(k.substring(8))}',
      'mese' => etichettaGruppo(k, gruppo).substring(0, 3),
      _ => F.dataKey(k).substring(0, 5),
    };

List<String> chiaviPeriodo(String da, String a, String gruppo) {
  final out = <String>[];
  var k = da;
  for (var i = 0; k.compareTo(a) <= 0 && i < 1200; i++) {
    final g = chiaveGruppo(k, gruppo);
    if (out.isEmpty || out.last != g) out.add(g);
    k = D.aggiungiGiorniKey(k, 1);
  }
  return out;
}

class RigaGruppo {
  int servizi = 0, vendite = 0, visite = 0;
  int get totale => servizi + vendite;
}

class RigaNome {
  RigaNome(this.nome, [this.unita = 'pz']);
  final String nome, unita;
  num q = 0;
  int n = 0, cent = 0;
}

class Report {
  Report(this.da, this.a, this.gruppo);
  final String da, a, gruppo;
  late List<String> chiavi;
  final perGruppo = <String, RigaGruppo>{};
  int totServizi = 0, totVendite = 0, visite = 0, completati = 0, noShow = 0, annullati = 0, daSvolgere = 0, totSpesa = 0, totConsumi = 0;
  List<RigaNome> servizi = [], consumi = [], vendite = [], spesa = [];
  double? get tassoNoShow => completati + noShow == 0 ? null : noShow / (completati + noShow);
  int get mediaVisita => visite == 0 ? 0 : (totServizi / visite).round();
}

Report calcolaReport(Dati d, String da, String a, {String? gruppo}) {
  final r = Report(da, a, gruppo ?? gruppoAutomatico(da, a));
  bool dentro(String k) => k.compareTo(da) >= 0 && k.compareTo(a) <= 0;
  final visite = tutteLeVisite(d).where((v) => dentro(v.data)).toList();
  final movimenti = d.elenco('movimenti_magazzino', archiviati: true);
  final vendite = movimenti.where((m) => m['tipo'] == 'vendita' && dentro(chiaveData(comeStr(m['data'])))).toList();
  final consumi = movimenti.where((m) => ['consumo', 'scarico'].contains(m['tipo']) && dentro(chiaveData(comeStr(m['data'])))).toList();
  final apps = d.elenco('appuntamenti').where((x) => dentro(D.key(inizioApp(x)))).toList();
  final ordini = d.elenco('ordini_fornitore').where((o) => spesaOrdine(o) > 0 && dentro(chiaveData(dataSpesaOrdine(o)))).toList();

  r.chiavi = chiaviPeriodo(da, a, r.gruppo);
  for (final k in r.chiavi) {
    r.perGruppo[k] = RigaGruppo();
  }
  for (final v in visite) {
    final g = r.perGruppo[chiaveGruppo(v.data, r.gruppo)];
    if (g != null) {
      g.servizi += v.importoCent;
      g.visite++;
    }
  }
  for (final m in vendite) {
    r.perGruppo[chiaveGruppo(chiaveData(comeStr(m['data'])), r.gruppo)]?.vendite += comeInt(m['importoCent']) ?? 0;
  }
  r.visite = visite.length;
  r.totServizi = visite.fold(0, (t, v) => t + v.importoCent);
  r.totVendite = vendite.fold(0, (t, m) => t + (comeInt(m['importoCent']) ?? 0));

  final serv = <String, RigaNome>{};
  for (final v in visite) {
    for (final s in v.servizi) {
      final k = comeStr(s['servizioId']).isNotEmpty ? comeStr(s['servizioId']) : comeStr(s['nome']);
      final x = serv.putIfAbsent(k, () => RigaNome(comeStr(s['nome'])));
      final q = comeInt(s['quantita']) ?? 1;
      x.n += q;
      x.cent += (comeInt(s['prezzoCent']) ?? 0) * q;
    }
  }
  r.servizi = serv.values.toList()..sort((x, y) => y.n != x.n ? y.n.compareTo(x.n) : y.cent.compareTo(x.cent));

  r.completati = apps.where((x) => statoApp(x) == 'completato').length;
  r.noShow = apps.where((x) => statoApp(x) == 'non_presentata').length;
  r.annullati = apps.where((x) => statoApp(x) == 'annullato').length;
  r.daSvolgere = apps.where((x) => ['prenotato', 'confermato'].contains(statoApp(x))).length;

  final cons = <String, RigaNome>{};
  for (final m in consumi) {
    final p = d.get('prodotti', comeStr(m['prodottoId']));
    final x = cons.putIfAbsent(comeStr(m['prodottoId']), () => RigaNome(p != null ? nomeProdottoConMarca(p) : 'Prodotto eliminato', comeStr(p?['unita']).isEmpty ? 'pz' : comeStr(p?['unita'])));
    x.q = qta(x.q - numero(m['quantita']));
    x.cent += (-numero(m['quantita']) * (comeInt(p?['costoCent']) ?? 0)).round();
  }
  r.consumi = cons.values.toList()..sort((x, y) => y.cent != x.cent ? y.cent.compareTo(x.cent) : y.q.compareTo(x.q));
  r.totConsumi = r.consumi.fold(0, (t, x) => t + x.cent);

  final vend = <String, RigaNome>{};
  for (final m in vendite) {
    final p = d.get('prodotti', comeStr(m['prodottoId']));
    final x = vend.putIfAbsent(comeStr(m['prodottoId']), () => RigaNome(p != null ? nomeProdotto(p) : 'Prodotto eliminato', comeStr(p?['unita']).isEmpty ? 'pz' : comeStr(p?['unita'])));
    x.q = qta(x.q - numero(m['quantita']));
    x.cent += comeInt(m['importoCent']) ?? 0;
  }
  r.vendite = vend.values.toList()..sort((x, y) => y.cent.compareTo(x.cent));

  final sp = <String, RigaNome>{};
  for (final o in ordini) {
    final f = d.get('fornitori', comeStr(o['fornitoreId']));
    final x = sp.putIfAbsent(comeStr(o['fornitoreId']), () => RigaNome(f != null ? nomeFornitore(f) : 'Fornitore eliminato'));
    x.n++;
    x.cent += spesaOrdine(o);
  }
  r.spesa = sp.values.toList()..sort((x, y) => y.cent.compareTo(x.cent));
  r.totSpesa = r.spesa.fold(0, (t, x) => t + x.cent);
  return r;
}

String percentuale(double? x) => x == null ? '—' : '${(x * 100).toStringAsFixed(1).replaceAll('.', ',')}%';

/* ----------------------------- CSV ----------------------------- */
String csvCampo(dynamic v) {
  if (v == null) return '';
  final s = v is num ? v.toString().replaceAll('.', ',') : v.toString();
  return RegExp(r'[";\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
}

String euroCsv(int? cent) => cent == null ? '' : (cent / 100).toStringAsFixed(2).replaceAll('.', ',');

/// File CSV per Excel in italiano: BOM UTF-8, separatore ";", righe CRLF.
Uint8List creaCsv(List<String> intestazioni, List<List<dynamic>> righe) =>
    Uint8List.fromList(utf8.encode('﻿${[intestazioni, ...righe].map((r) => r.map(csvCampo).join(';')).join('\r\n')}'));

({List<String> intestazioni, List<List<dynamic>> righe}) tabellaCsv(Report r, String quale) => switch (quale) {
      'incassi' => (
          intestazioni: ['Periodo', 'Visite', 'Servizi (€)', 'Vendite (€)', 'Totale (€)'],
          righe: [for (final k in r.chiavi) [etichettaGruppo(k, r.gruppo), r.perGruppo[k]!.visite, euroCsv(r.perGruppo[k]!.servizi), euroCsv(r.perGruppo[k]!.vendite), euroCsv(r.perGruppo[k]!.totale)]],
        ),
      'servizi' => (intestazioni: ['Servizio', 'Volte', 'Incasso a listino (€)'], righe: [for (final s in r.servizi) [s.nome, s.n, euroCsv(s.cent)]]),
      'appuntamenti' => (
          intestazioni: ['Esito', 'Numero'],
          righe: [['Completati', r.completati], ['Non presentata', r.noShow], ['Annullati', r.annullati], ['Tasso non presentazione (%)', r.tassoNoShow == null ? '' : (r.tassoNoShow! * 1000).round() / 10]],
        ),
      'consumi' => (intestazioni: ['Prodotto', 'Quantità', 'Unità', 'Valore a costo (€)'], righe: [for (final x in r.consumi) [x.nome, x.q, x.unita, euroCsv(x.cent)]]),
      'vendite' => (intestazioni: ['Prodotto', 'Quantità', 'Unità', 'Incasso (€)'], righe: [for (final x in r.vendite) [x.nome, x.q, x.unita, euroCsv(x.cent)]]),
      _ => (intestazioni: ['Fornitore', 'Ordini ricevuti', 'Spesa (€)'], righe: [for (final x in r.spesa) [x.nome, x.n, euroCsv(x.cent)]]),
    };
