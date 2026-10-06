import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../appunti/pagina_appunti.dart';
import '../comuni.dart';
import '../foto.dart';
import '../fornitori/ordini.dart';
import '../fornitori/scheda_fornitore.dart';
import '../tema.dart';
import 'modulo_prodotto.dart';
import 'movimento.dart';

Future<void> apriProdotto(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SchedaProdotto(id: id)));

/// Scheda prodotto: giacenza, avvisi, dati, movimenti, appunti.
class SchedaProdotto extends StatelessWidget {
  const SchedaProdotto({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final p = d.get('prodotti', id);
        if (p == null) return Scaffold(appBar: AppBar(), body: const Vuoto('Prodotto non trovato.', icona: Icons.inventory_2_outlined));
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final u = comeStr(p['unita']);
        final g = giacenzaDi(d, id);
        final mov = movimentiDi(d, id);
        final forn = d.get('fornitori', comeStr(p['fornitoreId']));
        final pao = scadenzaPAO(p);
        final et = etichetteProdotto(d, p, g);
        final tipi = tipiMovimento.keys.where((k) => k != 'vendita' || p['uso'] != 'interno').toList();
        final largo = MediaQuery.sizeOf(context).width >= 900;

        final dati = Sezione(
          titolo: 'Dati',
          azione: TextButton(onPressed: () => apriModuloProdotto(context, prodotto: p), child: const Text('Modifica')),
          child: Column(children: [
            if (comeStr(p['codiceColore']).isNotEmpty) RigaKv('Codice colore', comeStr(p['codiceColore'])),
            RigaKv('Categoria', comeStr(p['categoria'])),
            RigaKv('Scorta minima', numero(p['scortaMinima']) > 0 ? fmtQta(p['scortaMinima'], u) : ''),
            RigaKv('Costo', p['costoCent'] != null ? '${F.euro(comeInt(p['costoCent']))} / ${u.isEmpty ? 'pz' : u}' : ''),
            if (p['uso'] != 'interno') RigaKv('Prezzo vendita', p['prezzoVenditaCent'] != null ? F.euro(comeInt(p['prezzoVenditaCent'])) : ''),
            RigaKv('Uso', usiProdotto[p['uso']] ?? ''),
            if (forn != null)
              InkWell(
                onTap: d.moduloAttivo('fornitori') ? () => apriFornitore(context, comeStr(forn['id'])) : null,
                child: RigaKv('Fornitore', '${nomeFornitore(forn)}${comeStr(p['codiceFornitore']).isNotEmpty ? ' · cod. ${p['codiceFornitore']}' : ''}'),
              )
            else
              const RigaKv('Fornitore', ''),
            RigaKv('Lotto', comeStr(p['lotto'])),
            RigaKv('Scadenza', F.dataKey(comeStr(p['scadenza']))),
            RigaKv('Aperto il', [F.dataKey(comeStr(p['dataApertura'])), if ((comeInt(p['paoMesi']) ?? 0) > 0) 'PAO ${p['paoMesi']} mesi${pao != null ? ' (fino al ${F.dataKey(pao)})' : ''}'].where((x) => x.isNotEmpty).join(' · ')),
            if (comeStr(p['note']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s), child: Riquadro(titolo: 'Note', testo: comeStr(p['note']))),
          ]),
        );

        final movimenti = Sezione(
          titolo: 'Movimenti (${mov.length})',
          child: mov.isEmpty
              ? Text('Nessun movimento.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
              : Column(children: [
                  for (final m in mov.take(80))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(tipiMovimento[m['tipo']]?.nome ?? comeStr(m['tipo']), style: t.titleSmall),
                            Text(
                              [
                                F.dataOra(D.daIso(comeStr(m['data']))),
                                if (m['riferimento'] is Map) comeDoc(m['riferimento'])['tipo'] == 'ordine' ? 'da ordine' : (comeDoc(m['riferimento'])['tipo'] == 'scheda' ? 'da scheda lavoro' : ''),
                                if (comeStr(m['lotto']).isNotEmpty) 'lotto ${m['lotto']}',
                                comeStr(m['nota']),
                              ].where((x) => x.isNotEmpty).join(' · '),
                              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                            ),
                          ]),
                        ),
                        Text('${numero(m['quantita']) > 0 ? '+' : ''}${fmtQta(m['quantita'], u)}',
                            style: t.titleSmall?.copyWith(color: numero(m['quantita']) < 0 ? cs.error : const Color(0xFF1F7A55), fontFeatures: const [FontFeature.tabularFigures()])),
                      ]),
                    ),
                  if (mov.length > 80) Text('Mostrati gli ultimi 80 movimenti su ${mov.length}.', style: t.bodySmall),
                ]),
        );

        final testa = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (comeStr(p['fotoId']).isNotEmpty) Padding(padding: const EdgeInsets.only(right: S.l), child: FotoMiniatura(key: ValueKey(p['fotoId']), id: comeStr(p['fotoId']), dimensione: 88)),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (descrProdotto(p).isNotEmpty) Text(descrProdotto(p), style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                Text(fmtQta(g, u), style: t.displaySmall?.copyWith(color: g < 0 ? cs.error : null)),
                if (et.isNotEmpty) Wrap(spacing: 4, runSpacing: 4, children: [for (final (x, tipo) in et) EtichettaTipo(x, tipo)]),
              ]),
            ),
          ]),
          const SizedBox(height: S.l),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: () => apriMovimento(context, p, 'carico'), icon: const Icon(Icons.add_rounded), label: const Text('Carico'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)))),
            const SizedBox(width: S.s),
            Expanded(child: OutlinedButton.icon(onPressed: () => apriMovimento(context, p, 'consumo'), icon: const Icon(Icons.remove_rounded), label: const Text('Usa'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)))),
          ]),
          const SizedBox(height: S.s),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in tipi.where((k) => k != 'carico' && k != 'consumo')) ActionChip(label: Text(tipiMovimento[k]!.nome), onPressed: () => apriMovimento(context, p, k)),
            ActionChip(
              avatar: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Aperto oggi'),
              onPressed: () async {
                final prima = comeStr(p['dataApertura']);
                p['dataApertura'] = D.oggiKey();
                await d.salva('prodotti', p);
                if (context.mounted) {
                  avviso(context, 'Segnato come aperto oggi', annulla: () async {
                    p['dataApertura'] = prima;
                    await d.salva('prodotti', p);
                  });
                }
              },
            ),
            if (d.moduloAttivo('ordini')) ActionChip(avatar: const Icon(Icons.local_shipping_outlined, size: 18), label: const Text('Aggiungi a un ordine'), onPressed: () => aggiungiAOrdine(context, p)),
          ]),
        ]);

        return Scaffold(
          appBar: AppBar(title: Text(nomeProdotto(p)), actions: [
            IconButton(tooltip: 'Modifica', onPressed: () => apriModuloProdotto(context, prodotto: p), icon: const Icon(Icons.edit_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Altre azioni',
              onSelected: (v) async {
                if (v == 'archivia') {
                  final ok = await conferma(context, titolo: 'Archiviare il prodotto?', messaggio: 'Non comparirà più nel magazzino; i movimenti restano. Potrai ripristinarlo da Altro → Elementi archiviati.', ok: 'Archivia');
                  if (!ok || !context.mounted) return;
                  Navigator.pop(context);
                  await d.archivia('prodotti', id);
                  avvisa('Prodotto archiviato', annulla: () async => d.ripristina('prodotti', id));
                }
              },
              itemBuilder: (_) => [const PopupMenuItem(value: 'archivia', child: ListTile(leading: Icon(Icons.archive_outlined), title: Text('Archivia'), contentPadding: EdgeInsets.zero))],
            ),
          ]),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
                testa,
                const SizedBox(height: S.l),
                if (largo)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(children: [dati, if (d.moduloAttivo('appunti')) ...[const SizedBox(height: S.l), SezioneAppunti(tipo: 'prodotto', id: id)]])),
                    const SizedBox(width: S.l),
                    Expanded(child: movimenti),
                  ])
                else ...[
                  dati,
                  const SizedBox(height: S.l),
                  if (d.moduloAttivo('appunti')) ...[SezioneAppunti(tipo: 'prodotto', id: id), const SizedBox(height: S.l)],
                  movimenti,
                ],
              ]),
            ),
          ),
        );
      },
    );
  }
}
