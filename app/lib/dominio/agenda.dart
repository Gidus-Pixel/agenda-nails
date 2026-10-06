import '../core/config.dart';
import '../core/date.dart';
import '../core/telefono.dart';
import '../core/util.dart';
import '../dati/dati.dart';

/* ===================== utilità sui documenti ===================== */
String nomeCliente(Doc? c) {
  if (c == null) return 'Cliente';
  final n = [comeStr(c['nome']), comeStr(c['cognome'])].where((s) => s.isNotEmpty).join(' ');
  return n.isEmpty ? 'Cliente senza nome' : n;
}

bool haConsenso(Doc? c, String tipo) => c != null && comeDoc(comeDoc(c['consensi'])[tipo])['dato'] == true;
bool haAvvertenze(Doc? c) => c != null && comeStr(c['avvertenze']).trim().isNotEmpty && haConsenso(c, 'sanitari');

Doc nuovaClienteVuota({String nome = '', String cognome = '', String telefono = ''}) => {
      'nome': nome, 'cognome': cognome, 'telefono': telefono, 'email': '', 'dataNascita': '', 'note': '',
      'preferenze': {'forma': '', 'lunghezza': '', 'colori': '', 'tecnica': ''},
      'avvertenze': '', 'tag': <String>[],
      'consensi': {for (final k in consensi.keys) k: {'dato': false, 'data': ''}},
      'archiviato': false,
    };

DateTime inizioApp(Doc a) => D.daIso(comeStr(a['inizio']));
DateTime fineApp(Doc a) => D.daIso(comeStr(a['fine']));
int durataApp(Doc a) => D.minutiTra(inizioApp(a), fineApp(a));
String statoApp(Doc a) => comeStr(a['stato']).isEmpty ? 'prenotato' : comeStr(a['stato']);
List<Doc> serviziApp(Doc a) => comeListaDoc(a['servizi']);
String serviziTesto(Doc a) {
  final s = serviziApp(a).map((x) => (comeInt(x['quantita']) ?? 1) > 1 ? '${x['nome']} ×${x['quantita']}' : comeStr(x['nome'])).join(' + ');
  return s.isEmpty ? 'Nessun servizio' : s;
}

String nomeOperatrice(Dati d, String? id) {
  final o = d.operatrici.where((x) => x['id'] == id).toList();
  if (o.isEmpty) return '';
  return comeStr(o.first['nome']).isEmpty ? 'Operatrice' : comeStr(o.first['nome']);
}

/* ===================== servizi ===================== */
List<Doc> serviziAttivi(Dati d) {
  final s = d.elenco('servizi');
  s.sort((a, b) {
    final c = comeStr(a['categoria']).compareTo(comeStr(b['categoria']));
    if (c != 0) return c;
    final o = (comeInt(a['ordine']) ?? 0).compareTo(comeInt(b['ordine']) ?? 0);
    if (o != 0) return o;
    return comeStr(a['nome']).compareTo(comeStr(b['nome']));
  });
  return s;
}

int coloreServizio(Dati d, Doc app) {
  final s = serviziApp(app);
  if (s.isEmpty) return coloreDaHex(comeDoc(d.cfg['brand'])['primario']) ?? 0xFFB4646E;
  final att = d.get('servizi', comeStr(s.first['servizioId']));
  return coloreDaHex(att?['colore'] ?? s.first['colore']) ?? (coloreDaHex(comeDoc(d.cfg['brand'])['primario']) ?? 0xFFB4646E);
}

int coloreApp(Dati d, Doc app) {
  final st = statoApp(app);
  if (st == 'annullato' || st == 'non_presentata') return statiAppuntamento[st]!.colore;
  if (comeDoc(d.cfg['agenda'])['coloreEventiPer'] == 'stato') return statiAppuntamento[st]?.colore ?? 0xFF777777;
  return coloreServizio(d, app);
}

/* ===================== appuntamenti e blocchi ===================== */
List<Doc> appuntamentiTra(Dati d, DateTime da, DateTime a) => d.elenco('appuntamenti').where((x) {
      final i = comeStr(x['inizio']), f = comeStr(x['fine']);
      if (i.isEmpty || f.isEmpty) return false;
      return D.daIso(f).isAfter(da) && D.daIso(i).isBefore(a);
    }).toList()
      ..sort((x, y) => comeStr(x['inizio']).compareTo(comeStr(y['inizio'])));

