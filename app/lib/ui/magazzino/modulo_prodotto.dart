import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../foto.dart';
import '../piattaforma.dart';
import '../tema.dart';

/// Nuovo prodotto o modifica. Restituisce l'id del prodotto salvato.
Future<String?> apriModuloProdotto(BuildContext context, {Doc? prodotto, String? fornitoreId}) {
  return Navigator.of(context).push<String?>(MaterialPageRoute<String?>(fullscreenDialog: true, builder: (_) => _ModuloProdotto(prodotto: prodotto, fornitoreId: fornitoreId)));
}

class _ModuloProdotto extends StatefulWidget {
  const _ModuloProdotto({this.prodotto, this.fornitoreId});
  final Doc? prodotto;
  final String? fornitoreId;
  @override
  State<_ModuloProdotto> createState() => _ModuloProdottoState();
}

class _ModuloProdottoState extends State<_ModuloProdotto> {
  late final Doc _p = widget.prodotto != null ? clonaDoc(widget.prodotto!) : {...prodottoVuoto(), 'fornitoreId': widget.fornitoreId};
  final _c = <String, TextEditingController>{};
  String _categoria = '', _unita = 'pz', _uso = 'interno', _scadenza = '', _apertura = '';
  String? _fornitore;
  bool _rimuoviFoto = false, _salvando = false;
  Uint8List? _fotoNuova;

  TextEditingController c(String k) => _c.putIfAbsent(k, TextEditingController.new);

  @override
  void initState() {
    super.initState();
    c('nome').text = comeStr(_p['nome']);
    c('cod').text = comeStr(_p['codiceColore']);
    c('marca').text = comeStr(_p['marca']);
    c('linea').text = comeStr(_p['linea']);
    c('scorta').text = testoQta(_p['scortaMinima']);
    c('costo').text = F.testoDaCent(comeInt(_p['costoCent']));
    c('prezzo').text = F.testoDaCent(comeInt(_p['prezzoVenditaCent']));
    c('codf').text = comeStr(_p['codiceFornitore']);
    c('lotto').text = comeStr(_p['lotto']);
    c('pao').text = comeStr(_p['paoMesi']);
    c('note').text = comeStr(_p['note']);
    c('gia');
    _categoria = comeStr(_p['categoria']);
    _unita = comeStr(_p['unita']).isEmpty ? 'pz' : comeStr(_p['unita']);
    _uso = comeStr(_p['uso']).isEmpty ? 'interno' : comeStr(_p['uso']);
    _scadenza = comeStr(_p['scadenza']);
    _apertura = comeStr(_p['dataApertura']);
    _fornitore = comeStr(_p['fornitoreId']).isEmpty ? null : comeStr(_p['fornitoreId']);
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
    final nome = c('nome').text.trim();
    if (nome.isEmpty) {
      avviso(context, 'Il nome è obbligatorio.', errore: true);
      return;
    }
    setState(() => _salvando = true);
    final nuovo = widget.prodotto == null;
    _p.addAll({
      'nome': nome, 'codiceColore': c('cod').text.trim(), 'marca': c('marca').text.trim(), 'linea': c('linea').text.trim(), 'categoria': _categoria,
      'unita': _unita, 'scortaMinima': qtaDaTesto(c('scorta').text), 'uso': _uso, 'costoCent': F.centDaTesto(c('costo').text), 'prezzoVenditaCent': F.centDaTesto(c('prezzo').text),
      'fornitoreId': _fornitore, 'codiceFornitore': c('codf').text.trim(), 'lotto': c('lotto').text.trim(), 'scadenza': _scadenza,
      'paoMesi': int.tryParse(c('pao').text.trim()), 'dataApertura': _apertura, 'note': c('note').text.trim(),
    });
    _p['id'] ??= uid();
    await d.inBlocco(() async {
      final vecchia = comeStr(_p['fotoId']);
      if ((_rimuoviFoto || _fotoNuova != null) && vecchia.isNotEmpty) {
        await d.elimina('foto', vecchia);
        _p['fotoId'] = null;
      }
      if (_fotoNuova != null) {
        final idF = uid();
        await d.salvaBytesFoto(idF, _fotoNuova!);
        await d.salva('foto', {'id': idF, 'prodottoId': _p['id'], 'tipo': 'prodotto', 'blobTipo': 'image/jpeg', if (_p['demo'] == true) 'demo': true});
        _p['fotoId'] = idF;
      }
      await d.salva('prodotti', _p);
      final iniziale = nuovo ? qtaDaTesto(c('gia').text) : null;
      if (iniziale != null && iniziale != 0) {
        await registraMovimento(d, prodottoId: comeStr(_p['id']), tipo: iniziale > 0 ? 'carico' : 'rettifica', quantita: iniziale, nota: 'Giacenza iniziale', costoCent: comeInt(_p['costoCent']));
      }
    });
    if (!mounted) return;
    Navigator.pop(context, comeStr(_p['id']));
    avvisa(nuovo ? 'Prodotto aggiunto' : 'Prodotto aggiornato');
  }

