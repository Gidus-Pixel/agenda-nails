import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../tema.dart';
import 'pagina_fornitori.dart';

/* =============================== Elenco ordini =============================== */
class PaginaOrdini extends StatefulWidget {
  const PaginaOrdini({super.key});
  @override
  State<PaginaOrdini> createState() => _PaginaOrdiniState();
}

class _PaginaOrdiniState extends State<PaginaOrdini> {
  String _filtro = 'aperti';
  static const _filtri = {'aperti': statiOrdineAperti, 'ricevuti': ['ricevuto'], 'annullati': ['annullato'], 'tutti': <String>[]};

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Ordini ai fornitori'), actions: [
        if (d.moduloAttivo('magazzino')) TextButton.icon(onPressed: () => creaOrdiniSottoScorta(context), icon: const Icon(Icons.auto_awesome_outlined), label: const Text('Dai sotto scorta')),
      ]),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'ordini-nuovo', onPressed: () => apriOrdine(context), icon: const Icon(Icons.add_rounded), label: const Text('Ordine')),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final ordini = d.elenco('ordini_fornitore')..sort((a, b) => comeStr(b['dataCreazione']).compareTo(comeStr(a['dataCreazione'])));
          bool passa(Doc o, String k) => _filtri[k]!.isEmpty || _filtri[k]!.contains(o['stato']);
          final lista = ordini.where((o) => passa(o, _filtro)).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, 0), children: [
                    for (final e in {'aperti': 'Aperti', 'ricevuti': 'Ricevuti', 'annullati': 'Annullati', 'tutti': 'Tutti'}.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text('${e.value} (${ordini.where((o) => passa(o, e.key)).length})'), selected: _filtro == e.key, onSelected: (_) => setState(() => _filtro = e.key)),
                      ),
                  ]),
                ),
                const SizedBox(height: S.s),
                if (lista.isEmpty) const Vuoto('Nessun ordine.', icona: Icons.local_shipping_outlined),
                for (final o in lista) Padding(padding: const EdgeInsets.symmetric(horizontal: S.s), child: RigaOrdine(o: o)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class RigaOrdine extends StatelessWidget {
  const RigaOrdine({super.key, required this.o, this.mostraFornitore = true});
  final Doc o;
  final bool mostraFornitore;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = statiOrdine[o['stato']] ?? statiOrdine['bozza']!;
    final f = d.get('fornitori', comeStr(o['fornitoreId']));
    final n = comeListaDoc(o['righe']).length;
    final creato = chiaveData(comeStr(o['dataCreazione']));
    final titolo = mostraFornitore ? (f != null ? nomeFornitore(f) : (comeStr(o['fornitoreId']).isEmpty ? 'Senza fornitore' : 'Fornitore eliminato')) : 'Ordine del ${F.dataKey(creato)}';
    return InkWell(
      onTap: () => apriOrdine(context, ordine: o),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.s, vertical: S.s),
        child: Row(children: [
          Container(width: 4, height: 44, margin: const EdgeInsets.only(right: S.m), decoration: BoxDecoration(color: Color(st.colore), borderRadius: BorderRadius.circular(4))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titolo, style: t.titleMedium),
              Text(
                [
                  if (mostraFornitore) F.dataKey(creato),
                  '$n rig${n == 1 ? 'a' : 'he'}',
                  F.euro(totaleOrdine(o)),
                  if (comeStr(o['dataInvio']).isNotEmpty) 'inviato ${F.dataKey(chiaveData(comeStr(o['dataInvio'])))}',
                  if (comeStr(o['dataRicezione']).isNotEmpty) 'ricevuto ${F.dataKey(chiaveData(comeStr(o['dataRicezione'])))}',
                  if (o['demo'] == true) 'PROVA',
                ].join(' · '),
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Color(st.colore), borderRadius: BorderRadius.circular(99)),
            child: Text(st.nome, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}

/* =============================== Ordine =============================== */
Future<void> apriOrdine(BuildContext context, {Doc? ordine, String? fornitoreId, List<Doc>? righe}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: ordine == null, builder: (_) => _ModuloOrdine(ordine: ordine, fornitoreId: fornitoreId, righe: righe)));
}

class _ModuloOrdine extends StatefulWidget {
  const _ModuloOrdine({this.ordine, this.fornitoreId, this.righe});
  final Doc? ordine;
  final String? fornitoreId;
  final List<Doc>? righe;
  @override
  State<_ModuloOrdine> createState() => _ModuloOrdineState();
}

class _ModuloOrdineState extends State<_ModuloOrdine> {
  late Doc _o = widget.ordine != null ? clonaDoc(widget.ordine!) : nuovoOrdine(fornitoreId: widget.fornitoreId, righe: widget.righe?.map(clonaDoc).toList());
  late final _spese = TextEditingController(text: F.testoDaCent(comeInt(_o['speseSpedizioneCent'])));
  late final _note = TextEditingController(text: comeStr(_o['note']));
  bool get _modificabile => _o['stato'] == 'bozza';
  List<Doc> get _righe => comeListaDoc(_o['righe']);

  @override
  void initState() {
    super.initState();
    final f = Ambito.of(context).dati.get('fornitori', comeStr(_o['fornitoreId']));
    if (widget.ordine == null && f != null && _o['speseSpedizioneCent'] == null) {
      _o['speseSpedizioneCent'] = f['speseSpedizioneCent'];
      _spese.text = F.testoDaCent(comeInt(f['speseSpedizioneCent']));
    }
    _o['righe'] = _righe;
  }

  @override
  void dispose() {
    _spese.dispose();
    _note.dispose();
    super.dispose();
  }

  void _leggi() {
    _o['note'] = _note.text.trim();
    if (_modificabile) _o['speseSpedizioneCent'] = F.centDaTesto(_spese.text);
  }

  Future<bool> _salva({bool silenzioso = false}) async {
    _leggi();
    if (comeStr(_o['fornitoreId']).isEmpty) {
      avviso(context, 'Scegli il fornitore.', errore: true);
      return false;
    }
    if (_righe.isEmpty) {
      avviso(context, 'Aggiungi almeno un prodotto.', errore: true);
      return false;
    }
    final rec = await context.dati.salva('ordini_fornitore', _o);
    _o = rec;
    if (!silenzioso && mounted) avviso(context, 'Ordine salvato');
    return true;
  }

  Future<void> _aggiungiProdotto() async {
    final d = context.dati;
    final p = await scegliProdotto(context, fornitoreId: comeStr(_o['fornitoreId']));
    if (p == null || !mounted) return;
    if (_righe.any((r) => r['prodottoId'] == p['id'])) {
      avviso(context, 'Il prodotto è già nell\'ordine.');
      return;
    }
    setState(() {
      _righe.add(rigaOrdineDa(p, quantita: (numero(p['scortaMinima']) > 0 ? numero(p['scortaMinima']) : 1)));
      if (comeStr(_o['fornitoreId']).isEmpty && comeStr(p['fornitoreId']).isNotEmpty && d.get('fornitori', comeStr(p['fornitoreId'])) != null) _o['fornitoreId'] = p['fornitoreId'];
    });
  }

  Future<void> _annulla() async {
    final d = context.dati;
    final ok = await conferma(context, titolo: 'Annullare l\'ordine?', messaggio: _o['stato'] == 'parziale' ? 'La merce già ricevuta resta in magazzino.' : null, ok: 'Annulla ordine', annulla: 'Indietro', pericolo: true);
    if (!ok || !mounted) return;
    final prima = comeStr(_o['stato']);
    _o['stato'] = 'annullato';
    final rec = await d.salva('ordini_fornitore', _o);
    if (!mounted) return;
    Navigator.pop(context);
    avvisa('Ordine annullato', annulla: () async {
      rec['stato'] = prima;
      await d.salva('ordini_fornitore', rec);
    });
  }

  Future<void> _eliminaBozza() async {
    final d = context.dati;
    final id = comeStr(_o['id']);
    Navigator.pop(context);
    await d.archivia('ordini_fornitore', id);
    avvisa('Bozza eliminata', annulla: () async => d.ripristina('ordini_fornitore', id));
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = statiOrdine[_o['stato']] ?? statiOrdine['bozza']!;
    final forn = d.get('fornitori', comeStr(_o['fornitoreId']));
    _o['speseSpedizioneCent'] = _modificabile ? F.centDaTesto(_spese.text) : _o['speseSpedizioneCent'];
    final tot = totaleOrdine(_o);
    final minimo = comeInt(forn?['minimoOrdineCent']);
    final esiste = _o['id'] != null;
    final stato = comeStr(_o['stato']);
    const dec = TextInputType.numberWithOptions(decimal: true);

    return Scaffold(
      appBar: AppBar(
        title: Text(esiste ? 'Ordine' : 'Nuovo ordine'),
        actions: [
          if (esiste && stato != 'annullato' && stato != 'ricevuto')
            PopupMenuButton<String>(
              tooltip: 'Altre azioni',
              onSelected: (v) => v == 'annulla' ? _annulla() : _eliminaBozza(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'annulla', child: Text('Annulla l\'ordine')),
                if (stato == 'bozza') const PopupMenuItem(value: 'elimina', child: Text('Elimina la bozza')),
              ],
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, 120), children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: Color(st.colore), borderRadius: BorderRadius.circular(99)), child: Text(st.nome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                const SizedBox(width: S.s),
                Expanded(child: Text('creato il ${F.dataOra(D.daIso(comeStr(_o['dataCreazione'])))}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
              ]),
              const SizedBox(height: S.l),
              if (_modificabile) ...[
                CampoScelta<String>(
                  etichetta: 'Fornitore *',
                  valore: comeStr(_o['fornitoreId']).isEmpty ? null : comeStr(_o['fornitoreId']),
                  opzioni: [for (final f in fornitoriAttivi(d)) (comeStr(f['id']), nomeFornitore(f))],
                  vuoto: 'Scegli…',
                  suCambio: (v) => setState(() {
                    _o['fornitoreId'] = v;
                    final f = d.get('fornitori', v);
                    if (f != null && _spese.text.isEmpty) _spese.text = F.testoDaCent(comeInt(f['speseSpedizioneCent']));
                  }),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final id = await apriModuloFornitore(context);
                      if (id != null) setState(() => _o['fornitoreId'] = id);
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nuovo fornitore'),
                  ),
                ),
              ] else
                Text(forn != null ? nomeFornitore(forn) : 'Fornitore non disponibile', style: t.headlineSmall),
              if (minimo != null && minimo > 0 && tot < minimo) Padding(padding: const EdgeInsets.only(top: S.s), child: Riquadro(tipo: 'avviso', testo: 'Il minimo d\'ordine di questo fornitore è ${F.euro(minimo)}.')),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Righe (${_righe.length})',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final r in _righe)
                    Padding(
                      key: ObjectKey(r),
                      padding: const EdgeInsets.only(bottom: S.m),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text('${r['nome']}', style: t.titleSmall)),
                          if (_modificabile) IconButton(tooltip: 'Togli', onPressed: () => setState(() => _righe.remove(r)), icon: const Icon(Icons.close_rounded)),
                        ]),
                        if (comeStr(r['codiceFornitore']).isNotEmpty) Text('cod. ${r['codiceFornitore']}', style: t.bodySmall),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: testoQta(r['quantita']),
                              enabled: _modificabile,
                              keyboardType: dec,
                              decoration: const InputDecoration(labelText: 'Quantità'),
                              onChanged: (v) => setState(() {
                                final n = qtaDaTesto(v);
                                if (n != null && n > 0) r['quantita'] = n;
                              }),
                            ),
                          ),
                          const SizedBox(width: S.s),
                          Expanded(
                            child: TextFormField(
                              initialValue: F.testoDaCent(comeInt(r['costoCent'])),
                              enabled: _modificabile,
                              keyboardType: dec,
                              decoration: const InputDecoration(labelText: 'Costo unit. (€)'),
                              onChanged: (v) => setState(() => r['costoCent'] = F.centDaTesto(v)),
                            ),
                          ),
                          if (!_modificabile) ...[const SizedBox(width: S.s), Expanded(child: Text('ricevuti ${testoQta(r['ricevuta'] ?? 0)}', style: t.bodyMedium))],
                        ]),
                      ]),
                    ),
                  if (_righe.isEmpty) Text('Nessuna riga.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  if (_modificabile) Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: _aggiungiProdotto, icon: const Icon(Icons.add_rounded), label: const Text('Aggiungi prodotto'))),
                ]),
              ),
              const SizedBox(height: S.l),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Campo(etichetta: 'Spese di spedizione (€)', controller: _spese, tastiera: dec, abilitato: _modificabile, suCambio: (_) => setState(() {}))),
                const SizedBox(width: S.m),
                Expanded(child: Tessera(valore: F.euro(tot), etichetta: 'totale ordine')),
              ]),
              Campo(etichetta: 'Note', controller: _note, righe: 3),
            ]),
          ),
        ),
      ),
      bottomNavigationBar: stato == 'annullato'
          ? null
          : Material(
              color: cs.surfaceContainerLowest,
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(S.m),
                  child: Row(children: [
                    if (_modificabile) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            if (await _salva() && mounted) Navigator.pop(this.context);
                          },
                          child: const Text('Salva bozza'),
                        ),
                      ),
                      const SizedBox(width: S.s),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            if (!await _salva(silenzioso: true) || !mounted) return;
                            await apriInvioOrdine(this.context, _o);
                            if (mounted) setState(() => _o = this.context.dati.get('ordini_fornitore', comeStr(_o['id'])) ?? _o);
                          },
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Invia…'),
                        ),
                      ),
                    ] else ...[
                      Expanded(child: OutlinedButton(onPressed: () => apriInvioOrdine(context, _o), child: const Text('Testo ordine'))),
                      const SizedBox(width: S.s),
                      if (['inviato', 'parziale'].contains(stato))
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              _leggi();
                              await context.dati.salva('ordini_fornitore', _o);
                              if (!mounted) return;
                              await apriRicevimento(this.context, _o);
                              if (mounted) setState(() => _o = this.context.dati.get('ordini_fornitore', comeStr(_o['id'])) ?? _o);
                            },
                            icon: const Icon(Icons.inventory_rounded),
                            label: const Text('Ricevi merce'),
                          ),
                        )
                      else
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              _leggi();
                              await context.dati.salva('ordini_fornitore', _o);
                              if (mounted) avviso(this.context, 'Note salvate');
                            },
                            child: const Text('Salva note'),
                          ),
                        ),
                    ],
                  ]),
                ),
              ),
            ),
    );
  }
}

