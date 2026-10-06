import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import 'agenda.dart';
import 'magazzino.dart';

/// Stato del promemoria di un appunto: (testo, tipo) con tipo pericolo | avviso | info; null se non c'è o è fatto.
(String, String)? statoPromemoria(Doc a) {
  final p = comeStr(a['promemoria']);
  if (p.isEmpty || a['fatto'] == true) return null;
  final oggi = D.oggiKey();
  if (p.compareTo(oggi) < 0) return ('scaduto ${F.dataKey(p)}', 'pericolo');
  if (p == oggi) return ('oggi', 'avviso');
  return (F.dataKey(p), 'info');
}

List<Doc> promemoriaInArrivo(Dati d, {int giorni = 7}) {
  final limite = D.aggiungiGiorniKey(D.oggiKey(), giorni);
  return d.elenco('appunti').where((a) => comeStr(a['promemoria']).isNotEmpty && a['fatto'] != true && comeStr(a['promemoria']).compareTo(limite) <= 0).toList()
    ..sort((a, b) => comeStr(a['promemoria']).compareTo(comeStr(b['promemoria'])));
}

/// Fissati in alto, poi i più recenti.
List<Doc> ordinaAppunti(List<Doc> lista) => lista
  ..sort((a, b) {
    final f = (b['fissato'] == true ? 1 : 0) - (a['fissato'] == true ? 1 : 0);
    return f != 0 ? f : comeStr(b['updatedAt']).compareTo(comeStr(a['updatedAt']));
  });

List<Doc> appuntiCollegati(Dati d, String tipo, String id) =>
    ordinaAppunti(d.elenco('appunti').where((a) => comeDoc(a['collegamento'])['tipo'] == tipo && comeDoc(a['collegamento'])['id'] == id).toList());

String? nomeCollegamento(Dati d, dynamic c) {
  final col = comeDoc(c);
  final tipo = comeStr(col['tipo']), id = comeStr(col['id']);
  if (tipo.isEmpty || id.isEmpty) return null;
  switch (tipo) {
    case 'cliente':
      final x = d.get('clienti', id);
      return x != null ? nomeCliente(x) : 'Cliente eliminata';
    case 'fornitore':
      final x = d.get('fornitori', id);
      return x != null ? nomeFornitore(x) : 'Fornitore eliminato';
    case 'prodotto':
      final x = d.get('prodotti', id);
      return x != null ? nomeProdotto(x) : 'Prodotto eliminato';
    case 'appuntamento':
      final x = d.get('appuntamenti', id);
      if (x == null) return 'Appuntamento eliminato';
      final cl = d.get('clienti', comeStr(x['clienteId']));
      return '${F.giornoBreve(inizioApp(x))} ${D.hhmm(inizioApp(x))} · ${cl != null ? nomeCliente(cl) : comeStr(x['clienteNome'])}';
  }
  return null;
}

Doc appuntoVuoto({Doc? collegamento}) => {'titolo': '', 'testo': '', 'tag': <String>[], 'fissato': false, 'colore': 'giallo', 'promemoria': '', 'fatto': false, 'collegamento': collegamento, 'archiviato': false};

/// Ricerca a parole: tutte le parole devono comparire in titolo, testo o tag.
bool appuntoCorrisponde(Doc a, String q) {
  final testo = norm([comeStr(a['titolo']), comeStr(a['testo']), ...comeListaStr(a['tag'])].join(' '));
  return norm(q).trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).every(testo.contains);
}
