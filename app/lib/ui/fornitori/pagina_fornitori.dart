import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';
import 'scheda_fornitore.dart';

/// Elenco fornitori con ricerca, prodotti forniti, ordini aperti e spesa dell'anno.
class PaginaFornitori extends StatefulWidget {
  const PaginaFornitori({super.key});
  @override
  State<PaginaFornitori> createState() => _PaginaFornitoriState();
}

class _PaginaFornitoriState extends State<PaginaFornitori> {
  final _cerca = TextEditingController();

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
      appBar: AppBar(title: const Text('Fornitori')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fornitori-nuovo',
        onPressed: () async {
          final id = await apriModuloFornitore(context);
          if (id != null && context.mounted) await apriFornitore(context, id);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Fornitore'),
      ),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final t = Theme.of(context).textTheme;
          final cs = Theme.of(context).colorScheme;
          final anno = '${DateTime.now().year}';
          final q = norm(_cerca.text.trim());
          final prodotti = d.elenco('prodotti');
          final ordini = d.elenco('ordini_fornitore');
          final lista = fornitoriAttivi(d).where((f) => q.isEmpty || norm([f['ragioneSociale'], f['referente'], f['telefono'], f['email'], f['piva']].map(comeStr).join(' ')).contains(q)).toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.s),
                  child: TextField(controller: _cerca, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cerca per nome, referente, telefono…')),
                ),
                if (lista.isEmpty) Vuoto(d.conta('fornitori') == 0 ? 'Nessun fornitore. Aggiungi il primo: potrai inviargli gli ordini con un tocco.' : 'Nessun fornitore trovato.', icona: Icons.storefront_outlined),
                for (final f in lista)
                  Builder(builder: (context) {
                    final np = prodotti.where((p) => p['fornitoreId'] == f['id']).length;
                    final ord = ordini.where((o) => o['fornitoreId'] == f['id']).toList();
                    final aperti = ord.where((o) => statiOrdineAperti.contains(o['stato'])).length;
                    final spesa = ord.where((o) => chiaveData(dataSpesaOrdine(o)).startsWith(anno)).fold<int>(0, (s, o) => s + spesaOrdine(o));
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: S.l, vertical: 4),
                      leading: Avatar(nomeFornitore(f)),
                      title: Text(nomeFornitore(f), style: t.titleMedium),
                      subtitle: Text(
                        [
                          comeStr(f['referente']),
                          if (comeStr(f['telefono']).isNotEmpty) telefonoLeggibile(comeStr(f['telefono'])),
                          '$np prodott${np == 1 ? 'o' : 'i'}',
                          if (aperti > 0) '$aperti ordin${aperti == 1 ? 'e aperto' : 'i aperti'}',
                          if (spesa > 0) 'spesa $anno: ${F.euro(spesa)}',
                        ].where((x) => x.isNotEmpty).join(' · '),
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => apriFornitore(context, comeStr(f['id'])),
                    );
                  }),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Nuovo fornitore o modifica. Restituisce l'id.
Future<String?> apriModuloFornitore(BuildContext context, {Doc? fornitore}) {
  return Navigator.of(context).push<String?>(MaterialPageRoute<String?>(fullscreenDialog: true, builder: (_) => _ModuloFornitore(fornitore: fornitore)));
}

class _ModuloFornitore extends StatefulWidget {
  const _ModuloFornitore({this.fornitore});
  final Doc? fornitore;
  @override
  State<_ModuloFornitore> createState() => _ModuloFornitoreState();
}

class _ModuloFornitoreState extends State<_ModuloFornitore> {
  late final Doc _f = widget.fornitore != null ? clonaDoc(widget.fornitore!) : fornitoreVuoto();
  final _c = <String, TextEditingController>{};
  TextEditingController c(String k) => _c.putIfAbsent(k, () => TextEditingController(text: comeStr(_f[k])));

