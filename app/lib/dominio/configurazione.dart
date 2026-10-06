import 'dart:convert';
import 'dart:typed_data';

import '../core/config.dart';
import '../core/util.dart';
import '../dati/dati.dart';

/// Configurazione da esportare/importare (per preparare installazioni per altre estetiste).
/// Stesso formato della web app.
Uint8List esportaConfigurazione(Dati d) {
  final servizi = d.elenco('servizi').map((s) {
    final r = clonaDoc(s);
    for (final k in ['id', 'createdAt', 'updatedAt', 'demo', 'archiviato', 'prodottiDefault']) {
      r.remove(k);
    }
    return r;
  }).toList();
  final out = {'app': appId, 'tipo': 'configurazione', 'schemaVersion': schemaVersion, 'esportatoIl': adessoIso(), 'config': clonaDoc(d.cfg), 'servizi': servizi};
  return Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(out)));
}

/// Controlla il file; restituisce l'oggetto se è una configurazione valida.
Doc? leggiConfigurazione(Uint8List b) {
  try {
    final obj = comeDoc(jsonDecode(utf8.decode(b)));
    if (obj['app'] != appId || obj['tipo'] != 'configurazione' || obj['config'] is! Map) return null;
    return obj;
  } catch (_) {
    return null;
  }
}

Doc normalizzaServizio(Doc s, int i) {
  int? n(dynamic v) => (v == null || v == '') ? null : comeInt(v);
  return {
    'nome': comeStr(s['nome']).trim(),
    'categoria': comeStr(s['categoria']).isEmpty ? 'Altro' : comeStr(s['categoria']),
    'durata': n(s['durata']) ?? 0,
    'prezzoCent': s['prezzoCent'] != null ? (n(s['prezzoCent']) ?? 0) : 0,
    'colore': comeStr(s['colore']).isEmpty ? esadecimale(paletteServizi[i % paletteServizi.length]) : comeStr(s['colore']),
    'cuscinetto': n(s['cuscinetto']),
    'richiamoGiorni': n(s['richiamoGiorni']),
    'ordine': n(s['ordine']) ?? i,
  };
}

/// Importa: sostituisce le impostazioni, aggiorna/aggiunge i servizi per nome (non cancella nulla).
Future<void> importaConfigurazione(Dati d, Doc obj) async {
  await d.inBlocco(() async {
    await d.salvaConfig(comeDoc(obj['config']));
    final esistenti = d.elenco('servizi', archiviati: true);
    final daSalvare = <Doc>[];
    final servizi = comeListaDoc(obj['servizi']);
    for (var i = 0; i < servizi.length; i++) {
      final s = servizi[i];
      if (comeStr(s['nome']).trim().isEmpty) continue;
      final e = esistenti.where((x) => norm(comeStr(x['nome'])) == norm(comeStr(s['nome']))).firstOrNull;
      daSalvare.add({...(e ?? <String, dynamic>{'prodottiDefault': <Doc>[]}), ...normalizzaServizio(s, i), 'archiviato': false});
    }
    await d.salvaMolti('servizi', daSalvare);
    await d.scriviMeta('seedServizi', true);
  });
}

/// Primo avvio: i servizi scritti nella configurazione predefinita diventano il listino.
Future<void> seminaServizi(Dati d) async {
  if (d.meta('seedServizi') == true) return;
  final cfgServ = comeListaDoc(d.cfg['servizi']);
  if (d.elenco('servizi', archiviati: true).isEmpty && cfgServ.isNotEmpty) {
    await d.salvaMolti('servizi', [for (var i = 0; i < cfgServ.length; i++) {...normalizzaServizio(cfgServ[i], i), 'prodottiDefault': <Doc>[], 'archiviato': false}]);
  }
  await d.scriviMeta('seedServizi', true);
}
