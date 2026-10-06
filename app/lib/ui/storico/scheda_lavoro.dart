import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../../dominio/magazzino.dart';
import '../app.dart';
import '../comuni.dart';
import '../foto.dart';
import '../fornitori/ordini.dart' show scegliProdotto;
import '../piattaforma.dart';
import '../tema.dart';

/// Scheda lavoro (storico): da un appuntamento da completare, da modificare, o nuova per una cliente.
Future<void> apriSchedaLavoro(BuildContext context, {Doc? app, Doc? scheda, String? clienteId}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => SchedaLavoro(app: app, scheda: scheda, clienteId: clienteId),
  ));
}

class SchedaLavoro extends StatefulWidget {
  const SchedaLavoro({super.key, this.app, this.scheda, this.clienteId});
  final Doc? app, scheda;
  final String? clienteId;
  @override
  State<SchedaLavoro> createState() => _SchedaLavoroState();
}

class _NuovaFoto {
  _NuovaFoto(this.bytes, this.tipo);
  final Uint8List bytes;
  final String tipo;
}

class _SchedaLavoroState extends State<SchedaLavoro> {
  bool get _modifica => widget.scheda != null;
  late Doc _s0;
  late String _cliId;
  late String _data, _ora;
  List<Doc> _servizi = [], _prodotti = [];
  String _tecnica = '', _forma = '', _lunghezza = '', _pagamento = '';
  final _durata = TextEditingController(), _colori = TextEditingController(), _importo = TextEditingController(), _note = TextEditingController(), _prossima = TextEditingController();
  List<Doc> _fotoEsistenti = [];
  final Set<String> _fotoRimosse = {};
  final List<_NuovaFoto> _fotoNuove = [];
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final d = Ambito.of(context).dati;
    final app = widget.app, sc = widget.scheda;
    _cliId = comeStr(sc?['clienteId'] ?? app?['clienteId'] ?? widget.clienteId);
    final cli = d.get('clienti', _cliId);
    final p = comeDoc(cli?['preferenze']);
    _s0 = sc != null
        ? clonaDoc(sc)
        : {
            'appuntamentoId': app?['id'],
            'clienteId': _cliId,
            'data': app != null ? D.key(inizioApp(app)) : D.oggiKey(),
            'ora': app != null ? D.hhmm(inizioApp(app)) : D.hhmm(DateTime.now()),
            'servizi': app != null ? clona(serviziApp(app)) : <Doc>[],
            'tecnica': comeStr(p['tecnica']), 'forma': comeStr(p['forma']), 'lunghezza': comeStr(p['lunghezza']), 'colori': '',
            'prodotti': app != null && d.moduloAttivo('magazzino') ? prodottiDaServizi(d, serviziApp(app)) : <Doc>[], 'durataRealeMin': app != null ? durataApp(app) : null, 'importoCent': app != null ? (comeInt(app['prezzoTotaleCent']) ?? 0) : null,
            'metodoPagamento': '', 'note': '', 'noteProssimaVolta': '', 'archiviato': false,
            if (app?['demo'] == true) 'demo': true,
          };
    _data = comeStr(_s0['data']);
    _ora = comeStr(_s0['ora']);
    _servizi = comeListaDoc(_s0['servizi']).map(clonaDoc).toList();
    _prodotti = comeListaDoc(_s0['prodotti']).map(clonaDoc).toList();
    _tecnica = comeStr(_s0['tecnica']);
    _forma = comeStr(_s0['forma']);
    _lunghezza = comeStr(_s0['lunghezza']);
    _pagamento = comeStr(_s0['metodoPagamento']);
    _durata.text = comeStr(_s0['durataRealeMin']);
    _colori.text = comeStr(_s0['colori']);
    _importo.text = F.testoDaCent(comeInt(_s0['importoCent']));
    _note.text = comeStr(_s0['note']);
    _prossima.text = comeStr(_s0['noteProssimaVolta']);
    if (sc != null) _fotoEsistenti = d.elenco('foto', archiviati: true).where((f) => f['schedaId'] == sc['id']).toList();
  }

  @override
  void dispose() {
    for (final c in [_durata, _colori, _importo, _note, _prossima]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _aggiungiFoto(String tipo) async {
    final d = context.dati;
    final cli = d.get('clienti', _cliId);
    if (cli != null && !haConsenso(cli, 'foto')) {
      final ok = await conferma(context, titolo: 'Consenso foto', messaggio: 'Per salvare foto dei lavori serve il consenso della cliente.\n\nHai ottenuto oggi il consenso di ${nomeCliente(cli)}?', ok: 'Sì, registra il consenso');
      if (!ok) return;
      final cons = comeDoc(cli['consensi']);
      cons['foto'] = {'dato': true, 'data': D.oggiKey()};
      cli['consensi'] = cons;
      await d.salva('clienti', cli);
    }
    if (!mounted) return;
    final fonte = await sceltaTra(context, titolo: 'Foto "$tipo"', opzioni: [('libreria', 'Dalla libreria', false), ('camera', 'Scatta ora', true)]);
    if (fonte == null) return;
    try {
      final b = await prendiFoto(fotocamera: fonte == 'camera');
      if (b != null && mounted) setState(() => _fotoNuove.add(_NuovaFoto(b, tipo)));
    } catch (e) {
      if (mounted) avviso(context, 'Impossibile aprire ${fonte == 'camera' ? 'la fotocamera' : 'la libreria'}: controlla i permessi nelle impostazioni del telefono.', errore: true);
    }
  }

  Future<void> _salva() async {
    final d = context.dati;
    if (_data.isEmpty) return;
    setState(() => _salvando = true);
    final cli = d.get('clienti', _cliId);
    final rec = _modifica ? clonaDoc(widget.scheda!) : clonaDoc(_s0);
    rec.addAll({
      'data': _data,
      'ora': _ora,
      'servizi': clona(_servizi),
      'tecnica': _tecnica,
      'forma': _forma,
      'lunghezza': _lunghezza,
      'colori': _colori.text.trim(),
      'prodotti': _prodotti
          .where((x) => comeStr(x['prodottoId']).isNotEmpty || comeStr(x['nome']).trim().isNotEmpty)
          .map((x) => {...x, 'nome': comeStr(x['nome']).trim(), 'quantita': comeStr(x['quantita']).replaceAll(',', '.'), 'scala': x['scala'] == true && comeStr(x['prodottoId']).isNotEmpty && d.moduloAttivo('magazzino')})
          .toList(),
      'durataRealeMin': int.tryParse(_durata.text.trim()),
      'importoCent': F.centDaTesto(_importo.text) ?? 0,
      'metodoPagamento': _pagamento,
      'note': _note.text.trim(),
      'noteProssimaVolta': _prossima.text.trim(),
    });
    rec['id'] ??= uid();
    // Consumi di magazzino: ricalcolati da zero a ogni salvataggio (solo i prodotti con "Scala dal magazzino")
    final consumi = consumiScheda(d, rec, cli != null ? nomeCliente(cli) : 'cliente');
    if (consumi.nuovi.isNotEmpty) {
      final gia = mappaGiacenze(d);
      for (final m in consumi.precedenti) {
        gia[comeStr(m['prodottoId'])] = qta((gia[comeStr(m['prodottoId'])] ?? 0) - numero(m['quantita']));
      }
      final uscite = <String, num>{};
      for (final m in consumi.nuovi) {
        uscite[comeStr(m['prodottoId'])] = qta((uscite[comeStr(m['prodottoId'])] ?? 0) - numero(m['quantita']));
      }
      final negativi = [
        for (final e in uscite.entries)
          if (qta((gia[e.key] ?? 0) - e.value) < 0)
            '${nomeProdotto(d.get('prodotti', e.key))}: risultano ${fmtQta(gia[e.key] ?? 0, comeStr(d.get('prodotti', e.key)?['unita']))}, ne usi ${fmtQta(e.value, comeStr(d.get('prodotti', e.key)?['unita']))}',
      ];
      if (negativi.isNotEmpty) {
        final ok = await conferma(context, titolo: 'Giacenza insufficiente', messaggio: 'Alcuni prodotti andrebbero sotto zero:\n${negativi.map((x) => '• $x').join('\n')}\n\nPuoi salvare lo stesso e correggere poi con una rettifica inventario.', ok: 'Salva comunque');
        if (!ok || !mounted) {
          if (mounted) setState(() => _salvando = false);
          return;
        }
      }
    }
    final nuove = <Doc>[];
    for (final f in _fotoNuove) {
      final id = uid();
      await d.salvaBytesFoto(id, f.bytes);
      nuove.add({'id': id, 'schedaId': rec['id'], 'clienteId': rec['clienteId'], 'tipo': f.tipo, 'blobTipo': 'image/jpeg', if (rec['demo'] == true) 'demo': true});
    }
    Map<String, dynamic>? appPrec;
    final app = widget.app != null ? d.get('appuntamenti', comeStr(widget.app!['id'])) : null;
    await d.inBlocco(() async {
      if (nuove.isNotEmpty) await d.salvaMolti('foto', nuove);
      if (_fotoRimosse.isNotEmpty) await d.eliminaMolti('foto', _fotoRimosse.toList());
      rec['fotoIds'] = [..._fotoEsistenti.where((f) => !_fotoRimosse.contains(f['id'])).map((f) => f['id']), ...nuove.map((f) => f['id'])];
      await d.salva('schede_lavoro', rec);
      await d.eliminaMolti('movimenti_magazzino', [for (final m in consumi.precedenti) comeStr(m['id'])]);
      await d.salvaMolti('movimenti_magazzino', consumi.nuovi);
      if (app != null && !_modifica) {
        appPrec = {'stato': app['stato'], 'schedaId': app['schedaId']};
        app['stato'] = 'completato';
        app['schedaId'] = rec['id'];
        await d.salva('appuntamenti', app);
      }
    });
    if (!mounted) return;
    Navigator.pop(context);
    vibra(true);
    final msgMag = consumi.nuovi.isEmpty ? '' : ' · ${consumi.nuovi.length} prodott${consumi.nuovi.length == 1 ? 'o scalato' : 'i scalati'} dal magazzino';
    if (_modifica) {
      avvisa('Scheda lavoro aggiornata$msgMag');
    } else {
      avvisa((app != null ? 'Appuntamento completato · scheda salvata' : 'Scheda lavoro salvata') + msgMag, annulla: () async {
        await d.inBlocco(() async {
          await d.eliminaMolti('movimenti_magazzino', [for (final m in consumi.nuovi) comeStr(m['id'])]);
          await d.eliminaMolti('foto', [for (final f in nuove) comeStr(f['id'])]);
          await d.elimina('schede_lavoro', comeStr(rec['id']));
          if (app != null && appPrec != null) {
            app['stato'] = appPrec!['stato'];
            app['schedaId'] = appPrec!['schedaId'];
            await d.salva('appuntamenti', app);
          }
        });
      });
    }
  }

  Future<void> _elimina() async {
    final ok = await conferma(context, titolo: 'Eliminare la scheda lavoro?', messaggio: 'Verrà archiviata: potrai ripristinarla da Altro → Elementi archiviati.', ok: 'Elimina', pericolo: true);
    if (!ok || !mounted) return;
    final d = context.dati;
    final id = comeStr(widget.scheda!['id']);
    await d.archivia('schede_lavoro', id);
    if (!mounted) return;
    Navigator.pop(context);
    avvisa('Scheda lavoro eliminata', annulla: () async => d.ripristina('schede_lavoro', id));
  }

  Widget _scelte(String titolo, List<String> opzioni, String valore, ValueChanged<String> fn) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titolo, style: t.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in opzioni) ChoiceChip(label: Text(o), selected: valore == o, onSelected: (s) => setState(() => fn(s ? o : ''))),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cli = d.get('clienti', _cliId);
    final listino = serviziAttivi(d);
    final app = widget.app;
    final acconto = comeInt(app?['accontoCent']) ?? 0;
    final esistenti = _fotoEsistenti.where((f) => !_fotoRimosse.contains(f['id'])).toList();
    final magazzino = d.moduloAttivo('magazzino');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: Text(_modifica ? 'Scheda lavoro' : (app != null ? 'Completa appuntamento' : 'Nuova scheda lavoro')),
        actions: [
          if (_modifica) IconButton(tooltip: 'Elimina', onPressed: _elimina, icon: const Icon(Icons.delete_outline_rounded)),
          Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salvando ? null : _salva, child: const Text('Salva'))),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              Text(cli != null ? nomeCliente(cli) : 'Cliente eliminata', style: t.headlineSmall),
              if (app != null) Text('Appuntamento di ${F.giornoLungo(inizioApp(app)).toLowerCase()}', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              if (haAvvertenze(cli)) ...[const SizedBox(height: S.m), Avvertenze(comeStr(cli!['avvertenze']))],
              const SizedBox(height: S.l),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text(F.dataKey(_data)),
                    onPressed: () async {
                      final g = await scegliData(context, D.daKey(_data));
                      if (g != null) setState(() => _data = D.key(g));
                    },
                  ),
                ),
                const SizedBox(width: S.s),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(_ora.isEmpty ? '--:--' : _ora),
                    onPressed: () async {
                      final m = _ora.isEmpty ? 600 : D.minDaHHMM(_ora);
                      final o = await scegliOra(context, TimeOfDay(hour: m ~/ 60, minute: m % 60));
                      if (o != null) setState(() => _ora = '${D.p2(o.hour)}:${D.p2(o.minute)}');
                    },
                  ),
                ),
              ]),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Servizi eseguiti',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final s in _servizi)
                    Row(children: [
                      Expanded(child: Text('${s['nome']}${(comeInt(s['quantita']) ?? 1) > 1 ? ' ×${s['quantita']}' : ''}')),
                      Text(F.euro((comeInt(s['prezzoCent']) ?? 0) * (comeInt(s['quantita']) ?? 1))),
                      IconButton(onPressed: () => setState(() => _servizi.remove(s)), icon: const Icon(Icons.close_rounded), tooltip: 'Rimuovi'),
                    ]),
                  if (_servizi.isEmpty) Text('Nessun servizio', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  if (listino.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PopupMenuButton<Doc>(
                        onSelected: (x) => setState(() {
                          _servizi.add({'servizioId': x['id'], 'nome': x['nome'], 'durata': x['durata'], 'prezzoCent': x['prezzoCent'], 'quantita': 1, 'colore': x['colore'], 'richiamoGiorni': x['richiamoGiorni']});
                          if (!_modifica && app == null) _importo.text = F.testoDaCent(_servizi.fold<int>(0, (t, y) => t + (comeInt(y['prezzoCent']) ?? 0) * (comeInt(y['quantita']) ?? 1)));
                        }),
                        itemBuilder: (c) => [for (final x in listino) PopupMenuItem(value: x, child: Text('${x['nome']} (${F.euro(comeInt(x['prezzoCent']))})'))],
                        child: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.add_rounded), SizedBox(width: 6), Text('Aggiungi servizio')])),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Il lavoro',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _scelte('Tecnica', tecniche, _tecnica, (v) => _tecnica = v),
                  _scelte('Forma', forme, _forma, (v) => _forma = v),
                  _scelte('Lunghezza', lunghezze, _lunghezza, (v) => _lunghezza = v),
                  Campo(etichetta: 'Colori / codici usati', controller: _colori, placeholder: 'marca, linea, codice'),
                  Campo(etichetta: 'Durata reale (minuti)', controller: _durata, tastiera: TextInputType.number),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Prodotti usati',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final p in _prodotti)
                    Padding(
                      key: ObjectKey(p),
                      padding: const EdgeInsets.only(bottom: S.m),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: comeStr(p['prodottoId']).isNotEmpty
                                ? Text(nomeProdotto(d.get('prodotti', comeStr(p['prodottoId'])) ?? {'nome': p['nome']}), style: t.titleSmall)
                                : TextFormField(initialValue: comeStr(p['nome']), decoration: const InputDecoration(hintText: 'Nome del prodotto'), onChanged: (v) => p['nome'] = v),
                          ),
                          IconButton(onPressed: () => setState(() => _prodotti.remove(p)), icon: const Icon(Icons.close_rounded), tooltip: 'Rimuovi'),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Expanded(child: TextFormField(initialValue: testoQta(p['quantita']), decoration: const InputDecoration(labelText: 'Quantità'), keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (v) => p['quantita'] = v)),
                          const SizedBox(width: 6),
                          Expanded(child: TextFormField(initialValue: comeStr(p['lotto']), decoration: const InputDecoration(labelText: 'Lotto'), onChanged: (v) => p['lotto'] = v)),
                        ]),
                        if (magazzino && comeStr(p['prodottoId']).isNotEmpty)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: p['scala'] == true,
                            onChanged: (v) => setState(() => p['scala'] = v == true),
                            title: const Text('Scala dal magazzino'),
                          ),
                      ]),
                    ),
                  if (magazzino) Text('Solo i prodotti con "Scala dal magazzino" vengono scaricati dalla giacenza, al salvataggio.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  Wrap(spacing: S.s, children: [
                    if (magazzino)
                      TextButton.icon(
                        onPressed: () async {
                          final x = await scegliProdotto(context);
                          if (x != null) {
                            setState(() => _prodotti.add({'prodottoId': x['id'], 'nome': nomeProdotto(x), 'quantita': 1, 'lotto': comeStr(x['lotto']), 'scala': true}));
                          }
                        },
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Dal magazzino'),
                      ),
                    TextButton.icon(onPressed: () => setState(() => _prodotti.add({'nome': '', 'quantita': '', 'lotto': '', 'prodottoId': null, 'scala': false})), icon: const Icon(Icons.add_rounded), label: Text(magazzino ? 'Scritto a mano' : 'Aggiungi prodotto')),
                  ]),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Pagamento',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Campo(
                    etichetta: 'Importo incassato (€)',
                    controller: _importo,
                    tastiera: const TextInputType.numberWithOptions(decimal: true),
                    aiuto: acconto > 0 ? 'Comprende l\'acconto di ${F.euro(acconto)} già versato: da incassare ora ${F.euro(((comeInt(app?['prezzoTotaleCent']) ?? 0) - acconto).clamp(0, 1 << 31))}.' : null,
                  ),
                  _scelte('Metodo di pagamento', pagamenti, _pagamento, (v) => _pagamento = v),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Foto prima / dopo',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (cli != null && !haConsenso(cli, 'foto')) const Padding(padding: EdgeInsets.only(bottom: S.s), child: Riquadro(tipo: 'avviso', testo: 'La cliente non ha registrato il consenso alle foto: te lo chiederò prima di aggiungerne.')),
                  Wrap(spacing: S.m, runSpacing: S.m, children: [
                    for (final f in esistenti) FotoMiniatura(key: ValueKey(f['id']), id: comeStr(f['id']), etichetta: comeStr(f['tipo']), suRimuovi: () => setState(() => _fotoRimosse.add(comeStr(f['id'])))),
                    for (final f in _fotoNuove) FotoMiniatura(key: ObjectKey(f), id: '', bytes: f.bytes, etichetta: f.tipo, suRimuovi: () => setState(() => _fotoNuove.remove(f))),
                  ]),
                  if (esistenti.isEmpty && _fotoNuove.isEmpty) Text('Nessuna foto', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: S.m),
                  Row(children: [
                    Expanded(child: OutlinedButton.icon(onPressed: () => _aggiungiFoto('prima'), icon: const Icon(Icons.photo_camera_outlined), label: const Text('Foto prima'))),
                    const SizedBox(width: S.s),
                    Expanded(child: OutlinedButton.icon(onPressed: () => _aggiungiFoto('dopo'), icon: const Icon(Icons.photo_camera_rounded), label: const Text('Foto dopo'))),
                  ]),
                ]),
              ),
              const SizedBox(height: S.l),
              Campo(etichetta: 'Note sul lavoro', controller: _note, righe: 3),
              Campo(etichetta: 'Note per la prossima volta', controller: _prossima, righe: 3, aiuto: 'Le ritrovi quando fissi il prossimo appuntamento di questa cliente.'),
              const SizedBox(height: S.l),
              FilledButton.icon(
                onPressed: _salvando ? null : _salva,
                icon: const Icon(Icons.check_rounded),
                label: Text(_modifica ? 'Salva' : (app != null ? 'Completa e salva' : 'Salva scheda')),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
