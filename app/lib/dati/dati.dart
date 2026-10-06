import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/util.dart';
import 'archivio.dart';

/// Tutti i dati dell'app, tenuti in memoria (sono pochi: migliaia di record al massimo)
/// e salvati subito nell'archivio. L'interfaccia legge in modo sincrono e si aggiorna
/// tramite `notifyListeners`.
class Dati extends ChangeNotifier {
  Dati(this._archivio);
  final Archivio _archivio;
  final Map<String, Map<String, Doc>> _c = {for (final a in archivi) a: <String, Doc>{}};
  Doc _config = clonaDoc(configPredefinita);
  bool pronto = false;
  /// Chiamata dopo ogni modifica locale (la usa il cloud per sincronizzare).
  void Function(String collezione)? suModifica;
  bool _silenzioso = false;

  Archivio get archivio => _archivio;

  /// Ridisegna l'interfaccia (es. tornando nell'app, per aggiornare "adesso").
  void aggiorna() => notifyListeners();

  Future<void> avvia() async {
    await _archivio.apri();
    final tutto = await _archivio.caricaTutto(archivi);
    for (final e in tutto.entries) {
      _c[e.key] = {for (final d in e.value) comeStr(d['id']): d};
    }
    _ricaricaConfig();
    if (meta('schemaVersion') == null) await scriviMeta('schemaVersion', schemaVersion);
    pronto = true;
    notifyListeners();
  }

  /* ----------------------------- lettura ----------------------------- */
  List<Doc> elenco(String collezione, {bool archiviati = false}) {
    final v = _c[collezione]?.values ?? const <Doc>[];
    return archiviati ? v.toList() : v.where((d) => d['archiviato'] != true).toList();
  }

  Doc? get(String collezione, String? id) => id == null ? null : _c[collezione]?[id];
  int conta(String collezione) => elenco(collezione).length;

  /* ----------------------------- scrittura ----------------------------- */
  Doc _timbra(Doc d) {
    final ora = adessoIso();
    d['id'] ??= uid();
    d['createdAt'] ??= ora;
    d['updatedAt'] = ora;
    return d;
  }

  Future<Doc> salva(String collezione, Doc doc) async {
    _timbra(doc);
    _c[collezione]![comeStr(doc['id'])] = doc;
    await _archivio.scrivi(collezione, [doc]);
    _dopoModifica(collezione);
    return doc;
  }

  Future<void> salvaMolti(String collezione, List<Doc> docs) async {
    if (docs.isEmpty) return;
    for (final d in docs) {
      _timbra(d);
      _c[collezione]![comeStr(d['id'])] = d;
    }
    await _archivio.scrivi(collezione, docs);
    _dopoModifica(collezione);
  }

  /// Eliminazione definitiva. Lascia una "lapide" per avvisare gli altri dispositivi via cloud.
  Future<void> elimina(String collezione, String id, {bool lapide = true}) => eliminaMolti(collezione, [id], lapide: lapide);

