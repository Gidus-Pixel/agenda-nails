import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../appunti/pagina_appunti.dart';
import '../comuni.dart';
import '../magazzino/modulo_prodotto.dart';
import '../magazzino/pagina_magazzino.dart';
import '../piattaforma.dart';
import '../tema.dart';
import 'ordini.dart';
import 'pagina_fornitori.dart';

Future<void> apriFornitore(BuildContext context, String id) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SchedaFornitore(id: id)));

/// Scheda fornitore: contatti, condizioni, spesa per periodo, ordini, prodotti forniti, appunti.
class SchedaFornitore extends StatefulWidget {
  const SchedaFornitore({super.key, required this.id});
  final String id;
  @override
  State<SchedaFornitore> createState() => _SchedaFornitoreState();
}

class _SchedaFornitoreState extends State<SchedaFornitore> {
  late String _da = '${DateTime.now().year}-01-01', _a = D.oggiKey();

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final f = d.get('fornitori', widget.id);
        if (f == null) return Scaffold(appBar: AppBar(), body: const Vuoto('Fornitore non trovato.', icona: Icons.storefront_outlined));
        final t = Theme.of(context).textTheme;
        final cs = Theme.of(context).colorScheme;
        final gia = mappaGiacenze(d);
        final forniti = prodottiAttivi(d).where((p) => p['fornitoreId'] == widget.id).toList();
        final ord = d.elenco('ordini_fornitore').where((o) => o['fornitoreId'] == widget.id).toList()..sort((a, b) => comeStr(b['dataCreazione']).compareTo(comeStr(a['dataCreazione'])));
        final anni = {for (final o in ord) if (chiaveData(dataSpesaOrdine(o)).length >= 4) chiaveData(dataSpesaOrdine(o)).substring(0, 4)}.toList()..sort((a, b) => b.compareTo(a));
        final spesaPeriodo = ord.where((o) {
          final k = chiaveData(dataSpesaOrdine(o));
          return k.compareTo(_da) >= 0 && k.compareTo(_a) <= 0;
        }).fold<int>(0, (s, o) => s + spesaOrdine(o));
        final tel = comeStr(f['telefono']);
        final wa = comeStr(f['whatsapp']).isNotEmpty ? comeStr(f['whatsapp']) : tel;
        final email = comeStr(f['email']);
        final sito = comeStr(f['sito']);
        final largo = MediaQuery.sizeOf(context).width >= 900;

        Widget data(String v, ValueChanged<String> fn) => OutlinedButton(
              onPressed: () async {
                final g = await scegliData(context, D.daKey(v));
                if (g != null) setState(() => fn(D.key(g)));
              },
              child: Text(F.dataKey(v)),
            );