/// Sceglie un prodotto dal magazzino (prima quelli del fornitore indicato).
Future<Doc?> scegliProdotto(BuildContext context, {String? fornitoreId}) {
  return showModalBottomSheet<Doc>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (c) => _SceltaProdotto(fornitoreId: fornitoreId),
  );
}

class _SceltaProdotto extends StatefulWidget {
  const _SceltaProdotto({this.fornitoreId});
  final String? fornitoreId;
  @override
  State<_SceltaProdotto> createState() => _SceltaProdottoState();
}

class _SceltaProdottoState extends State<_SceltaProdotto> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final q = norm(_q.trim());
    final tutti = prodottiAttivi(d).where((p) => q.isEmpty || norm([p['nome'], p['marca'], p['codiceColore'], p['codiceFornitore']].map(comeStr).join(' ')).contains(q)).toList();
    final propri = tutti.where((p) => (widget.fornitoreId ?? '').isNotEmpty && p['fornitoreId'] == widget.fornitoreId).toList();
    final altri = tutti.where((p) => !propri.contains(p)).toList();
    final gia = mappaGiacenze(d);
    Widget voce(Doc p) => ListTile(
          title: Text(nomeProdotto(p)),
          subtitle: Text([descrProdotto(p), 'giacenza ${fmtQta(gia[comeStr(p['id'])] ?? 0, comeStr(p['unita']))}'].where((x) => x.isNotEmpty).join(' · ')),
          onTap: () => Navigator.pop(context, p),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(S.s, 0, S.s, S.l), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s),
          child: TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cerca prodotto'), onChanged: (v) => setState(() => _q = v)),
        ),
        if (propri.isNotEmpty) ...[Padding(padding: const EdgeInsets.fromLTRB(S.m, S.m, S.m, 0), child: Text('Di questo fornitore', style: t.labelLarge)), for (final p in propri) voce(p)],
        if (altri.isNotEmpty) ...[Padding(padding: const EdgeInsets.fromLTRB(S.m, S.m, S.m, 0), child: Text(propri.isEmpty ? 'Prodotti' : 'Altri prodotti', style: t.labelLarge)), for (final p in altri) voce(p)],
        if (tutti.isEmpty) const Vuoto('Nessun prodotto. Aggiungilo prima dal Magazzino.', icona: Icons.inventory_2_outlined),
      ]),
    );
  }
}