List<Doc> appuntamentiCliente(Dati d, String clienteId) =>
    d.elenco('appuntamenti').where((a) => a['clienteId'] == clienteId).toList()..sort((x, y) => comeStr(x['inizio']).compareTo(comeStr(y['inizio'])));

List<Doc> schedeCliente(Dati d, String clienteId) => d.elenco('schede_lavoro').where((s) => s['clienteId'] == clienteId).toList()
  ..sort((a, b) => ('${b['data']}${b['ora'] ?? ''}').compareTo('${a['data']}${a['ora'] ?? ''}'));

class IstanzaBlocco {
  IstanzaBlocco(this.blocco, this.inizio, this.fine);
  final Doc blocco;
  final DateTime inizio, fine;
}

List<IstanzaBlocco> istanzeBlocchi(Dati d, DateTime da, DateTime a) {
  final out = <IstanzaBlocco>[];
  for (final b in d.elenco('blocchi')) {
    final r = b['ricorrenza'];
    if (r is Map) {
      final giorni = (r['giorni'] as List? ?? const []).map((e) => comeInt(e)).toList();
      var g = D.inizioGiorno(da);
      final ultimo = D.inizioGiorno(a);
      for (var i = 0; !g.isAfter(ultimo) && i < 800; i++, g = D.aggiungiGiorni(g, 1)) {
        final k = D.key(g);
        if (comeStr(r['dal']).isNotEmpty && k.compareTo(comeStr(r['dal'])) < 0) continue;
        if (comeStr(r['al']).isNotEmpty && k.compareTo(comeStr(r['al'])) > 0) break;
        if (!giorni.contains(D.jsDay(g))) continue;
        final ini = D.combina(k, comeStr(r['oraInizio'])), fin = D.combina(k, comeStr(r['oraFine']));
        if (fin.isAfter(da) && ini.isBefore(a)) out.add(IstanzaBlocco(b, ini, fin));
      }
    } else if (comeStr(b['inizio']).isNotEmpty) {
      final ini = D.daIso(comeStr(b['inizio'])), fin = D.daIso(comeStr(b['fine']));
      if (fin.isAfter(da) && ini.isBefore(a)) out.add(IstanzaBlocco(b, ini, fin));
    }
  }
  return out;
}

String descriviBlocco(Doc b) {
  final tipo = tipiBlocco[b['tipo']] ?? 'Blocco';
  final t = comeStr(b['titolo']).isNotEmpty ? '$tipo: ${b['titolo']}' : tipo;
  final r = b['ricorrenza'];
  if (r is Map) {
    const nomi = ['dom', 'lun', 'mar', 'mer', 'gio', 'ven', 'sab'];
    final gg = [1, 2, 3, 4, 5, 6, 0].where((x) => (r['giorni'] as List? ?? const []).contains(x)).map((x) => nomi[x]).join(', ');
    return '$t — ogni $gg, ${r['oraInizio']}–${r['oraFine']}${comeStr(r['al']).isNotEmpty ? ' fino al ${F.dataKey(comeStr(r['al']))}' : ''}';
  }
  final i = D.daIso(comeStr(b['inizio'])), f = D.daIso(comeStr(b['fine']));
  if (b['tuttoIlGiorno'] == true) {
    final ultimo = D.aggiungiGiorni(f, -1);
    return D.key(i) == D.key(ultimo) ? '$t — ${F.giornoLungo(i)}' : '$t — dal ${F.data(i)} al ${F.data(ultimo)}';
  }
  return '$t — ${F.giornoLungo(i)}, ${F.intervallo(i, f)}';
}

/* ===================== controllo di uno slot ===================== */
class Problema {
  Problema(this.tipo, this.msg);
  final String tipo, msg;
}

int cuscinettoDi(Dati d, List<Doc> servizi) {
  final def = d.cuscinettoMinuti;
  if (servizi.isEmpty) return def;
  var m = 0;
  for (final s in servizi) {
    final att = d.get('servizi', comeStr(s['servizioId']));
    final v = comeInt(att?['cuscinetto']) ?? comeInt(s['cuscinetto']) ?? def;
    if (v > m) m = v;
  }
  return m;
}