  @override
  void initState() {
    super.initState();
    c('telefono').text = telefonoLeggibile(comeStr(_f['telefono']));
    c('whatsapp').text = telefonoLeggibile(comeStr(_f['whatsapp']));
    c('minimoOrdineCent').text = F.testoDaCent(comeInt(_f['minimoOrdineCent']));
    c('speseSpedizioneCent').text = F.testoDaCent(comeInt(_f['speseSpedizioneCent']));
  }

  @override
  void dispose() {
    for (final x in _c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _salva() async {
    final d = context.dati;
    final rs = c('ragioneSociale').text.trim();
    if (rs.isEmpty) {
      avviso(context, 'La ragione sociale è obbligatoria.', errore: true);
      return;
    }
    String tel(String k) => c(k).text.trim().isEmpty ? '' : normalizzaTelefono(c(k).text, prefisso: d.prefisso);
    for (final k in ['ragioneSociale', 'piva', 'referente', 'email', 'sito', 'indirizzo', 'condizioniPagamento', 'tempiConsegna', 'sconti', 'note']) {
      _f[k] = c(k).text.trim();
    }
    _f['telefono'] = tel('telefono');
    _f['whatsapp'] = tel('whatsapp');
    _f['minimoOrdineCent'] = F.centDaTesto(c('minimoOrdineCent').text);
    _f['speseSpedizioneCent'] = F.centDaTesto(c('speseSpedizioneCent').text);
    final rec = await d.salva('fornitori', _f);
    if (!mounted) return;
    Navigator.pop(context, comeStr(rec['id']));
    avvisa(widget.fornitore == null ? 'Fornitore aggiunto' : 'Fornitore aggiornato');
  }

  @override
  Widget build(BuildContext context) {
    Widget riga(List<Widget> figli) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < figli.length; i++) ...[if (i > 0) const SizedBox(width: S.s), Expanded(child: figli[i])],
        ]);
    const dec = TextInputType.numberWithOptions(decimal: true);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: Text(widget.fornitore == null ? 'Nuovo fornitore' : 'Modifica fornitore'),
        actions: [Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salva, child: const Text('Salva')))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              Sezione(
                titolo: 'Anagrafica',
                child: Column(children: [
                  Campo(etichetta: 'Ragione sociale *', controller: c('ragioneSociale'), autofocus: widget.fornitore == null, maiuscole: TextCapitalization.words),
                  riga([Campo(etichetta: 'Partita IVA', controller: c('piva'), tastiera: TextInputType.number), Campo(etichetta: 'Referente', controller: c('referente'), maiuscole: TextCapitalization.words)]),
                  Campo(etichetta: 'Indirizzo', controller: c('indirizzo')),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Contatti',
                child: Column(children: [
                  riga([Campo(etichetta: 'Telefono', controller: c('telefono'), tastiera: TextInputType.phone), Campo(etichetta: 'WhatsApp (se diverso)', controller: c('whatsapp'), tastiera: TextInputType.phone)]),
                  Campo(etichetta: 'Email', controller: c('email'), tastiera: TextInputType.emailAddress, maiuscole: TextCapitalization.none),
                  Campo(etichetta: 'Sito web', controller: c('sito'), tastiera: TextInputType.url, maiuscole: TextCapitalization.none),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Condizioni',
                child: Column(children: [
                  riga([Campo(etichetta: 'Pagamento', controller: c('condizioniPagamento')), Campo(etichetta: 'Tempi di consegna', controller: c('tempiConsegna'), placeholder: 'es. 2–3 giorni lavorativi')]),
                  riga([Campo(etichetta: 'Minimo d\'ordine (€)', controller: c('minimoOrdineCent'), tastiera: dec), Campo(etichetta: 'Spedizione (€)', controller: c('speseSpedizioneCent'), tastiera: dec)]),
                  Campo(etichetta: 'Sconti', controller: c('sconti')),
                ]),
              ),
              const SizedBox(height: S.l),
              Campo(etichetta: 'Note', controller: c('note'), righe: 3),
              FilledButton(onPressed: _salva, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Salva')),
            ]),
          ),
        ),
      ),
    );
  }
}