  Future<void> eliminaMolti(String collezione, List<String> ids, {bool lapide = true}) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      _c[collezione]!.remove(id);
    }
    await _archivio.elimina(collezione, ids);
    if (collezione == 'foto') await _archivio.eliminaBytes(ids);
    if (lapide && collezione != 'meta') {
      final quando = adessoIso();
      final lapidi = ids.map((id) => <String, dynamic>{'id': 'elim:$collezione:$id', 'valore': {'archivio': collezione, 'recordId': id, 'quando': quando}}).toList();
      for (final l in lapidi) {
        _c['meta']![l['id'] as String] = l;
      }
      await _archivio.scrivi('meta', lapidi);
    }
    _dopoModifica(collezione);
  }

  Future<Doc?> archivia(String collezione, String id) async {
    final d = get(collezione, id);
    if (d == null) return null;
    d['archiviato'] = true;
    d['archiviatoIl'] = adessoIso();
    return salva(collezione, d);
  }

  Future<Doc?> ripristina(String collezione, String id) async {
    final d = get(collezione, id);
    if (d == null) return null;
    d['archiviato'] = false;
    d.remove('archiviatoIl');
    return salva(collezione, d);
  }

  /// Scrittura "grezza" senza cambiare updatedAt (dati arrivati dal cloud o da un backup).
  Future<void> scriviGrezzi(String collezione, List<Doc> docs, {bool notifica = true}) async {
    if (docs.isEmpty) return;
    for (final d in docs) {
      _c[collezione]![comeStr(d['id'])] = d;
    }
    await _archivio.scrivi(collezione, docs);
    if (collezione == 'impostazioni') _ricaricaConfig();
    if (notifica) notifyListeners();
  }

  Future<void> eliminaGrezzi(String collezione, List<String> ids) async {
    for (final id in ids) {
      _c[collezione]!.remove(id);
    }
    await _archivio.elimina(collezione, ids);
    if (collezione == 'foto') await _archivio.eliminaBytes(ids);
  }

  /// Sostituisce TUTTI i dati (ripristino di un backup). Le foto: [fotoBytes] id → byte.
  Future<void> sostituisciTutto(Map<String, List<Doc>> dati, {Map<String, Uint8List>? fotoBytes, bool tieniFotoAttuali = false}) async {
    final localiDaTenere = elenco('meta', archiviati: true).where((m) => metaLocali.contains(m['id'])).toList();
    final nuovi = <String, List<Doc>>{for (final a in archivi) a: List<Doc>.from(dati[a] ?? const <Doc>[])};
    nuovi['meta'] = [
      ...nuovi['meta']!.where((m) => !metaLocali.contains(m['id']) && m['id'] != 'schemaVersion' && !comeStr(m['id']).startsWith('elim:')),
      ...localiDaTenere,
      {'id': 'schemaVersion', 'valore': schemaVersion},
    ];
    if (tieniFotoAttuali) nuovi['foto'] = elenco('foto', archiviati: true);
    await _archivio.sostituisciTutto(nuovi);
    if (!tieniFotoAttuali) {
      final vecchie = await _archivio.idBytes();
      await _archivio.eliminaBytes(vecchie);
      for (final e in (fotoBytes ?? const <String, Uint8List>{}).entries) {
        await _archivio.scriviBytes(e.key, e.value);
      }
    }
    for (final a in archivi) {
      _c[a] = {for (final d in nuovi[a]!) comeStr(d['id']): d};
    }
    _ricaricaConfig();
    notifyListeners();
  }

  Future<Uint8List?> bytesFoto(String id) => _archivio.leggiBytes(id);
  Future<void> salvaBytesFoto(String id, Uint8List b) => _archivio.scriviBytes(id, b);

  void _dopoModifica(String collezione) {
    if (collezione == 'impostazioni') _ricaricaConfig();
    notifyListeners();
    if (!_silenzioso && collezione != 'meta') suModifica?.call(collezione);
  }

  /// Esegue più operazioni con un solo aggiornamento dell'interfaccia.
  Future<T> inBlocco<T>(Future<T> Function() fn) async {
    final prima = _silenzioso;
    _silenzioso = true;
    try {
      return await fn();
    } finally {
      _silenzioso = prima;
      notifyListeners();
      if (!prima) suModifica?.call('*');
    }
  }

  /* ----------------------------- meta ----------------------------- */
  dynamic meta(String id) => _c['meta']![id]?['valore'];
  Future<void> scriviMeta(String id, dynamic valore) async {
    final d = <String, dynamic>{'id': id, 'valore': valore};
    _c['meta']![id] = d;
    await _archivio.scrivi('meta', [d]);
  }

  Future<void> eliminaMeta(List<String> ids) async {
    for (final id in ids) {
      _c['meta']!.remove(id);
    }
    await _archivio.elimina('meta', ids);
  }

  /* ----------------------------- configurazione ----------------------------- */
  Doc get cfg => _config;
  void _ricaricaConfig() {
    final salvata = _c['impostazioni']!['config'];
    _config = comeDoc(unisciProfondo(configPredefinita, salvata == null ? null : salvata['valori']));
    final ops = comeListaDoc(_config['operatrici']);
    if (ops.isEmpty) _config['operatrici'] = clona(configPredefinita['operatrici']);
  }

  Future<void> salvaConfig(Doc nuova) async {
    final valori = comeDoc(unisciProfondo(configPredefinita, nuova));
    final rec = _c['impostazioni']!['config'] ?? <String, dynamic>{'id': 'config'};
    rec['valori'] = valori;
    await salva('impostazioni', rec);
  }

  /// Moduli attivabili da Impostazioni (un modulo spento sparisce da menu e cruscotto).
  /// "ordini" richiede anche "magazzino": senza prodotti non ci sono righe d'ordine.
  bool moduloAttivo(String m) {
    final mod = comeDoc(_config['moduli']);
    if (mod[m] == false) return false;
    if (m == 'ordini' && mod['magazzino'] == false) return false;
    return true;
  }
  List<Doc> get operatrici => comeListaDoc(_config['operatrici']);
  bool get piuOperatrici => operatrici.length > 1;
  int get slotMinuti => comeInt(comeDoc(_config['agenda'])['slotMinuti']) ?? 15;
  int get cuscinettoMinuti => comeInt(comeDoc(_config['agenda'])['cuscinettoMinuti']) ?? 10;
  String get prefisso => comeStr(comeDoc(_config['attivita'])['prefissoInternazionale']).isEmpty ? '39' : comeStr(comeDoc(_config['attivita'])['prefissoInternazionale']);
  String get nomeAttivita => comeStr(comeDoc(_config['attivita'])['nome']);
}