/* =============================== Invio =============================== */
Future<void> apriInvioOrdine(BuildContext context, Doc o) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: _InvioOrdine(o: o)),
  );
}

class _InvioOrdine extends StatefulWidget {
  const _InvioOrdine({required this.o});
  final Doc o;
  @override
  State<_InvioOrdine> createState() => _InvioOrdineState();
}

class _InvioOrdineState extends State<_InvioOrdine> {
  late final Doc? _forn = Ambito.of(context).dati.get('fornitori', comeStr(widget.o['fornitoreId']));
  late final _testo = TextEditingController(text: testoOrdine(Ambito.of(context).dati, widget.o, _forn));

  @override
  void dispose() {
    _testo.dispose();
    super.dispose();
  }

  Future<void> _segnaInviato() async {
    final d = context.dati;
    final o = d.get('ordini_fornitore', comeStr(widget.o['id']));
    if (o == null || o['stato'] != 'bozza') return;
    o['stato'] = 'inviato';
    o['dataInvio'] = adessoIso();
    await d.salva('ordini_fornitore', o);
    avvisa('Ordine segnato come inviato', annulla: () async {
      o['stato'] = 'bozza';
      o['dataInvio'] = null;
      await d.salva('ordini_fornitore', o);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final f = _forn;
    final wa = f == null ? '' : (comeStr(f['whatsapp']).isNotEmpty ? comeStr(f['whatsapp']) : comeStr(f['telefono']));
    final email = comeStr(f?['email']);
    final bozza = d.get('ordini_fornitore', comeStr(widget.o['id']))?['stato'] == 'bozza';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.l),
      child: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Invia l\'ordine', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('Puoi modificare il testo. L\'invio lo fai tu da WhatsApp o dalla posta.', style: t.bodyMedium),
          const SizedBox(height: S.m),
          TextField(controller: _testo, maxLines: 12, minLines: 6),
          const SizedBox(height: S.m),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _testo.text));
                if (context.mounted) avviso(context, 'Testo copiato');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copia'),
            ),
            OutlinedButton.icon(onPressed: () => condividiTesto(context, _testo.text), icon: const Icon(Icons.ios_share_rounded), label: const Text('Condividi')),
            if (wa.isNotEmpty)
              FilledButton.icon(
                onPressed: () async {
                  await apriLink(context, linkWhatsApp(wa, _testo.text, prefisso: d.prefisso));
                  await _segnaInviato();
                },
                icon: const Icon(Icons.chat_rounded),
                label: const Text('WhatsApp'),
              ),
            if (email.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () async {
                  final oggetto = 'Ordine ${d.nomeAttivita} del ${F.data(DateTime.now())}'.replaceAll(RegExp(r'\s+'), ' ');
                  await apriLink(context, Uri.parse('mailto:${Uri.encodeComponent(email)}?subject=${Uri.encodeComponent(oggetto)}&body=${Uri.encodeComponent(_testo.text)}'));
                  await _segnaInviato();
                },
                icon: const Icon(Icons.mail_outline_rounded),
                label: const Text('Email'),
              ),
          ]),
          if (wa.isEmpty && email.isEmpty) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('Aggiungi telefono/WhatsApp o email nella scheda del fornitore per inviare con un tocco.', style: t.bodySmall)),
          if (bozza) ...[
            const SizedBox(height: S.l),
            TextButton(
              onPressed: () async {
                await _segnaInviato();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('L\'ho inviato in un altro modo: segna come inviato'),
            ),
          ],
        ]),
      ),
    );
  }
}

