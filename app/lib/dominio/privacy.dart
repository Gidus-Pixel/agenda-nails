import 'dart:convert';

import '../core/util.dart';
import '../dati/dati.dart';

/// Esportazione dei dati di una singola cliente (diritto di accesso / portabilità, GDPR).
/// Stessa forma della versione web; le foto sono incluse come dataURL.
Future<Doc> esportaDatiCliente(Dati d, String id) async {
  final c = d.get('clienti', id);
  final foto = <Doc>[];
  for (final f in d.elenco('foto', archiviati: true).where((f) => f['clienteId'] == id)) {
    final b = await d.bytesFoto(comeStr(f['id']));
    foto.add({...f, if (b != null) 'dataURL': 'data:${comeStr(f['blobTipo']).isEmpty ? 'image/jpeg' : f['blobTipo']};base64,${base64Encode(b)}'});
  }
  return {
    'esportatoIl': adessoIso(),
    'attivita': d.nomeAttivita,
    'cliente': c,
    'appuntamenti': d.elenco('appuntamenti', archiviati: true).where((a) => a['clienteId'] == id).toList(),
    'schedeLavoro': d.elenco('schede_lavoro', archiviati: true).where((s) => s['clienteId'] == id).toList(),
    'appunti': d.elenco('appunti', archiviati: true).where((a) => comeDoc(a['collegamento'])['tipo'] == 'cliente' && comeDoc(a['collegamento'])['id'] == id).toList(),
    'foto': foto,
  };
}

/// Cancellazione di una cliente: i dati personali e le foto spariscono, appuntamenti e schede
/// restano anonimi (le statistiche non cambiano). Identica alla versione web.
Future<void> eliminaClienteConAnonimizzazione(Dati d, String id) async {
  final anon = 'anon-${uid()}';
  await d.inBlocco(() async {
    final apps = d.elenco('appuntamenti', archiviati: true).where((a) => a['clienteId'] == id).toList();
    for (final a in apps) {
      a['clienteId'] = anon;
      a['clienteNome'] = 'Cliente eliminata';
      a['note'] = '';
    }
    final schede = d.elenco('schede_lavoro', archiviati: true).where((s) => s['clienteId'] == id).toList();
    for (final s in schede) {
      s['clienteId'] = anon;
      s['note'] = '';
      s['noteProssimaVolta'] = '';
      s['fotoIds'] = <String>[];
    }
    final appunti = d.elenco('appunti', archiviati: true).where((a) => comeDoc(a['collegamento'])['tipo'] == 'cliente' && comeDoc(a['collegamento'])['id'] == id).toList();
    for (final a in appunti) {
      a['collegamento'] = null;
    }
    final foto = d.elenco('foto', archiviati: true).where((f) => f['clienteId'] == id).map((f) => comeStr(f['id'])).toList();
    await d.salvaMolti('appuntamenti', apps);
    await d.salvaMolti('schede_lavoro', schede);
    await d.salvaMolti('appunti', appunti);
    await d.eliminaMolti('foto', foto);
    await d.elimina('clienti', id);
  });
}
