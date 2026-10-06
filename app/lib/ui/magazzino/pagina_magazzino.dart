import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../fornitori/ordini.dart';
import '../tema.dart';
import 'modulo_prodotto.dart';
import 'movimento.dart';
import 'scheda_prodotto.dart';

/// Magazzino: prodotti con giacenza (somma dei movimenti), filtri e avvisi.
class PaginaMagazzino extends StatefulWidget {
  const PaginaMagazzino({super.key});
  @override
  State<PaginaMagazzino> createState() => _PaginaMagazzinoState();
}

class _PaginaMagazzinoState extends State<PaginaMagazzino> {
  final _cerca = TextEditingController();
  String _filtro = '';
  String? _categoria, _fornitore;

  @override
  void initState() {
    super.initState();
    _cerca.addListener(() => setState(() {}));
    if (schermataAvvio == 'prodotto') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final p = avvisiMagazzino(context.dati).sottoScorta.firstOrNull?.p ?? prodottiAttivi(context.dati).firstOrNull;
        if (p != null) apriProdotto(context, comeStr(p['id']));
      });
    }
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
      appBar: AppBar(title: const Text('Magazzino'), actions: [
        if (d.moduloAttivo('ordini'))
          IconButton(tooltip: 'Ordini ai fornitori', onPressed: () => apriSezione(context, 'ordini'), icon: const Icon(Icons.local_shipping_outlined)),
        if (d.moduloAttivo('fornitori'))
          IconButton(tooltip: 'Fornitori', onPressed: () => apriSezione(context, 'fornitori'), icon: const Icon(Icons.storefront_outlined)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'magazzino-nuovo',
        onPressed: () async {
          final id = await apriModuloProdotto(context);
          if (id != null && context.mounted) await apriProdotto(context, id);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Prodotto'),
      ),
      body: ListenableBuilder(listenable: d, builder: (context, _) => _contenuto(context)),
    );
  }

  Widget _contenuto(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final prodotti = prodottiAttivi(d);
    final gia = mappaGiacenze(d);
    final avv = avvisiMagazzino(d);
    final idSotto = {for (final x in [...avv.sottoScorta, ...avv.negativi]) x.p['id']};
    final idScad = {for (final x in [...avv.inScadenza, ...avv.scaduti]) x.p['id']};
    final idPao = {for (final x in avv.paoSuperato) x.p['id']};
    final categorie = {for (final p in prodotti) comeStr(p['categoria'])}.where((x) => x.isNotEmpty).toList();
    final fornitori = fornitoriAttivi(d);
    final q = norm(_cerca.text.trim());
    final lista = prodotti.where((p) {
      if (_categoria != null && p['categoria'] != _categoria) return false;
      if (_fornitore != null && p['fornitoreId'] != _fornitore) return false;
      if (_filtro == 'sotto' && !idSotto.contains(p['id'])) return false;
      if (_filtro == 'scadenza' && !idScad.contains(p['id'])) return false;
      if (_filtro == 'pao' && !idPao.contains(p['id'])) return false;
      if (q.isNotEmpty && !norm([p['nome'], p['marca'], p['linea'], p['codiceColore'], p['codiceFornitore'], p['categoria']].map(comeStr).join(' ')).contains(q)) return false;
      return true;
    }).toList();

    Widget chip(String k, String testo) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(label: Text(testo), selected: _filtro == k, onSelected: (_) => setState(() => _filtro = k)),
        );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.m),
            child: GrigliaTessere(colonne: eTablet(context) ? 4 : 2, children: [
              Tessera(valore: F.euro(valoreMagazzino(prodotti, gia)), etichetta: 'valore a costo'),
              Tessera(valore: '${idSotto.length}', etichetta: 'sotto scorta'),
              Tessera(valore: '${idScad.length}', etichetta: 'in scadenza o scaduti'),
              Tessera(valore: '${idPao.length}', etichetta: 'aperti oltre il PAO'),
            ]),
          ),
          if (idSotto.isNotEmpty && d.moduloAttivo('ordini'))
            Padding(
              padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.m),
              child: Riquadro(
                tipo: 'avviso',
                testo: '${idSotto.length == 1 ? 'Un prodotto è' : '${idSotto.length} prodotti sono'} sotto la scorta minima.',
                azioni: [FilledButton.tonal(onPressed: () => creaOrdiniSottoScorta(context), child: const Text('Prepara gli ordini'))],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
            child: TextField(
              controller: _cerca,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Cerca nome, marca, codice…',
                suffixIcon: _cerca.text.isEmpty ? null : IconButton(onPressed: _cerca.clear, icon: const Icon(Icons.close_rounded), tooltip: 'Cancella'),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.l), children: [
              chip('', 'Tutti'),
              chip('sotto', 'Sotto scorta (${idSotto.length})'),
              chip('scadenza', 'In scadenza (${idScad.length})'),
              chip('pao', 'PAO superato (${idPao.length})'),
            ]),
          ),
          if (categorie.length > 1 || fornitori.isNotEmpty)
            SizedBox(
              height: 46,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.l), children: [
                for (final c in categorie)
                  Padding(padding: const EdgeInsets.only(right: 6), child: FilterChip(label: Text(c), selected: _categoria == c, onSelected: (s) => setState(() => _categoria = s ? c : null))),
                if (fornitori.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: PopupMenuButton<String?>(
                      tooltip: 'Fornitore',
                      onSelected: (v) => setState(() => _fornitore = v == '' ? null : v),
                      itemBuilder: (_) => [const PopupMenuItem(value: '', child: Text('Tutti i fornitori')), for (final f in fornitori) PopupMenuItem(value: comeStr(f['id']), child: Text(nomeFornitore(f)))],
                      child: Chip(
                        avatar: const Icon(Icons.storefront_outlined, size: 18),
                        label: Text(_fornitore == null ? 'Fornitore' : nomeFornitore(d.get('fornitori', _fornitore))),
                        backgroundColor: _fornitore == null ? null : cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
              ]),
            ),
          const SizedBox(height: S.s),
          if (lista.isEmpty)
            Vuoto(prodotti.isEmpty ? 'Nessun prodotto. Aggiungi il primo con "Prodotto": gel, basi, top, semipermanenti, lime, monouso…' : 'Nessun prodotto corrisponde ai filtri.', icona: Icons.inventory_2_outlined),
          for (final p in lista) RigaProdotto(p: p, g: gia[comeStr(p['id'])] ?? 0),
          if (lista.isNotEmpty) Padding(padding: const EdgeInsets.all(S.l), child: Text('${lista.length} prodotti', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
        ]),
      ),
    );
  }
}