/* =============================== Ricevimento =============================== */
Future<void> apriRicevimento(BuildContext context, Doc o) {
  return Navigator.of(context).push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => _Ricevimento(o: o)));
}

class _Ricevimento extends StatefulWidget {
  const _Ricevimento({required this.o});
  final Doc o;
  @override
  State<_Ricevimento> createState() => _RicevimentoState();
}

class _RicevimentoState extends State<_Ricevimento> {
  late final List<Doc> _righe = comeListaDoc(widget.o['righe']);
  late final List<TextEditingController> _q = [for (final r in _righe) TextEditingController(text: testoQta(qta((numero(r['quantita']) - numero(r['ricevuta'])).clamp(0, double.infinity))))];
  late final List<TextEditingController> _lotto = [for (final _ in _righe) TextEditingController()];
  late final List<String> _scad = [for (final _ in _righe) ''];
  bool _costo = true;

  @override
  void dispose() {
    for (final c in [..._q, ..._lotto]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registra() async {
    final d = context.dati;
    final arrivi = <int, ({num quantita, String lotto, String scadenza})>{};
    for (var i = 0; i < _righe.length; i++) {
      if (d.get('prodotti', comeStr(_righe[i]['prodottoId'])) == null) continue;
      final n = qtaDaTesto(_q[i].text) ?? (_q[i].text.trim().isEmpty ? 0 : null);
      if (n == null || n < 0) {
        avviso(context, 'Controlla la quantità di ${_righe[i]['nome']}.', errore: true);
        return;
      }
      if (n > 0) arrivi[i] = (quantita: n, lotto: _lotto[i].text.trim(), scadenza: _scad[i]);
    }
    if (arrivi.isEmpty) {
      avviso(context, 'Nessuna quantità indicata.', errore: true);
      return;
    }
    final o = d.get('ordini_fornitore', comeStr(widget.o['id'])) ?? widget.o;
    final r = await riceviOrdine(d, o, arrivi, aggiornaCosto: _costo);
    if (!mounted) return;
    Navigator.pop(context);
    vibra(true);
    avvisa(o['stato'] == 'ricevuto' ? 'Ordine ricevuto: magazzino aggiornato' : 'Arrivo parziale registrato', annulla: () async {
      await d.inBlocco(() async {
        await d.eliminaMolti('movimenti_magazzino', [for (final m in r.movimenti) comeStr(m['id'])]);
        await d.salvaMolti('prodotti', r.prodottiPrima);
        await d.salva('ordini_fornitore', r.ordinePrima);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: const Text('Ricevi merce'),
        actions: [Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _registra, child: const Text('Registra')))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.all(S.l), children: [
              const Riquadro(testo: 'Indica cosa è arrivato. Per ogni quantità viene registrato un carico in magazzino.'),
              const SizedBox(height: S.l),
              for (var i = 0; i < _righe.length; i++)
                Builder(builder: (context) {
                  final r = _righe[i];
                  final esiste = d.get('prodotti', comeStr(r['prodottoId'])) != null;
                  return Card(
                    margin: const EdgeInsets.only(bottom: S.m),
                    child: Padding(
                      padding: const EdgeInsets.all(S.m),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('${r['nome']}', style: t.titleSmall),
                        Text('Ordinati ${testoQta(r['quantita'])} · già ricevuti ${testoQta(r['ricevuta'] ?? 0)}${esiste ? '' : ' · prodotto non più in magazzino'}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(height: S.s),
                        Row(children: [
                          Expanded(child: TextField(controller: _q[i], enabled: esiste, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Arrivati ora'))),
                          const SizedBox(width: S.s),
                          Expanded(child: TextField(controller: _lotto[i], enabled: esiste, decoration: const InputDecoration(labelText: 'Lotto'))),
                        ]),
                        if (esiste)
                          Row(children: [
                            Expanded(child: Text('Scadenza', style: t.labelLarge)),
                            TextButton(
                              onPressed: () async {
                                final g = await scegliData(context, _scad[i].isEmpty ? DateTime.now() : D.daKey(_scad[i]));
                                if (g != null) setState(() => _scad[i] = D.key(g));
                              },
                              child: Text(_scad[i].isEmpty ? 'Nessuna' : F.dataKey(_scad[i])),
                            ),
                          ]),
                      ]),
                    ),
                  );
                }),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: _costo, onChanged: (v) => setState(() => _costo = v), title: const Text('Aggiorna il costo dei prodotti con quello dell\'ordine')),
              const SizedBox(height: S.m),
              FilledButton(onPressed: _registra, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Registra l\'arrivo')),
            ]),
          ),
        ),
      ),
    );
  }
}