List<List<int>> intervalliGiorno(Dati d, DateTime giorno) {
  final o = d.cfg['orari'];
  if (o is! Map) return const [];
  final iv = o[D.giornoKey(giorno)];
  if (iv is! List) return const [];
  return iv.whereType<List>().map((x) => [D.minDaHHMM(comeStr(x[0])), D.minDaHHMM(comeStr(x[1]))]).toList()..sort((a, b) => a[0].compareTo(b[0]));
}

List<Problema> controllaSlot(Dati d, {required DateTime inizio, required DateTime fine, String? operatriceId, String? escludiId, List<Doc> servizi = const [], bool ignoraPassato = false}) {
  final problemi = <Problema>[];
  if (!fine.isAfter(inizio)) return [Problema('durata', 'La durata deve essere maggiore di zero.')];
  if (!ignoraPassato && inizio.isBefore(DateTime.now().subtract(const Duration(minutes: 1)))) problemi.add(Problema('passato', "L'orario è nel passato."));

  if (d.cfg['orari'] is Map) {
    final kIni = D.key(inizio), kFin = D.key(fine.subtract(const Duration(milliseconds: 1)));
    final nomeG = D.giorniNome[D.giornoKey(inizio)]!;
    if (kIni != kFin) {
      problemi.add(Problema('orario', "L'appuntamento prosegue oltre la mezzanotte."));
    } else {
      final iv = intervalliGiorno(d, inizio);
      final a = D.minutiDelGiorno(inizio);
      var f = D.minutiDelGiorno(fine);
      if (f == 0) f = 1440;
      final testoOrari = iv.map((x) => '${D.hhmmDaMin(x[0])}–${D.hhmmDaMin(x[1])}').join(' / ');
      if (iv.isEmpty) {
        problemi.add(Problema('orario', '$nomeG è giorno di chiusura.'));
      } else if (!iv.any((x) => a >= x[0] && f <= x[1])) {
        List<int>? pausa;
        for (var i = 1; i < iv.length; i++) {
          if (iv[i][0] > iv[i - 1][1] && a < iv[i][0] && f > iv[i - 1][1]) pausa = [iv[i - 1][1], iv[i][0]];
        }
        if (pausa != null) {
          final cavallo = a < pausa[0] && f > pausa[1];
          problemi.add(Problema('orario', "L'appuntamento ${cavallo ? 'è a cavallo della' : 'cade nella'} pausa (${D.hhmmDaMin(pausa[0])}–${D.hhmmDaMin(pausa[1])}). Orari di ${nomeG.toLowerCase()}: $testoOrari."));
        } else {
          problemi.add(Problema('orario', "Fuori dall'orario di apertura (${nomeG.toLowerCase()}: $testoOrari)."));
        }
      }
    }
  }
  final da = D.aggiungiGiorni(D.inizioGiorno(inizio), -1), a = D.aggiungiGiorni(D.inizioGiorno(fine), 2);
  for (final ib in istanzeBlocchi(d, da, a)) {
    final op = comeStr(ib.blocco['operatriceId']);
    if (op.isNotEmpty && operatriceId != null && op != operatriceId) continue;
    if (ib.inizio.isBefore(fine) && ib.fine.isAfter(inizio)) problemi.add(Problema('blocco', 'Si sovrappone a: ${descriviBlocco(ib.blocco)}.'));
  }
  final mio = cuscinettoDi(d, servizi);
  for (final ap in appuntamentiTra(d, da, a)) {
    if (ap['id'] == escludiId || !statiAttivi.contains(statoApp(ap))) continue;
    if (d.piuOperatrici && operatriceId != null && comeStr(ap['operatriceId']).isNotEmpty && ap['operatriceId'] != operatriceId) continue;
    final ai = inizioApp(ap), af = fineApp(ap);
    final nome = d.get('clienti', comeStr(ap['clienteId'])) != null ? nomeCliente(d.get('clienti', comeStr(ap['clienteId']))) : comeStr(ap['clienteNome']);
    if (ai.isBefore(fine) && af.isAfter(inizio)) {
      problemi.add(Problema('sovrapposizione', "Si sovrappone all'appuntamento di $nome (${F.intervallo(ai, af)})."));
      continue;
    }
    if (!af.isAfter(inizio)) {
      final serve = cuscinettoDi(d, serviziApp(ap));
      final gap = D.minutiTra(af, inizio);
      if (gap < serve) problemi.add(Problema('cuscinetto', "Tra la fine dell'appuntamento di $nome (${D.hhmm(af)}) e questo ci sono $gap min: ne servono $serve per pulizia e sterilizzazione."));
    } else if (!ai.isBefore(fine)) {
      final gap = D.minutiTra(fine, ai);
      if (gap < mio) problemi.add(Problema('cuscinetto', "Dopo questo appuntamento restano $gap min prima di quello di $nome (${D.hhmm(ai)}): ne servono $mio per pulizia e sterilizzazione."));
    }
  }
  return problemi;
}

