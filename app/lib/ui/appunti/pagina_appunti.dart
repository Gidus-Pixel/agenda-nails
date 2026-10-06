import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../../dominio/appunti.dart';
import '../../dominio/magazzino.dart';
import '../agenda/dettaglio_appuntamento.dart';
import '../app.dart';
import '../clienti/scheda_cliente.dart';
import '../comuni.dart';
import '../fornitori/scheda_fornitore.dart';
import '../magazzino/scheda_prodotto.dart';
import '../tema.dart';

/// Appunti: note colorate con tag, fissate in alto, promemoria e collegamenti.
class PaginaAppunti extends StatefulWidget {
  const PaginaAppunti({super.key});
  @override
  State<PaginaAppunti> createState() => _PaginaAppuntiState();
}

class _PaginaAppuntiState extends State<PaginaAppunti> {
  final _cerca = TextEditingController();
  String _filtro = '';
  String? _tag;

  @override
  void initState() {
    super.initState();
    _cerca.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cerca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Appunti')),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'appunti-nuovo', onPressed: () => apriAppunto(context), icon: const Icon(Icons.add_rounded), label: const Text('Appunto')),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final tutti = ordinaAppunti(d.elenco('appunti'));
          final tags = {for (final a in tutti) ...comeListaStr(a['tag'])}.toList()..sort();
          final lista = tutti.where((a) {
            if (_tag != null && !comeListaStr(a['tag']).contains(_tag)) return false;
            if (_filtro == 'fissati' && a['fissato'] != true) return false;
            if (_filtro == 'promemoria' && comeStr(a['promemoria']).isEmpty) return false;
            if (_filtro == 'dafare' && !(comeStr(a['promemoria']).isNotEmpty && a['fatto'] != true)) return false;
            if (_cerca.text.trim().isNotEmpty && !appuntoCorrisponde(a, _cerca.text)) return false;
            return true;
          }).toList();
          Widget chip(String k, String t) => Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text(t), selected: _filtro == k, onSelected: (_) => setState(() => _filtro = k)));
          return ListView(padding: const EdgeInsets.only(bottom: 100), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.s),
              child: TextField(controller: _cerca, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cerca nel titolo, nel testo e nei tag')),
            ),
            SizedBox(
              height: 46,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.l), children: [
                chip('', 'Tutti'), chip('fissati', 'Fissati'), chip('promemoria', 'Con promemoria'), chip('dafare', 'Da fare'),
                for (final t in tags) Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text('#$t'), selected: _tag == t, onSelected: (s) => setState(() => _tag = s ? t : null))),
              ]),
            ),
            const SizedBox(height: S.s),
            if (lista.isEmpty) Vuoto(tutti.isEmpty ? 'Nessun appunto. Scrivi il primo con "Appunto": idee, cose da ordinare, preferenze delle clienti…' : 'Nessun appunto corrisponde.', icona: Icons.sticky_note_2_outlined),
            Padding(padding: const EdgeInsets.symmetric(horizontal: S.l), child: GrigliaAppunti(lista: lista)),
          ]);
        },
      ),
    );
  }
}

/// Griglia di "post-it" (una colonna sul telefono, più colonne su tablet).
class GrigliaAppunti extends StatelessWidget {
  const GrigliaAppunti({super.key, required this.lista, this.mostraCollegamento = true});
  final List<Doc> lista;
  final bool mostraCollegamento;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, v) {
      final colonne = (v.maxWidth / 300).floor().clamp(1, 4);
      final w = (v.maxWidth - S.m * (colonne - 1)) / colonne;
      return Wrap(spacing: S.m, runSpacing: S.m, children: [for (final a in lista) SizedBox(width: w, child: CartaAppunto(a: a, mostraCollegamento: mostraCollegamento))]);
    });
  }
}

