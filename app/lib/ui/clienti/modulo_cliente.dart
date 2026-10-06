import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';

/// Nuova cliente o modifica: dati, preferenze, consensi, avvertenze (solo con consenso ai dati sanitari).
Future<String?> apriModuloCliente(BuildContext context, {Doc? cliente}) {
  return Navigator.of(context).push(MaterialPageRoute<String?>(fullscreenDialog: true, builder: (_) => ModuloCliente(cliente: cliente)));
}

class ModuloCliente extends StatefulWidget {
  const ModuloCliente({super.key, this.cliente});
  final Doc? cliente;
  @override
  State<ModuloCliente> createState() => _ModuloClienteState();
}

class _ModuloClienteState extends State<ModuloCliente> {
  late final Doc _c = widget.cliente != null ? clonaDoc(widget.cliente!) : nuovaClienteVuota();
  final _nome = TextEditingController(), _cognome = TextEditingController(), _tel = TextEditingController(), _email = TextEditingController();
  final _note = TextEditingController(), _avv = TextEditingController(), _colori = TextEditingController(), _tag = TextEditingController();
  String? _nascita;
  late Doc _pref, _cons;
  List<String> _tags = [];

  @override
  void initState() {
    super.initState();
    _nome.text = comeStr(_c['nome']);
    _cognome.text = comeStr(_c['cognome']);
    _tel.text = telefonoLeggibile(comeStr(_c['telefono']));
    _email.text = comeStr(_c['email']);
    _note.text = comeStr(_c['note']);
    _avv.text = comeStr(_c['avvertenze']);
    _nascita = comeStr(_c['dataNascita']).isEmpty ? null : comeStr(_c['dataNascita']);
    _pref = clonaDoc(comeDoc(_c['preferenze']));
    _colori.text = comeStr(_pref['colori']);
    _cons = {
      for (final k in consensi.keys) k: {'dato': comeDoc(comeDoc(_c['consensi'])[k])['dato'] == true, 'data': comeStr(comeDoc(comeDoc(_c['consensi'])[k])['data'])},
    };
    _tags = comeListaStr(_c['tag']);
  }