/// Primi slot liberi per una durata, entro [giorniMax] giorni.
({List<DateTime> slot, String? errore}) trovaSlotLiberi(Dati d, {required int durataMin, String? operatriceId, List<Doc> servizi = const [], DateTime? da, int quanti = 6, String? escludiId, int giorniMax = 90}) {
  if (d.cfg['orari'] is! Map) return (slot: <DateTime>[], errore: 'Per cercare gli slot liberi imposta prima gli orari di apertura (Impostazioni → Orari).');
  if (durataMin <= 0) return (slot: <DateTime>[], errore: 'Indica almeno un servizio o una durata.');
  final passo = d.slotMinuti < 5 ? 5 : d.slotMinuti;
  final ora = DateTime.now();
  final partenza = D.arrotondaSu((da != null && da.isAfter(ora)) ? da : ora, passo);
  final trovati = <DateTime>[];
  for (var g = 0; g <= giorniMax && trovati.length < quanti; g++) {
    final giorno = D.aggiungiGiorni(D.inizioGiorno(partenza), g);
    final k = D.key(giorno);
    for (final iv in intervalliGiorno(d, giorno)) {
      for (var m = iv[0]; m + durataMin <= iv[1] && trovati.length < quanti; m += passo) {
        final ini = D.combina(k, D.hhmmDaMin(m));
        if (ini.isBefore(partenza)) continue;
        final fin = D.aggiungiMinuti(ini, durataMin);
        if (controllaSlot(d, inizio: ini, fine: fin, operatriceId: operatriceId, servizi: servizi, escludiId: escludiId).isEmpty) trovati.add(ini);
      }
    }
  }
  return (slot: trovati, errore: null);
}

/* ===================== visite, incassi, richiami ===================== */
class Visita {
  Visita(this.data, this.clienteId, this.importoCent, this.servizi);
  final String data;
  final String? clienteId;
  final int importoCent;
  final List<Doc> servizi;
}

List<Visita> tutteLeVisite(Dati d) {
  final v = <Visita>[
    for (final s in d.elenco('schede_lavoro')) Visita(comeStr(s['data']), comeStr(s['clienteId']), comeInt(s['importoCent']) ?? 0, comeListaDoc(s['servizi'])),
  ];
  for (final a in d.elenco('appuntamenti')) {
    if (statoApp(a) == 'completato' && comeStr(a['schedaId']).isEmpty) v.add(Visita(D.key(inizioApp(a)), comeStr(a['clienteId']), comeInt(a['prezzoTotaleCent']) ?? 0, serviziApp(a)));
  }
  return v;
}

int incassoTra(List<Visita> visite, String daKey, String aKey) =>
    visite.where((v) => v.data.compareTo(daKey) >= 0 && v.data.compareTo(aKey) <= 0).fold(0, (t, v) => t + v.importoCent);

int venditeTra(Dati d, String daKey, String aKey) => d.elenco('movimenti_magazzino', archiviati: true).where((m) {
      if (m['tipo'] != 'vendita') return false;
      final k = D.key(D.daIso(comeStr(m['data'])));
      return k.compareTo(daKey) >= 0 && k.compareTo(aKey) <= 0;
    }).fold(0, (t, m) => t + (comeInt(m['importoCent']) ?? 0));