  Widget _data(String etichetta, String valore, ValueChanged<String> fn) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.s),
      child: Row(children: [
        Expanded(child: Text(etichetta, style: t.labelLarge)),
        TextButton(
          onPressed: () async {
            final g = await scegliData(context, valore.isEmpty ? DateTime.now() : D.daKey(valore));
            if (g != null) setState(() => fn(D.key(g)));
          },
          child: Text(valore.isEmpty ? 'Scegli' : F.dataKey(valore)),
        ),
        if (valore.isNotEmpty) IconButton(onPressed: () => setState(() => fn('')), icon: const Icon(Icons.close_rounded), tooltip: 'Togli'),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final categorie = {...comeListaStr(d.cfg['categorieProdotti']), if (_categoria.isNotEmpty) _categoria}.toList();
    final marche = {...comeListaStr(d.cfg['marche']), for (final x in d.elenco('prodotti')) comeStr(x['marca'])}.where((x) => x.isNotEmpty).toList()..sort();
    final nuovo = widget.prodotto == null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: Text(nuovo ? 'Nuovo prodotto' : 'Modifica prodotto'),
        actions: [Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salvando ? null : _salva, child: const Text('Salva')))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              Sezione(
                titolo: 'Prodotto',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Campo(etichetta: 'Nome *', controller: c('nome'), autofocus: nuovo, placeholder: 'es. Gel costruttore rosa'),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Campo(etichetta: 'Codice colore', controller: c('cod'))),
                    const SizedBox(width: S.s),
                    Expanded(child: Campo(etichetta: 'Linea', controller: c('linea'))),
                  ]),
                  Campo(etichetta: 'Marca', controller: c('marca'), maiuscole: TextCapitalization.words),
                  if (marche.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.m),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [for (final m in marche.take(12)) ActionChip(label: Text(m), onPressed: () => setState(() => c('marca').text = m))]),
                    ),
                  Text('Categoria', style: t.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final x in categorie) ChoiceChip(label: Text(x), selected: _categoria == x, onSelected: (s) => setState(() => _categoria = s ? x : ''))]),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Quantità e prezzi',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Unità', style: t.labelLarge),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(segments: [for (final u in unita.keys) ButtonSegment(value: u, label: Text(u))], selected: {_unita}, onSelectionChanged: (s) => setState(() => _unita = s.first)),
                  const SizedBox(height: S.m),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (nuovo) ...[Expanded(child: Campo(etichetta: 'Giacenza iniziale', controller: c('gia'), tastiera: const TextInputType.numberWithOptions(decimal: true), placeholder: '0')), const SizedBox(width: S.s)],
                    Expanded(child: Campo(etichetta: 'Scorta minima', controller: c('scorta'), tastiera: const TextInputType.numberWithOptions(decimal: true), aiuto: 'Sotto questa quantità ricevi un avviso.')),
                  ]),
                  Text('Uso', style: t.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final e in usiProdotto.entries) ChoiceChip(label: Text(e.value), selected: _uso == e.key, onSelected: (_) => setState(() => _uso = e.key))]),
                  const SizedBox(height: S.m),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Campo(etichetta: 'Costo per unità (€)', controller: c('costo'), tastiera: const TextInputType.numberWithOptions(decimal: true))),
                    const SizedBox(width: S.s),
                    if (_uso != 'interno') Expanded(child: Campo(etichetta: 'Prezzo di vendita (€)', controller: c('prezzo'), tastiera: const TextInputType.numberWithOptions(decimal: true))),
                  ]),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Fornitore',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CampoScelta<String>(etichetta: 'Fornitore preferito', valore: _fornitore, opzioni: [for (final f in fornitoriAttivi(d)) (comeStr(f['id']), nomeFornitore(f))], suCambio: (v) => setState(() => _fornitore = v), vuoto: 'Nessuno'),
                  Campo(etichetta: 'Codice del fornitore', controller: c('codf')),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Lotto, scadenza e PAO',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Campo(etichetta: 'Lotto', controller: c('lotto')),
                  _data('Scadenza', _scadenza, (v) => _scadenza = v),
                  Campo(etichetta: 'PAO (mesi dopo l\'apertura)', controller: c('pao'), tastiera: TextInputType.number, aiuto: 'Il numero nel barattolino aperto stampato sulla confezione (es. 12M).'),
                  _data('Data di apertura', _apertura, (v) => _apertura = v),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Foto',
                child: Row(children: [
                  if (_fotoNuova != null)
                    FotoMiniatura(key: ObjectKey(_fotoNuova), id: '', bytes: _fotoNuova, dimensione: 76)
                  else if (comeStr(_p['fotoId']).isNotEmpty && !_rimuoviFoto)
                    FotoMiniatura(id: comeStr(_p['fotoId']), dimensione: 76),
                  const SizedBox(width: S.m),
                  Expanded(
                    child: Wrap(spacing: S.s, runSpacing: S.s, children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final s = await sceltaTra(context, titolo: 'Foto del prodotto', opzioni: [('libreria', 'Dalla libreria', false), ('camera', 'Scatta ora', true)]);
                          if (s == null) return;
                          final b = await prendiFoto(fotocamera: s == 'camera');
                          if (b != null) setState(() => _fotoNuova = b);
                        },
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(comeStr(_p['fotoId']).isNotEmpty || _fotoNuova != null ? 'Cambia' : 'Aggiungi'),
                      ),
                      if (comeStr(_p['fotoId']).isNotEmpty || _fotoNuova != null)
                        TextButton(onPressed: () => setState(() {
                              _fotoNuova = null;
                              _rimuoviFoto = true;
                            }), child: const Text('Rimuovi')),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: S.l),
              Campo(etichetta: 'Note', controller: c('note'), righe: 3),
              FilledButton(onPressed: _salvando ? null : _salva, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Salva')),
            ]),
          ),
        ),
      ),
    );
  }
}