class CartaAppunto extends StatelessWidget {
  const CartaAppunto({super.key, required this.a, this.mostraCollegamento = true});
  final Doc a;
  final bool mostraCollegamento;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    const testo = Color(0xFF1F1A1B);
    final st = statoPromemoria(a);
    final link = mostraCollegamento ? nomeCollegamento(d, a['collegamento']) : null;
    final corpo = comeStr(a['testo']);
    return Material(
      color: Color(coloriAppunti[a['colore']] ?? coloriAppunti['giallo']!),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => apriAppunto(context, appunto: a),
        child: Padding(
          padding: const EdgeInsets.all(S.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (a['fissato'] == true) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.push_pin_rounded, size: 18, color: testo)),
              Expanded(child: Text(comeStr(a['titolo']).isEmpty ? 'Senza titolo' : comeStr(a['titolo']), style: t.titleMedium?.copyWith(color: testo))),
              if (a['demo'] == true) const Text('PROVA', style: TextStyle(color: testo, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
            if (corpo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(corpo, maxLines: 8, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: testo))),
            if (st != null || (comeStr(a['promemoria']).isNotEmpty && a['fatto'] == true) || link != null || comeListaStr(a['tag']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: S.s),
                child: Wrap(spacing: 4, runSpacing: 4, children: [
                  if (st != null) EtichettaTipo('⏰ ${st.$1}', st.$2) else if (comeStr(a['promemoria']).isNotEmpty && a['fatto'] == true) const EtichettaTipo('✓ fatto', 'ok'),
                  if (link != null)
                    ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.white.withValues(alpha: 0.55),
                      side: BorderSide.none,
                      label: Text('🔗 ${tipiCollegamento[comeDoc(a['collegamento'])['tipo']]}: $link', style: const TextStyle(color: testo, fontSize: 12)),
                      onPressed: () => apriCollegamento(context, a['collegamento']),
                    ),
                  for (final tg in comeListaStr(a['tag'])) Text('#$tg  ', style: const TextStyle(color: testo, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

void apriCollegamento(BuildContext context, dynamic c) {
  final col = comeDoc(c);
  final id = comeStr(col['id']);
  final d = context.dati;
  switch (col['tipo']) {
    case 'cliente':
      if (d.get('clienti', id) != null) apriSchedaCliente(context, id);
    case 'fornitore':
      if (d.get('fornitori', id) != null) apriFornitore(context, id);
    case 'prodotto':
      if (d.get('prodotti', id) != null) apriProdotto(context, id);
    case 'appuntamento':
      final a = d.get('appuntamenti', id);
      if (a != null) apriAppuntamento(context, a);
  }
}

/// Sezione "Appunti" dentro una scheda collegata (cliente, fornitore, prodotto).
class SezioneAppunti extends StatelessWidget {
  const SezioneAppunti({super.key, required this.tipo, required this.id});
  final String tipo, id;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final lista = appuntiCollegati(d, tipo, id);
    final t = Theme.of(context).textTheme;
    return Sezione(
      titolo: 'Appunti (${lista.length})',
      azione: TextButton.icon(onPressed: () => apriAppunto(context, collegamento: {'tipo': tipo, 'id': id}), icon: const Icon(Icons.add_rounded), label: const Text('Appunto')),
      child: lista.isEmpty ? Text('Nessun appunto collegato.', style: t.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)) : GrigliaAppunti(lista: lista, mostraCollegamento: false),
    );
  }
}

/* ================================ Modulo appunto ================================ */
Future<void> apriAppunto(BuildContext context, {Doc? appunto, Doc? collegamento}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _ModuloAppunto(appunto: appunto, collegamento: collegamento)));
}

class _ModuloAppunto extends StatefulWidget {
  const _ModuloAppunto({this.appunto, this.collegamento});
  final Doc? appunto;
  final Doc? collegamento;
  @override
  State<_ModuloAppunto> createState() => _ModuloAppuntoState();
}

class _ModuloAppuntoState extends State<_ModuloAppunto> {
  late final Doc _a = widget.appunto != null ? clonaDoc(widget.appunto!) : appuntoVuoto(collegamento: widget.collegamento);
  late final _titolo = TextEditingController(text: comeStr(_a['titolo']));
  late final _testo = TextEditingController(text: comeStr(_a['testo']));
  late final _tag = TextEditingController(text: comeListaStr(_a['tag']).join(', '));
  final _cercaColl = TextEditingController();
  late String _colore = comeStr(_a['colore']).isEmpty ? 'giallo' : comeStr(_a['colore']);
  late bool _fissato = _a['fissato'] == true, _fatto = _a['fatto'] == true;
  late String _promemoria = comeStr(_a['promemoria']);
  late Doc? _coll = _a['collegamento'] is Map ? comeDoc(_a['collegamento']) : null;
  String _tipoColl = 'cliente';

  @override
  void dispose() {
    for (final c in [_titolo, _testo, _tag, _cercaColl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salva() async {
    final d = context.dati;
    final titolo = _titolo.text.trim(), testo = _testo.text.trim();
    if (titolo.isEmpty && testo.isEmpty) {
      avviso(context, 'Scrivi almeno un titolo o un testo.', errore: true);
      return;
    }
    _a.addAll({
      'titolo': titolo, 'testo': testo,
      'tag': {for (final x in _tag.text.split(',')) if (x.trim().replaceFirst('#', '').isNotEmpty) x.trim().replaceFirst('#', '')}.toList(),
      'colore': _colore, 'fissato': _fissato, 'promemoria': _promemoria, 'fatto': _fatto, 'collegamento': _coll,
    });
    await d.salva('appunti', _a);
    if (!mounted) return;
    Navigator.pop(context);
    avvisa(widget.appunto == null ? 'Appunto salvato' : 'Appunto aggiornato');
  }

  Future<void> _elimina() async {
    final d = context.dati;
    final id = comeStr(widget.appunto!['id']);
    Navigator.pop(context);
    await d.archivia('appunti', id);
    avvisa('Appunto eliminato', annulla: () async => d.ripristina('appunti', id));
  }

  List<(String, String)> _risultati() {
    final d = context.dati;
    final q = norm(_cercaColl.text.trim());
    if (q.isEmpty) return [];
    final List<(String, String)> voci = switch (_tipoColl) {
      'cliente' => [for (final c in d.elenco('clienti')) if (norm('${nomeCliente(c)} ${c['telefono'] ?? ''}').contains(q)) (comeStr(c['id']), nomeCliente(c))],
      'fornitore' => [for (final f in d.elenco('fornitori')) if (norm(nomeFornitore(f)).contains(q)) (comeStr(f['id']), nomeFornitore(f))],
      'prodotto' => [for (final p in d.elenco('prodotti')) if (norm([p['nome'], p['marca'], p['codiceColore']].map(comeStr).join(' ')).contains(q)) (comeStr(p['id']), nomeProdottoConMarca(p))],
      _ => [
          for (final x in (d.elenco('appuntamenti')..sort((a, b) => comeStr(b['inizio']).compareTo(comeStr(a['inizio'])))))
            if (norm('${nomeCliente(d.get('clienti', comeStr(x['clienteId'])))} ${x['clienteNome'] ?? ''} ${F.data(inizioApp(x))}').contains(q))
              (comeStr(x['id']), '${F.giornoBreve(inizioApp(x))} ${D.hhmm(inizioApp(x))} · ${nomeClienteDi(d, x)}'),
        ],
    };
    return voci.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final nomeColl = _coll == null ? null : nomeCollegamento(d, _coll);
    final tipiAttivi = tipiCollegamento.entries.where((e) => switch (e.key) {
          'fornitore' => d.moduloAttivo('fornitori'),
          'prodotto' => d.moduloAttivo('magazzino'),
          'appuntamento' => d.moduloAttivo('agenda'),
          _ => true,
        });
    return Scaffold(
      backgroundColor: Color.lerp(cs.surface, Color(coloriAppunti[_colore]!), Theme.of(context).brightness == Brightness.dark ? 0.08 : 0.35),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: Text(widget.appunto == null ? 'Nuovo appunto' : 'Appunto'),
        actions: [
          IconButton(tooltip: _fissato ? 'Togli da in alto' : 'Fissa in alto', onPressed: () => setState(() => _fissato = !_fissato), icon: Icon(_fissato ? Icons.push_pin_rounded : Icons.push_pin_outlined)),
          if (widget.appunto != null) IconButton(tooltip: 'Elimina', onPressed: _elimina, icon: const Icon(Icons.delete_outline_rounded)),
          Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salva, child: const Text('Salva'))),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              TextField(controller: _titolo, autofocus: widget.appunto == null, style: t.headlineSmall, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Titolo', border: InputBorder.none, filled: false)),
              TextField(controller: _testo, maxLines: null, minLines: 6, style: t.bodyLarge, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Scrivi qui…', border: InputBorder.none, filled: false)),
              const Divider(height: S.xl),
              Text('Colore', style: t.labelLarge),
              const SizedBox(height: S.s),
              Wrap(spacing: S.m, children: [
                for (final e in coloriAppunti.entries)
                  GestureDetector(
                    onTap: () => setState(() => _colore = e.key),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: Color(e.value), shape: BoxShape.circle, border: Border.all(color: _colore == e.key ? cs.onSurface : cs.outlineVariant, width: _colore == e.key ? 3 : 1)),
                    ),
                  ),
              ]),
              const SizedBox(height: S.l),
              Campo(etichetta: 'Tag (separati da virgola)', controller: _tag, placeholder: 'es. ordini, idee, formazione', maiuscole: TextCapitalization.none),
              Row(children: [
                Expanded(child: Text('Promemoria', style: t.labelLarge)),
                TextButton(
                  onPressed: () async {
                    final g = await scegliData(context, _promemoria.isEmpty ? DateTime.now() : D.daKey(_promemoria));
                    if (g != null) setState(() => _promemoria = D.key(g));
                  },
                  child: Text(_promemoria.isEmpty ? 'Nessuno' : F.dataKey(_promemoria)),
                ),
                if (_promemoria.isNotEmpty) IconButton(onPressed: () => setState(() => _promemoria = ''), icon: const Icon(Icons.close_rounded), tooltip: 'Togli'),
              ]),
              if (_promemoria.isNotEmpty) CheckboxListTile(contentPadding: EdgeInsets.zero, value: _fatto, onChanged: (v) => setState(() => _fatto = v == true), title: const Text('Fatto')),
              const SizedBox(height: S.m),
              Text('Collegamento (facoltativo)', style: t.labelLarge),
              const SizedBox(height: S.s),
              if (_coll != null && nomeColl != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: Text(nomeColl),
                    subtitle: Text(tipiCollegamento[_coll!['tipo']] ?? ''),
                    trailing: TextButton(onPressed: () => setState(() => _coll = null), child: const Text('Scollega')),
                  ),
                )
              else ...[
                Wrap(spacing: 6, children: [for (final e in tipiAttivi) ChoiceChip(label: Text(e.value), selected: _tipoColl == e.key, onSelected: (_) => setState(() => _tipoColl = e.key))]),
                const SizedBox(height: S.s),
                TextField(controller: _cercaColl, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cerca da collegare…'), onChanged: (_) => setState(() {})),
                for (final (id, nome) in _risultati())
                  ListTile(
                    title: Text(nome),
                    onTap: () => setState(() {
                      _coll = {'tipo': _tipoColl, 'id': id};
                      _cercaColl.clear();
                    }),
                  ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