        final colDati = Column(children: [
          Sezione(
            titolo: 'Dati',
            azione: TextButton(onPressed: () => apriModuloFornitore(context, fornitore: f), child: const Text('Modifica')),
            child: Column(children: [
              RigaKv('Telefono', telefonoLeggibile(tel)),
              if (comeStr(f['whatsapp']).isNotEmpty) RigaKv('WhatsApp', telefonoLeggibile(comeStr(f['whatsapp']))),
              RigaKv('Email', email),
              RigaKv('Indirizzo', comeStr(f['indirizzo'])),
              RigaKv('Pagamento', comeStr(f['condizioniPagamento'])),
              RigaKv('Consegna', comeStr(f['tempiConsegna'])),
              RigaKv('Minimo d\'ordine', f['minimoOrdineCent'] != null ? F.euro(comeInt(f['minimoOrdineCent'])) : ''),
              RigaKv('Spedizione', f['speseSpedizioneCent'] != null ? F.euro(comeInt(f['speseSpedizioneCent'])) : ''),
              RigaKv('Sconti', comeStr(f['sconti'])),
              if (comeStr(f['note']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s), child: Riquadro(titolo: 'Note', testo: comeStr(f['note']))),
            ]),
          ),
          const SizedBox(height: S.l),
          Sezione(
            titolo: 'Spesa',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [const Text('Dal '), data(_da, (v) => _da = v), const SizedBox(width: S.s), const Text('al '), data(_a, (v) => _a = v)]),
              const SizedBox(height: S.s),
              Tessera(valore: F.euro(spesaPeriodo), etichetta: 'merce ricevuta nel periodo (con spedizione)'),
              for (final an in anni) RigaKv(an, F.euro(ord.where((o) => chiaveData(dataSpesaOrdine(o)).startsWith(an)).fold<int>(0, (s, o) => s + spesaOrdine(o)))),
            ]),
          ),
          if (d.moduloAttivo('appunti')) ...[const SizedBox(height: S.l), SezioneAppunti(tipo: 'fornitore', id: widget.id)],
        ]);

        final colOrdini = Column(children: [
          if (d.moduloAttivo('ordini'))
            Sezione(
              titolo: 'Ordini (${ord.length})',
              azione: TextButton.icon(onPressed: () => apriOrdine(context, fornitoreId: widget.id), icon: const Icon(Icons.add_rounded), label: const Text('Nuovo')),
              child: ord.isEmpty ? Text('Nessun ordine.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)) : Column(children: [for (final o in ord) RigaOrdine(o: o, mostraFornitore: false)]),
            ),
          const SizedBox(height: S.l),
          if (d.moduloAttivo('magazzino'))
            Sezione(
              titolo: 'Prodotti forniti (${forniti.length})',
              padding: const EdgeInsets.fromLTRB(0, S.m, 0, S.s),
              azione: Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton.icon(onPressed: () => apriModuloProdotto(context, fornitoreId: widget.id), icon: const Icon(Icons.add_rounded), label: const Text('Prodotto'))),
              child: forniti.isEmpty
                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: S.l), child: Text('Nessun prodotto collegato: nel prodotto scegli questo fornitore come "preferito".', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
                  : Column(children: [for (final p in forniti) RigaProdotto(p: p, g: gia[comeStr(p['id'])] ?? 0, rapidi: false)]),
            ),
        ]);

        return Scaffold(
          appBar: AppBar(title: Text(nomeFornitore(f)), actions: [
            IconButton(tooltip: 'Modifica', onPressed: () => apriModuloFornitore(context, fornitore: f), icon: const Icon(Icons.edit_outlined)),
            PopupMenuButton<String>(
              tooltip: 'Altre azioni',
              onSelected: (v) async {
                if (v == 'archivia') {
                  final ok = await conferma(context, titolo: 'Archiviare il fornitore?', messaggio: 'Prodotti e ordini restano; il fornitore non comparirà più negli elenchi.', ok: 'Archivia');
                  if (!ok || !context.mounted) return;
                  Navigator.pop(context);
                  await d.archivia('fornitori', widget.id);
                  avvisa('Fornitore archiviato', annulla: () async => d.ripristina('fornitori', widget.id));
                }
              },
              itemBuilder: (_) => [const PopupMenuItem(value: 'archivia', child: ListTile(leading: Icon(Icons.archive_outlined), title: Text('Archivia'), contentPadding: EdgeInsets.zero))],
            ),
          ]),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
                if ([comeStr(f['referente']), comeStr(f['piva'])].any((x) => x.isNotEmpty))
                  Text([comeStr(f['referente']), if (comeStr(f['piva']).isNotEmpty) 'P.IVA ${f['piva']}'].where((x) => x.isNotEmpty).join(' · '), style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: S.m),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  if (d.moduloAttivo('ordini')) FilledButton.icon(onPressed: () => apriOrdine(context, fornitoreId: widget.id), icon: const Icon(Icons.add_shopping_cart_rounded), label: const Text('Nuovo ordine')),
                  if (tel.isNotEmpty) OutlinedButton.icon(onPressed: () => chiama(context, tel), icon: const Icon(Icons.call_rounded), label: const Text('Chiama')),
                  if (wa.isNotEmpty) OutlinedButton.icon(onPressed: () => apriLink(context, linkWhatsApp(wa, '', prefisso: d.prefisso)), icon: const Icon(Icons.chat_rounded), label: const Text('WhatsApp')),
                  if (email.isNotEmpty) OutlinedButton.icon(onPressed: () => apriLink(context, Uri(scheme: 'mailto', path: email)), icon: const Icon(Icons.mail_outline_rounded), label: const Text('Email')),
                  if (sito.isNotEmpty) OutlinedButton.icon(onPressed: () => apriLink(context, Uri.tryParse(RegExp(r'^https?:', caseSensitive: false).hasMatch(sito) ? sito : 'https://$sito')), icon: const Icon(Icons.public_rounded), label: const Text('Sito')),
                ]),
                const SizedBox(height: S.l),
                if (largo)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: colDati), const SizedBox(width: S.l), Expanded(child: colOrdini)])
                else ...[colOrdini, const SizedBox(height: S.l), colDati],
              ]),
            ),
          ),
        );
      },
    );
  }
}