/// Riga di un prodotto con giacenza e pulsanti rapidi Carico / Usa.
class RigaProdotto extends StatelessWidget {
  const RigaProdotto({super.key, required this.p, required this.g, this.rapidi = true});
  final Doc p;
  final num g;
  final bool rapidi;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final et = etichetteProdotto(d, p, g);
    final sotto = [descrProdotto(p), comeStr(p['categoria']), if (numero(p['scortaMinima']) > 0) 'scorta min. ${fmtQta(p['scortaMinima'], comeStr(p['unita']))}'].where((x) => x.isNotEmpty).join(' · ');
    return InkWell(
      onTap: () => apriProdotto(context, comeStr(p['id'])),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.l, vertical: S.s),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nomeProdotto(p), style: t.titleMedium),
              if (sotto.isNotEmpty) Text(sotto, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              if (et.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 4, runSpacing: 4, children: [for (final (x, tipo) in et) EtichettaTipo(x, tipo)])),
            ]),
          ),
          const SizedBox(width: S.s),
          Text(fmtQta(g, comeStr(p['unita'])), style: t.titleMedium?.copyWith(color: g < 0 ? cs.error : null, fontFeatures: const [FontFeature.tabularFigures()])),
          if (rapidi) ...[
            const SizedBox(width: 4),
            IconButton(tooltip: 'Carico', onPressed: () => apriMovimento(context, p, 'carico'), icon: const Icon(Icons.add_circle_outline_rounded)),
            IconButton(tooltip: 'Usa (consumo)', onPressed: () => apriMovimento(context, p, 'consumo'), icon: const Icon(Icons.remove_circle_outline_rounded)),
          ],
        ]),
      ),
    );
  }
}