/* =============================== Riordino =============================== */
/// Crea bozze d'ordine (una per fornitore) per i prodotti sotto scorta non già in un ordine aperto.
Future<void> creaOrdiniSottoScorta(BuildContext context) async {
  final d = context.dati;
  final r = proposteRiordino(d);
  if (r.gruppi.isEmpty) {
    avviso(context, r.giaInOrdine > 0 ? 'I prodotti sotto scorta sono già tutti in un ordine aperto.' : 'Nessun prodotto sotto scorta.');
    return;
  }
  final n = r.gruppi.length;
  final ok = await conferma(
    context,
    titolo: 'Creare $n bozz${n == 1 ? 'a' : 'e'} d\'ordine?',
    contenuto: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Proposta: riportare ogni prodotto a ${r.moltiplicatore} volte la scorta minima. Potrai cambiare le quantità in ogni bozza.'),
      for (final e in r.gruppi.entries) ...[
        const SizedBox(height: S.m),
        Text(e.key.isEmpty ? 'Senza fornitore preferito' : nomeFornitore(d.get('fornitori', e.key)), style: const TextStyle(fontWeight: FontWeight.w700)),
        for (final x in e.value) Text('• ${nomeProdotto(x.p)}: hai ${fmtQta(x.g, comeStr(x.p['unita']))}, ordina ${fmtQta(x.q, comeStr(x.p['unita']))}'),
      ],
      if (r.gruppi.containsKey('')) const Padding(padding: EdgeInsets.only(top: S.m), child: Text('Per i prodotti senza fornitore scegli il fornitore nella bozza prima di inviarla.')),
      if (r.giaInOrdine > 0) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('${r.giaInOrdine} prodotti sotto scorta sono già in un ordine aperto.')),
    ]),
    ok: 'Crea bozze',
  );
  if (!ok || !context.mounted) return;
  final creati = await creaBozzeRiordino(d, r.gruppi);
  avvisa('${creati.length} bozz${creati.length == 1 ? 'a creata' : 'e create'}', annulla: () async => d.eliminaMolti('ordini_fornitore', [for (final o in creati) comeStr(o['id'])]));
  if (context.mounted) apriSezione(context, 'ordini');
}

