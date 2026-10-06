import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../fornitori/ordini.dart' show scegliProdotto;
import '../tema.dart';
import 'pagina_altro.dart';

/// Listino servizi: nome, categoria, durata, prezzo, colore, tempo di pulizia, richiamo.
class PaginaServizi extends StatelessWidget {
  const PaginaServizi({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Servizi e listino')),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'servizi-nuovo', onPressed: () => apriModuloServizio(context), icon: const Icon(Icons.add_rounded), label: const Text('Nuovo servizio')),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final t = Theme.of(context).textTheme;
          final cs = Theme.of(context).colorScheme;
          final lista = serviziAttivi(d);
          final perCat = <String, List<Doc>>{};
          for (final s in lista) {
            perCat.putIfAbsent(comeStr(s['categoria']).isEmpty ? 'Altro' : comeStr(s['categoria']), () => []).add(s);
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, 100), children: [
                if (lista.isEmpty)
                  const Vuoto('Nessun servizio. Aggiungi i servizi che offri: durata e prezzo verranno proposti in automatico negli appuntamenti.', icona: Icons.spa_outlined),
                for (final e in perCat.entries) ...[
                  Padding(padding: const EdgeInsets.fromLTRB(S.s, S.l, S.s, S.s), child: Text(e.key.toUpperCase(), style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 1))),
                  Card(
                    child: Column(children: [
                      for (final s in e.value)
                        ListTile(
                          leading: CircleAvatar(radius: 10, backgroundColor: Color(coloreNum(s['colore']))),
                          title: Text(comeStr(s['nome'])),
                          subtitle: Text([
                            F.durata(comeInt(s['durata'])),
                            if ((comeInt(s['richiamoGiorni']) ?? 0) > 0) 'richiamo dopo ${s['richiamoGiorni']} gg',
                            if (s['cuscinetto'] != null) 'pulizia ${s['cuscinetto']} min',
                          ].join(' · ')),
                          trailing: Text(F.euro(comeInt(s['prezzoCent'])), style: t.titleSmall),
                          onTap: () => apriModuloServizio(context, servizio: s),
                        ),
                    ]),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}

Future<void> apriModuloServizio(BuildContext context, {Doc? servizio}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _ModuloServizio(servizio: servizio)));
}

class _ModuloServizio extends StatefulWidget {
  const _ModuloServizio({this.servizio});
  final Doc? servizio;
  @override
  State<_ModuloServizio> createState() => _ModuloServizioState();
}

class _ModuloServizioState extends State<_ModuloServizio> {
  final _nome = TextEditingController(), _durata = TextEditingController(), _prezzo = TextEditingController(), _richiamo = TextEditingController(), _cusc = TextEditingController(), _cat = TextEditingController();
  late int _colore;

  @override
  void initState() {
    super.initState();
    final s = widget.servizio;
    final d = Ambito.of(context).dati;
    _nome.text = comeStr(s?['nome']);
    _durata.text = s == null ? '60' : comeStr(s['durata']);
    _prezzo.text = s == null ? '' : F.testoDaCent(comeInt(s['prezzoCent']));
    _richiamo.text = comeStr(s?['richiamoGiorni']);
    _cusc.text = comeStr(s?['cuscinetto']);
    _cat.text = comeStr(s?['categoria']);
    _colore = coloreNum(s?['colore'], paletteServizi[d.conta('servizi') % paletteServizi.length]);
    _prodotti = comeListaDoc(s?['prodottiDefault']).map(clonaDoc).toList();
  }

  List<Doc> _prodotti = [];

  @override
  void dispose() {
    for (final c in [_nome, _durata, _prezzo, _richiamo, _cusc, _cat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salva() async {
    final d = context.dati;
    final durata = int.tryParse(_durata.text.trim()) ?? 0;
    if (_nome.text.trim().isEmpty || durata <= 0) {
      avviso(context, 'Servono almeno il nome e una durata in minuti.', errore: true);
      return;
    }
    final rec = widget.servizio != null ? widget.servizio! : <String, dynamic>{'prodottiDefault': <Doc>[], 'archiviato': false, 'ordine': d.conta('servizi')};
    rec['nome'] = _nome.text.trim();
    rec['categoria'] = _cat.text.trim().isEmpty ? 'Altro' : _cat.text.trim();
    rec['durata'] = durata;
    rec['prezzoCent'] = F.centDaTesto(_prezzo.text) ?? 0;
    rec['richiamoGiorni'] = int.tryParse(_richiamo.text.trim());
    rec['cuscinetto'] = int.tryParse(_cusc.text.trim());
    rec['colore'] = esadecimale(_colore);
    rec['prodottiDefault'] = [for (final x in _prodotti) if (numero(x['quantita']) > 0) {'prodottoId': x['prodottoId'], 'quantita': qta(numero(x['quantita']))}];
    await d.salva('servizi', rec);
    if (!mounted) return;
    Navigator.pop(context);
    avvisa('Servizio salvato');
  }

  Future<void> _archivia() async {
    final d = context.dati;
    final id = comeStr(widget.servizio!['id']);
    Navigator.pop(context);
    await d.archivia('servizi', id);
    avvisa('Servizio tolto dal listino (gli appuntamenti passati non cambiano)', annulla: () async => d.ripristina('servizi', id));
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final categorie = {...comeListaStr(d.cfg['categorieServizi']), for (final s in d.elenco('servizi')) comeStr(s['categoria'])}.where((x) => x.isNotEmpty).toList();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: Text(widget.servizio == null ? 'Nuovo servizio' : 'Servizio'),
        actions: [
          if (widget.servizio != null) IconButton(tooltip: 'Togli dal listino', onPressed: _archivia, icon: const Icon(Icons.archive_outlined)),
          Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salva, child: const Text('Salva'))),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(S.l), children: [
              Campo(etichetta: 'Nome', controller: _nome, autofocus: widget.servizio == null, placeholder: 'es. Refill gel'),
              Text('Categoria', style: t.labelLarge),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in categorie) ChoiceChip(label: Text(c), selected: _cat.text == c, onSelected: (_) => setState(() => _cat.text = c)),
              ]),
              const SizedBox(height: S.s),
              Campo(etichetta: 'Oppure una nuova categoria', controller: _cat, suCambio: (_) => setState(() {})),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Campo(etichetta: 'Durata (minuti)', controller: _durata, tastiera: TextInputType.number)),
                const SizedBox(width: S.m),
                Expanded(child: Campo(etichetta: 'Prezzo (€)', controller: _prezzo, tastiera: const TextInputType.numberWithOptions(decimal: true))),
              ]),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Campo(etichetta: 'Richiamo dopo (giorni)', controller: _richiamo, tastiera: TextInputType.number, aiuto: 'es. 21 per il refill: la cliente compare in "Da ricontattare".')),
                const SizedBox(width: S.m),
                Expanded(child: Campo(etichetta: 'Pulizia dopo (min)', controller: _cusc, tastiera: TextInputType.number, aiuto: 'Vuoto = ${d.cuscinettoMinuti} min (valore generale).')),
              ]),
              Text('Colore in agenda', style: t.labelLarge),
              const SizedBox(height: S.s),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final p in paletteServizi)
                  GestureDetector(
                    onTap: () => setState(() => _colore = p),
                    child: CircleAvatar(radius: 20, backgroundColor: Color(p), child: (p & 0xFFFFFF) == (_colore & 0xFFFFFF) ? const Icon(Icons.check_rounded, color: Colors.white) : null),
                  ),
              ]),
              if (d.moduloAttivo('magazzino')) ...[
                const SizedBox(height: S.xl),
                Sezione(
                  titolo: 'Prodotti consumati di default',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Quando completi un appuntamento con questo servizio, la scheda lavoro propone questi prodotti da scalare dal magazzino (moltiplicati per la quantità del servizio).', style: t.bodySmall),
                    const SizedBox(height: S.s),
                    for (final x in _prodotti)
                      Row(key: ObjectKey(x), children: [
                        Expanded(flex: 3, child: Text(nomeProdotto(d.get('prodotti', comeStr(x['prodottoId']))), style: t.bodyLarge)),
                        Expanded(
                          child: TextFormField(
                            initialValue: testoQta(x['quantita']),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(suffixText: comeStr(d.get('prodotti', comeStr(x['prodottoId']))?['unita'])),
                            onChanged: (v) => x['quantita'] = qtaDaTesto(v) ?? 0,
                          ),
                        ),
                        IconButton(onPressed: () => setState(() => _prodotti.remove(x)), icon: const Icon(Icons.close_rounded), tooltip: 'Togli'),
                      ]),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final p = await scegliProdotto(context);
                          if (p != null && !_prodotti.any((x) => x['prodottoId'] == p['id'])) setState(() => _prodotti.add({'prodottoId': p['id'], 'quantita': 1}));
                        },
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Aggiungi prodotto'),
                      ),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: S.xl),
              FilledButton(onPressed: _salva, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Salva')),
            ]),
          ),
        ),
      ),
    );
  }
}
