import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';

/// Carico, scarico, consumo, vendita, reso o rettifica inventario di un prodotto.
Future<void> apriMovimento(BuildContext context, Doc p, String tipo) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (c) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: _Movimento(p: p, tipo: tipo)),
  );
}

/// Se un'uscita porta la giacenza sotto zero chiede conferma. true = si può procedere.
Future<bool> controllaNegativo(BuildContext context, Doc p, num uscita) async {
  final g = giacenzaDi(context.dati, comeStr(p['id']));
  if (qta(g - uscita) >= 0) return true;
  return conferma(context,
      titolo: 'Giacenza insufficiente',
      messaggio: 'Di ${nomeProdotto(p)} risultano ${fmtQta(g, comeStr(p['unita']))}: dopo questa uscita la giacenza sarà ${fmtQta(g - uscita, comeStr(p['unita']))}.\n\nSuccede se un carico non è stato registrato. Puoi procedere e sistemare poi con una rettifica inventario.',
      ok: 'Registra comunque');
}

class _Movimento extends StatefulWidget {
  const _Movimento({required this.p, required this.tipo});
  final Doc p;
  final String tipo;
  @override
  State<_Movimento> createState() => _MovimentoState();
}

class _MovimentoState extends State<_Movimento> {
  final _q = TextEditingController(), _nota = TextEditingController(), _costo = TextEditingController(), _lotto = TextEditingController(), _importo = TextEditingController();
  late String _tipo = widget.tipo;
  String _scadenza = '', _pagamento = '';
  late num _giacenza;

  @override
  void initState() {
    super.initState();
    _giacenza = giacenzaDi(Ambito.of(context).dati, comeStr(widget.p['id']));
    _prepara();
    _q.addListener(() {
      if (_tipo == 'vendita' && widget.p['prezzoVenditaCent'] != null) {
        final n = qtaDaTesto(_q.text);
        if (n != null) _importo.text = F.testoDaCent((n * (comeInt(widget.p['prezzoVenditaCent']) ?? 0)).round());
      }
      setState(() {});
    });
  }

  void _prepara() {
    _q.text = _tipo == 'rettifica' ? testoQta(_giacenza) : '1';
    _costo.text = F.testoDaCent(comeInt(widget.p['costoCent']));
    _lotto.text = comeStr(widget.p['lotto']);
    _scadenza = comeStr(widget.p['scadenza']);
    _importo.text = F.testoDaCent(comeInt(widget.p['prezzoVenditaCent']));
  }