class StatCliente {
  StatCliente(this.visite, this.spesaCent, this.frequenzaGiorni, this.noShow, this.ultimaVisita);
  final int visite, spesaCent, noShow;
  final int? frequenzaGiorni;
  final String? ultimaVisita;
}

StatCliente statisticheCliente(Dati d, String clienteId) {
  final vis = tutteLeVisite(d).where((v) => v.clienteId == clienteId).toList()..sort((a, b) => a.data.compareTo(b.data));
  int? freq;
  if (vis.length >= 2) {
    var tot = 0;
    for (var i = 1; i < vis.length; i++) {
      tot += D.diffGiorni(vis[i - 1].data, vis[i].data);
    }
    freq = (tot / (vis.length - 1)).round();
  }
  final noShow = appuntamentiCliente(d, clienteId).where((a) => statoApp(a) == 'non_presentata').length;
  return StatCliente(vis.length, vis.fold(0, (t, v) => t + v.importoCent), freq, noShow, vis.isEmpty ? null : vis.last.data);
}

class Richiamo {
  Richiamo(this.cliente, this.ultimaVisita, this.scadenza, this.ritardo, this.servizi);
  final Doc cliente;
  final String ultimaVisita, scadenza, servizi;
  final int ritardo;
}

List<Richiamo> clientiDaRicontattare(Dati d) {
  final ora = adessoIso();
  final oggi = D.oggiKey();
  final futuri = d.elenco('appuntamenti').where((a) => comeStr(a['inizio']).compareTo(ora) > 0 && ['prenotato', 'confermato'].contains(statoApp(a))).map((a) => a['clienteId']).toSet();
  final ultima = <String, Visita>{};
  for (final v in tutteLeVisite(d)) {
    final c = v.clienteId ?? '';
    if (!ultima.containsKey(c) || v.data.compareTo(ultima[c]!.data) > 0) ultima[c] = v;
  }
  final out = <Richiamo>[];
  for (final c in d.elenco('clienti')) {
    final u = ultima[c['id']];
    if (u == null || futuri.contains(c['id'])) continue;
    final rich = u.servizi.map((s) => comeInt(d.get('servizi', comeStr(s['servizioId']))?['richiamoGiorni'] ?? s['richiamoGiorni']) ?? 0).where((x) => x > 0).toList();
    if (rich.isEmpty) continue;
    rich.sort();
    final scad = D.aggiungiGiorniKey(u.data, rich.first);
    if (scad.compareTo(oggi) <= 0) out.add(Richiamo(c, u.data, scad, D.diffGiorni(scad, oggi), u.servizi.map((s) => comeStr(s['nome'])).join(', ')));
  }
  out.sort((a, b) => b.ritardo.compareTo(a.ritardo));
  return out;
}

/* ===================== messaggi ===================== */
Map<String, String> valoriMessaggio(Dati d, Doc? cliente, Doc? app) {
  final v = {'nome': comeStr(cliente?['nome']), 'attivita': d.nomeAttivita, 'giorno': '', 'ora': '', 'servizio': ''};
  if (app != null) {
    final i = inizioApp(app);
    v['giorno'] = F.giornoMsg(i);
    v['ora'] = D.hhmm(i);
    v['servizio'] = serviziApp(app).map((s) => comeStr(s['nome'])).join(' + ');
  }
  return v;
}

Uri? linkPromemoria(Dati d, Doc cliente, Doc app) => linkWhatsApp(
      comeStr(cliente['telefono']),
      compilaModello(comeStr(comeDoc(d.cfg['messaggi'])['promemoria']), valoriMessaggio(d, cliente, app)),
      prefisso: d.prefisso,
    );

/// Nome della cliente di un appuntamento o di una scheda (anche se la cliente è stata eliminata).
String nomeClienteDi(Dati d, Doc rec, {String vuoto = 'Cliente'}) {
  final c = d.get('clienti', comeStr(rec['clienteId']));
  if (c != null) return nomeCliente(c);
  return comeStr(rec['clienteNome']).isNotEmpty ? comeStr(rec['clienteNome']) : vuoto;
}