  @override
  void dispose() {
    for (final c in [_nome, _cognome, _tel, _email, _note, _avv, _colori, _tag]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _sanitari => comeDoc(_cons['sanitari'])['dato'] == true;

  Future<void> _salva() async {
    final d = context.dati;
    if (_nome.text.trim().isEmpty && _cognome.text.trim().isEmpty) {
      avviso(context, 'Scrivi almeno il nome.', errore: true);
      return;
    }
    final tel = normalizzaTelefono(_tel.text, prefisso: d.prefisso);
    // possibile doppione (stesso telefono)
    if (tel.isNotEmpty) {
      final doppia = d.elenco('clienti').where((x) => x['id'] != _c['id'] && comeStr(x['telefono']) == tel).toList();
      if (doppia.isNotEmpty) {
        final ok = await conferma(context, titolo: 'Telefono già presente', messaggio: 'Il numero è già nella scheda di ${nomeCliente(doppia.first)}. Vuoi salvare lo stesso?', ok: 'Salva');
        if (!ok || !mounted) return;
      }
    }
    _c['nome'] = _nome.text.trim();
    _c['cognome'] = _cognome.text.trim();
    _c['telefono'] = tel;
    _c['email'] = _email.text.trim();
    _c['dataNascita'] = _nascita ?? '';
    _c['note'] = _note.text.trim();
    _c['avvertenze'] = _sanitari ? _avv.text.trim() : '';
    _pref['colori'] = _colori.text.trim();
    _c['preferenze'] = _pref;
    _c['consensi'] = _cons;
    _c['tag'] = _tags;
    _c['archiviato'] = _c['archiviato'] ?? false;
    final rec = await d.salva('clienti', _c);
    if (!mounted) return;
    final r = radice(context);
    Navigator.pop(context, comeStr(rec['id']));
    avviso(r, widget.cliente == null ? 'Cliente salvata' : 'Modifiche salvate');
  }

  Widget _scelte(String titolo, List<String> opzioni, String chiave) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titolo, style: t.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final o in opzioni) ChoiceChip(label: Text(o), selected: _pref[chiave] == o, onSelected: (s) => setState(() => _pref[chiave] = s ? o : '')),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final tuttiTag = <String>{for (final c in d.elenco('clienti')) ...comeListaStr(c['tag']), ..._tags}.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        title: Text(widget.cliente == null ? 'Nuova cliente' : 'Modifica cliente'),
        actions: [Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salva, child: const Text('Salva')))],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              Sezione(
                titolo: 'Dati',
                child: Column(children: [
                  Row(children: [
                    Expanded(child: Campo(etichetta: 'Nome', controller: _nome, maiuscole: TextCapitalization.words, autofocus: widget.cliente == null)),
                    const SizedBox(width: S.s),
                    Expanded(child: Campo(etichetta: 'Cognome', controller: _cognome, maiuscole: TextCapitalization.words)),
                  ]),
                  Campo(etichetta: 'Telefono / WhatsApp', controller: _tel, tastiera: TextInputType.phone, aiuto: 'Senza prefisso viene aggiunto +${d.prefisso}.'),
                  Campo(etichetta: 'Email', controller: _email, tastiera: TextInputType.emailAddress, maiuscole: TextCapitalization.none),
                  Row(children: [
                    Expanded(child: Text('Data di nascita (facoltativa)', style: t.labelLarge)),
                    TextButton(
                      onPressed: () async {
                        final g = await scegliData(context, _nascita == null ? DateTime(1990, 1, 1) : D.daKey(_nascita!));
                        if (g != null) setState(() => _nascita = D.key(g));
                      },
                      child: Text(_nascita == null ? 'Scegli' : F.dataKey(_nascita)),
                    ),
                    if (_nascita != null) IconButton(onPressed: () => setState(() => _nascita = null), icon: const Icon(Icons.close_rounded), tooltip: 'Togli'),
                  ]),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Preferenze',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _scelte('Forma', forme, 'forma'),
                  _scelte('Lunghezza', lunghezze, 'lunghezza'),
                  _scelte('Tecnica preferita', tecniche, 'tecnica'),
                  Campo(etichetta: 'Colori / codici preferiti', controller: _colori),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Consensi',
                child: Column(children: [
                  for (final e in consensi.entries)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.value),
                      subtitle: comeDoc(_cons[e.key])['dato'] == true && comeStr(comeDoc(_cons[e.key])['data']).isNotEmpty ? Text('Registrato il ${F.dataKey(comeStr(comeDoc(_cons[e.key])['data']))}') : null,
                      value: comeDoc(_cons[e.key])['dato'] == true,
                      onChanged: (v) => setState(() => _cons[e.key] = {'dato': v, 'data': v ? D.oggiKey() : ''}),
                    ),
                ]),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Avvertenze e sensibilità',
                child: _sanitari
                    ? Campo(etichetta: 'Allergie, reazioni (es. acrilati/HEMA), unghie fragili…', controller: _avv, righe: 3, aiuto: 'Compaiono in rosso nell\'agenda e nelle schede.')
                    : Riquadro(tipo: 'avviso', testo: 'Per annotare allergie o reazioni serve il consenso ai dati sanitari. Attivalo qui sopra dopo averlo raccolto.${_avv.text.isNotEmpty ? '\n\nSenza consenso le avvertenze già scritte verranno cancellate al salvataggio.' : ''}'),
              ),
              const SizedBox(height: S.l),
              Sezione(
                titolo: 'Etichette',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final tg in tuttiTag)
                      FilterChip(label: Text(tg), selected: _tags.contains(tg), onSelected: (s) => setState(() => s ? _tags.add(tg) : _tags.remove(tg))),
                  ]),
                  const SizedBox(height: S.s),
                  TextField(
                    controller: _tag,
                    decoration: InputDecoration(
                      hintText: 'Nuova etichetta (es. vip, sposa)',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.add_rounded),
                        onPressed: () => setState(() {
                          final v = _tag.text.trim().toLowerCase();
                          if (v.isNotEmpty && !_tags.contains(v)) _tags.add(v);
                          _tag.clear();
                        }),
                      ),
                    ),
                    onSubmitted: (v) => setState(() {
                      final x = v.trim().toLowerCase();
                      if (x.isNotEmpty && !_tags.contains(x)) _tags.add(x);
                      _tag.clear();
                    }),
                  ),
                ]),
              ),
              const SizedBox(height: S.l),
              Campo(etichetta: 'Note', controller: _note, righe: 4),
              Text('I dati restano su questo dispositivo (e nel tuo cloud cifrato, se attivo).', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }
}