  @override
  void dispose() {
    for (final c in [_q, _nota, _costo, _lotto, _importo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _registra() async {
    final d = context.dati;
    final p = widget.p;
    final u = comeStr(p['unita']);
    final n = qtaDaTesto(_q.text);
    if (n == null || (_tipo != 'rettifica' && n <= 0) || (_tipo == 'rettifica' && n < 0)) {
      avviso(context, 'Controlla la quantità.', errore: true);
      return;
    }
    final nota = _nota.text.trim();
    if (_tipo == 'rettifica' && nota.isEmpty) {
      avviso(context, 'Indica la causale della rettifica (es. inventario, prodotto rotto).', errore: true);
      return;
    }
    if (tipiMovimento[_tipo]!.segno < 0 && !await controllaNegativo(context, p, n)) return;
    if (!mounted) return;
    final nav = Navigator.of(context);
    final demo = p['demo'] == true;
    Doc rec;
    switch (_tipo) {
      case 'rettifica':
        final delta = qta(n - _giacenza);
        if (delta == 0) {
          nav.pop();
          avvisa('Nessuna differenza da registrare.');
          return;
        }
        rec = await registraMovimento(d, prodottoId: comeStr(p['id']), tipo: 'rettifica', quantita: delta, nota: nota, demo: demo);
      case 'carico':
        final costo = F.centDaTesto(_costo.text);
        final lotto = _lotto.text.trim();
        rec = await registraMovimento(d, prodottoId: comeStr(p['id']), tipo: 'carico', quantita: n, nota: nota, costoCent: costo, lotto: lotto, demo: demo);
        final prima = {'costoCent': p['costoCent'], 'lotto': p['lotto'], 'scadenza': p['scadenza']};
        if (costo != null) p['costoCent'] = costo;
        if (lotto.isNotEmpty) p['lotto'] = lotto;
        if (_scadenza.isNotEmpty) p['scadenza'] = _scadenza;
        await d.salva('prodotti', p);
        nav.pop();
        vibra(true);
        avvisa('Carico registrato: +${fmtQta(n, u)}', annulla: () async {
          await d.elimina('movimenti_magazzino', comeStr(rec['id']));
          p.addAll(prima);
          await d.salva('prodotti', p);
        });
        return;
      case 'vendita':
        rec = await registraMovimento(d,
            prodottoId: comeStr(p['id']), tipo: 'vendita', quantita: n, nota: [_pagamento, nota].where((x) => x.isNotEmpty).join(' · '), importoCent: F.centDaTesto(_importo.text) ?? 0, demo: demo);
      default:
        rec = await registraMovimento(d, prodottoId: comeStr(p['id']), tipo: _tipo, quantita: n, nota: nota, demo: demo);
    }
    nav.pop();
    vibra(true);
    avvisa('Registrato: ${tipiMovimento[_tipo]!.nome.toLowerCase()} di ${fmtQta(_tipo == 'rettifica' ? rec['quantita'] : n, u)}', annulla: () async => d.elimina('movimenti_magazzino', comeStr(rec['id'])));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final t = Theme.of(context).textTheme;
    final u = comeStr(p['unita']).isEmpty ? 'pz' : comeStr(p['unita']);
    final n = qtaDaTesto(_q.text);
    final tipi = tipiMovimento.keys.where((k) => k != 'vendita' || p['uso'] != 'interno').toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.l),
      child: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(nomeProdotto(p), style: t.headlineSmall),
          Text('Giacenza attuale: ${fmtQta(_giacenza, u)}', style: t.bodyLarge),
          const SizedBox(height: S.m),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final k in tipi)
              ChoiceChip(
                label: Text(tipiMovimento[k]!.nome),
                selected: _tipo == k,
                onSelected: (_) => setState(() {
                  _tipo = k;
                  _prepara();
                }),
              ),
          ]),
          const SizedBox(height: S.l),
          Campo(
            etichetta: _tipo == 'rettifica' ? 'Quantità contata ($u)' : 'Quantità ($u)',
            controller: _q,
            tastiera: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            aiuto: _tipo == 'rettifica' && n != null ? 'Differenza: ${n - _giacenza > 0 ? '+' : ''}${fmtQta(n - _giacenza, u)}' : null,
          ),
          if (_tipo == 'carico') ...[
            Row(children: [
              Expanded(child: Campo(etichetta: 'Costo unitario (€)', controller: _costo, tastiera: const TextInputType.numberWithOptions(decimal: true))),
              const SizedBox(width: S.s),
              Expanded(child: Campo(etichetta: 'Lotto', controller: _lotto)),
            ]),
            Row(children: [
              Expanded(child: Text('Scadenza', style: t.labelLarge)),
              TextButton(
                onPressed: () async {
                  final g = await scegliData(context, _scadenza.isEmpty ? DateTime.now() : D.daKey(_scadenza));
                  if (g != null) setState(() => _scadenza = D.key(g));
                },
                child: Text(_scadenza.isEmpty ? 'Nessuna' : F.dataKey(_scadenza)),
              ),
              if (_scadenza.isNotEmpty) IconButton(onPressed: () => setState(() => _scadenza = ''), icon: const Icon(Icons.close_rounded), tooltip: 'Togli'),
            ]),
          ],
          if (_tipo == 'vendita') ...[
            Campo(etichetta: 'Importo incassato (€)', controller: _importo, tastiera: const TextInputType.numberWithOptions(decimal: true)),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final x in pagamenti) ChoiceChip(label: Text(x), selected: _pagamento == x, onSelected: (s) => setState(() => _pagamento = s ? x : '')),
            ]),
            const SizedBox(height: S.m),
          ],
          Campo(etichetta: _tipo == 'rettifica' ? 'Causale *' : 'Nota', controller: _nota, placeholder: _tipo == 'rettifica' ? 'es. inventario, prodotto rotto, errore di carico' : null),
          const SizedBox(height: S.s),
          FilledButton(onPressed: _registra, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: Text('Registra ${tipiMovimento[_tipo]!.nome.toLowerCase()}')),
        ]),
      ),
    );
  }
}