/// Aggiunge un prodotto a una bozza esistente o a un nuovo ordine.
Future<void> aggiungiAOrdine(BuildContext context, Doc p) async {
  final d = context.dati;
  final riga = rigaOrdineDa(p, quantita: numero(p['scortaMinima']) > 0 ? numero(p['scortaMinima']) : 1);
  final bozze = d.elenco('ordini_fornitore').where((o) => o['stato'] == 'bozza' && (comeStr(p['fornitoreId']).isEmpty || o['fornitoreId'] == p['fornitoreId'] || comeStr(o['fornitoreId']).isEmpty)).toList();
  if (bozze.isEmpty) {
    await apriOrdine(context, fornitoreId: comeStr(p['fornitoreId']).isEmpty ? null : comeStr(p['fornitoreId']), righe: [riga]);
    return;
  }
  final scelta = await sceltaTra(context, titolo: 'Aggiungi a un ordine', messaggio: 'Vuoi aggiungerlo a una bozza esistente o creare un nuovo ordine?', opzioni: [
    ('nuovo', 'Nuovo ordine', false),
    for (final o in bozze.take(3)) (comeStr(o['id']), 'Bozza ${nomeFornitore(d.get('fornitori', comeStr(o['fornitoreId']))).isEmpty ? 'senza fornitore' : nomeFornitore(d.get('fornitori', comeStr(o['fornitoreId'])))}', true),
  ]);
  if (scelta == null || !context.mounted) return;
  if (scelta == 'nuovo') {
    await apriOrdine(context, fornitoreId: comeStr(p['fornitoreId']).isEmpty ? null : comeStr(p['fornitoreId']), righe: [riga]);
    return;
  }
  final o = d.get('ordini_fornitore', scelta)!;
  final righe = comeListaDoc(o['righe']);
  if (!righe.any((r) => r['prodottoId'] == p['id'])) righe.add(riga);
  o['righe'] = righe;
  if (comeStr(o['fornitoreId']).isEmpty && comeStr(p['fornitoreId']).isNotEmpty) o['fornitoreId'] = p['fornitoreId'];
  await d.salva('ordini_fornitore', o);
  if (context.mounted) await apriOrdine(context, ordine: o);
}
