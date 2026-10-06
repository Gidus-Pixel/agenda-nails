import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';

/// Nuovo appuntamento o modifica di uno esistente (pagina intera).
Future<void> apriModuloAppuntamento(BuildContext context, {Doc? app, DateTime? inizio, String? clienteId, List<Doc>? servizi, String? note}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => ModuloAppuntamento(app: app, inizio: inizio, clienteId: clienteId, servizi: servizi, note: note),
  ));
}

class ModuloAppuntamento extends StatefulWidget {
  const ModuloAppuntamento({super.key, this.app, this.inizio, this.clienteId, this.servizi, this.note});
  final Doc? app;
  final DateTime? inizio;
  final String? clienteId;
  final List<Doc>? servizi;
  final String? note;
  @override
  State<ModuloAppuntamento> createState() => _ModuloAppuntamentoState();
}

class _ModuloAppuntamentoState extends State<ModuloAppuntamento> {
  bool get _modifica => widget.app != null;
  String? _clienteId;
  final _cerca = TextEditingController();
  bool _nuovaCliente = false;
  final _nNome = TextEditingController(), _nCognome = TextEditingController(), _nTel = TextEditingController();
  List<Doc> _servizi = [];
  late DateTime _inizio;
  final _durata = TextEditingController(), _prezzo = TextEditingController(), _acconto = TextEditingController(), _note = TextEditingController();
  bool _durataManuale = false, _prezzoManuale = false;
  String? _operatrice;
  String _stato = 'prenotato';
  int _ogniSettimane = 0, _volte = 4;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final a = widget.app;
    final d = Ambito.of(context).dati;
    if (a != null) {
      _clienteId = comeStr(a['clienteId']);
      _servizi = clona(serviziApp(a));
      _inizio = inizioApp(a);
      _durata.text = '${durataApp(a)}';
      _prezzo.text = F.testoDaCent(comeInt(a['prezzoTotaleCent']) ?? 0);
      _acconto.text = (comeInt(a['accontoCent']) ?? 0) > 0 ? F.testoDaCent(comeInt(a['accontoCent'])) : '';
      _note.text = comeStr(a['note']);
      _durataManuale = a['durataManuale'] == true;
      _prezzoManuale = a['prezzoManuale'] == true;
      _operatrice = comeStr(a['operatriceId']).isEmpty ? null : comeStr(a['operatriceId']);
      _stato = statoApp(a);
    } else {
      _clienteId = widget.clienteId;
      _servizi = clona(widget.servizi ?? <Doc>[]);
      final passo = d.slotMinuti;
      _inizio = widget.inizio ?? D.arrotondaSu(DateTime.now().add(const Duration(minutes: 30)), passo < 5 ? 5 : passo);
      _note.text = widget.note ?? '';
      _operatrice = comeStr(d.operatrici.first['id']);
      _ricalcola();
    }
    _cerca.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    for (final c in [_cerca, _nNome, _nCognome, _nTel, _durata, _prezzo, _acconto, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  int get _durataServizi => _servizi.fold(0, (t, s) => t + (comeInt(s['durata']) ?? 0) * (comeInt(s['quantita']) ?? 1));
  int get _prezzoServizi => _servizi.fold(0, (t, s) => t + (comeInt(s['prezzoCent']) ?? 0) * (comeInt(s['quantita']) ?? 1));
  int get _durataMin => int.tryParse(_durata.text.trim()) ?? 0;

  void _ricalcola() {
    if (!_durataManuale) _durata.text = _servizi.isEmpty ? '' : '$_durataServizi';
    if (!_prezzoManuale) _prezzo.text = _servizi.isEmpty ? '' : F.testoDaCent(_prezzoServizi);
  }

  void _toggleServizio(Doc s) {
    setState(() {
      final i = _servizi.indexWhere((x) => x['servizioId'] == s['id']);
      if (i >= 0) {
        _servizi.removeAt(i);
      } else {
        _servizi.add({'servizioId': s['id'], 'nome': s['nome'], 'durata': s['durata'], 'prezzoCent': s['prezzoCent'], 'quantita': 1, 'colore': s['colore'], 'richiamoGiorni': s['richiamoGiorni']});
      }
      _durataManuale = false;
      _prezzoManuale = false;
      _ricalcola();
    });
    vibra();
  }

  void _quantita(Doc s, int delta) {
    setState(() {
      final q = ((comeInt(s['quantita']) ?? 1) + delta).clamp(1, 20);
      s['quantita'] = q;
      _durataManuale = false;
      _prezzoManuale = false;
      _ricalcola();
    });
  }

  Future<void> _salva() async {
    final d = context.dati;
    if (_clienteId == null && !_nuovaCliente) {
      avviso(context, 'Scegli la cliente o creane una nuova.', errore: true);
      return;
    }
    if (_nuovaCliente && _nNome.text.trim().isEmpty) {
      avviso(context, 'Scrivi almeno il nome della nuova cliente.', errore: true);
      return;
    }
    final durata = _durataMin;
    if (durata <= 0) {
      avviso(context, 'Indica la durata (o scegli almeno un servizio).', errore: true);
      return;
    }
    final prezzo = F.centDaTesto(_prezzo.text) ?? 0;
    final acconto = F.centDaTesto(_acconto.text) ?? 0;
    final opId = d.piuOperatrici ? _operatrice : (comeStr(d.operatrici.first['id']));
    // occorrenze (appuntamenti ripetuti)
    final occ = <DateTime>[_inizio];
    if (!_modifica && _ogniSettimane > 0) {
      for (var k = 1; k < _volte; k++) {
        occ.add(D.combina(D.aggiungiGiorniKey(D.key(_inizio), 7 * _ogniSettimane * k), D.hhmm(_inizio)));
      }
    }
    final problemi = <Problema>[];
    for (final o in occ) {
      for (final p in controllaSlot(d, inizio: o, fine: D.aggiungiMinuti(o, durata), operatriceId: opId, escludiId: comeStr(widget.app?['id']), servizi: _servizi, ignoraPassato: _modifica)) {
        problemi.add(occ.length > 1 ? Problema(p.tipo, '${F.giornoBreve(o)}: ${p.msg}') : p);
      }
    }
    if (problemi.isNotEmpty) {
      final ok = await conferma(context, titolo: 'Ci sono dei conflitti', messaggio: 'Vuoi salvare lo stesso?', problemi: problemi, ok: 'Salva comunque');
      if (!ok || !mounted) return;
    }
    setState(() => _salvando = true);
    try {
      Doc? nuovaCli;
      var cliId = _clienteId;
      if (_nuovaCliente) {
        nuovaCli = nuovaClienteVuota(nome: _nNome.text.trim(), cognome: _nCognome.text.trim(), telefono: normalizzaTelefono(_nTel.text, prefisso: d.prefisso));
        await d.salva('clienti', nuovaCli);
        cliId = comeStr(nuovaCli['id']);
      }
      final cli = d.get('clienti', cliId);
      final base = <String, dynamic>{
        'clienteId': cliId,
        'clienteNome': nomeCliente(cli),
        'servizi': clona(_servizi),
        'operatriceId': opId,
        'prezzoTotaleCent': prezzo,
        'accontoCent': acconto,
        'note': _note.text.trim(),
        'durataManuale': _durataManuale,
        'prezzoManuale': _prezzoManuale,
      };
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (_modifica) {
        final a = widget.app!;
        final prima = clonaDoc(a);
        a.addAll(base);
        a['inizio'] = isoJs(_inizio);
        a['fine'] = isoJs(D.aggiungiMinuti(_inizio, durata));
        a['stato'] = _stato;
        await d.salva('appuntamenti', a);
        nav.pop();
        avvisa('Appuntamento aggiornato', annulla: () async {
          a
            ..clear()
            ..addAll(prima);
          await d.salva('appuntamenti', a);
        });
      } else {
        final serie = occ.length > 1 ? uid() : null;
        final creati = [
          for (final o in occ) {...clona(base), 'inizio': isoJs(o), 'fine': isoJs(D.aggiungiMinuti(o, durata)), 'stato': 'prenotato', 'serieId': serie, 'schedaId': null, 'archiviato': false},
        ];
        await d.salvaMolti('appuntamenti', creati);
        nav.pop();
        vibra(true);
        avvisa(occ.length > 1 ? '${occ.length} appuntamenti creati' : 'Appuntamento fissato: ${giornoRelativo(_inizio).toLowerCase()} alle ${D.hhmm(_inizio)}', annulla: () async {
          await d.inBlocco(() async {
            await d.eliminaMolti('appuntamenti', [for (final c in creati) comeStr(c['id'])]);
            if (nuovaCli != null) await d.elimina('clienti', comeStr(nuovaCli['id']));
          });
        });
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final listino = serviziAttivi(d);
    final durata = _durataMin;
    final fine = D.aggiungiMinuti(_inizio, durata);
    final problemi = durata > 0 ? controllaSlot(d, inizio: _inizio, fine: fine, operatriceId: d.piuOperatrici ? _operatrice : null, escludiId: comeStr(widget.app?['id']), servizi: _servizi, ignoraPassato: _modifica) : <Problema>[];
    // servizi dell'appuntamento che non sono (più) nel listino
    final extra = _servizi.where((s) => !listino.any((l) => l['id'] == s['servizioId'])).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_modifica ? 'Modifica appuntamento' : 'Nuovo appuntamento'),
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Chiudi', onPressed: () => Navigator.pop(context)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: S.s),
            child: TextButton(onPressed: _salvando ? null : _salva, child: const Text('Salva')),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, 120), children: [
              // ---------------- cliente ----------------
              Text('Cliente', style: t.titleMedium),
              const SizedBox(height: S.s),
              _sceltaCliente(context),
              const SizedBox(height: S.xl),
              // ---------------- servizi ----------------
              Text('Servizi', style: t.titleMedium),
              const SizedBox(height: S.s),
              if (listino.isEmpty && extra.isEmpty)
                const Riquadro(tipo: 'info', testo: 'Non hai ancora un listino: aggiungi i servizi da Altro → Servizi. Intanto puoi indicare durata e prezzo a mano qui sotto.'),
              Wrap(spacing: S.s, runSpacing: S.s, children: [
                for (final s in listino)
                  FilterChip(
                    label: Text('${s['nome']} · ${F.durata(comeInt(s['durata']))}'),
                    selected: _servizi.any((x) => x['servizioId'] == s['id']),
                    avatar: CircleAvatar(backgroundColor: Color(coloreServizio(d, {'servizi': [{'servizioId': s['id'], 'colore': s['colore']}]})), radius: 6),
                    showCheckmark: false,
                    onSelected: (_) => _toggleServizio(s),
                  ),
                for (final s in extra)
                  InputChip(label: Text('${s['nome']}'), selected: true, onDeleted: () => setState(() {
                        _servizi.remove(s);
                        _ricalcola();
                      })),
              ]),
              if (_servizi.isNotEmpty) ...[
                const SizedBox(height: S.m),
                for (final s in _servizi)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Expanded(child: Text('${s['nome']}', style: t.bodyLarge)),
                      Text(F.euro((comeInt(s['prezzoCent']) ?? 0) * (comeInt(s['quantita']) ?? 1)), style: t.bodyMedium),
                      const SizedBox(width: S.s),
                      IconButton(onPressed: (comeInt(s['quantita']) ?? 1) > 1 ? () => _quantita(s, -1) : null, icon: const Icon(Icons.remove_circle_outline_rounded), tooltip: 'Meno'),
                      Text('×${comeInt(s['quantita']) ?? 1}', style: t.titleSmall),
                      IconButton(onPressed: () => _quantita(s, 1), icon: const Icon(Icons.add_circle_outline_rounded), tooltip: 'Più (es. nail art per unghia)'),
                    ]),
                  ),
              ],
              const SizedBox(height: S.xl),
              // ---------------- quando ----------------
              Text('Quando', style: t.titleMedium),
              const SizedBox(height: S.s),
              Row(children: [
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text(F.maiuscola(F.giornoBreve(_inizio))),
                    onPressed: () async {
                      final g = await scegliData(context, _inizio);
                      if (g != null) setState(() => _inizio = D.combina(D.key(g), D.hhmm(_inizio)));
                    },
                  ),
                ),
                const SizedBox(width: S.s),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(D.hhmm(_inizio)),
                    onPressed: () async {
                      final o = await scegliOra(context, TimeOfDay(hour: _inizio.hour, minute: _inizio.minute), passo: d.slotMinuti >= 5 ? 5 : 1);
                      if (o != null) setState(() => _inizio = D.combina(D.key(_inizio), '${D.p2(o.hour)}:${D.p2(o.minute)}'));
                    },
                  ),
                ),
              ]),
              const SizedBox(height: S.m),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Campo(
                    etichetta: 'Durata (minuti)',
                    controller: _durata,
                    tastiera: TextInputType.number,
                    aiuto: durata > 0 ? 'Fine alle ${D.hhmm(fine)}' : null,
                    suCambio: (_) => setState(() => _durataManuale = true),
                  ),
                ),
                const SizedBox(width: S.m),
                Expanded(child: Campo(etichetta: 'Prezzo (€)', controller: _prezzo, tastiera: const TextInputType.numberWithOptions(decimal: true), suCambio: (_) => _prezzoManuale = true)),
              ]),
              if (problemi.isNotEmpty) ...[
                Riquadro(tipo: 'avviso', titolo: 'Attenzione', testo: problemi.map((p) => '• ${p.msg}').join('\n')),
                const SizedBox(height: S.s),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: () => _trovaSlot(context), icon: const Icon(Icons.manage_search_rounded), label: const Text('Trova il primo spazio libero')),
              ),
              if (d.piuOperatrici) ...[
                const SizedBox(height: S.m),
                Text('Operatrice', style: t.titleMedium),
                const SizedBox(height: S.s),
                Wrap(spacing: S.s, children: [
                  for (final o in d.operatrici)
                    ChoiceChip(
                      label: Text(comeStr(o['nome']).isEmpty ? 'Operatrice' : comeStr(o['nome'])),
                      selected: _operatrice == o['id'],
                      onSelected: (_) => setState(() => _operatrice = comeStr(o['id'])),
                    ),
                ]),
              ],
              if (!_modifica) ...[
                const SizedBox(height: S.l),
                Text('Ripeti', style: t.titleMedium),
                const SizedBox(height: S.s),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  for (final (v, txt) in const [(0, 'Mai'), (1, 'Ogni settimana'), (2, 'Ogni 2 settimane'), (3, 'Ogni 3 settimane'), (4, 'Ogni 4 settimane')])
                    ChoiceChip(label: Text(txt), selected: _ogniSettimane == v, onSelected: (_) => setState(() => _ogniSettimane = v)),
                ]),
                if (_ogniSettimane > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: S.s),
                    child: Row(children: [
                      const Text('Numero di appuntamenti'),
                      const Spacer(),
                      IconButton(onPressed: _volte > 2 ? () => setState(() => _volte--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                      Text('$_volte', style: t.titleMedium),
                      IconButton(onPressed: _volte < 26 ? () => setState(() => _volte++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
                    ]),
                  ),
              ],
              const SizedBox(height: S.xl),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Campo(etichetta: 'Acconto versato (€)', controller: _acconto, tastiera: const TextInputType.numberWithOptions(decimal: true), placeholder: '0,00')),
                const SizedBox(width: S.m),
                const Expanded(child: SizedBox()),
              ]),
              Campo(etichetta: 'Note', controller: _note, righe: 3),
              if (_modifica) ...[
                Text('Stato', style: t.titleMedium),
                const SizedBox(height: S.s),
                Wrap(spacing: S.s, runSpacing: S.s, children: [
                  for (final s in const ['prenotato', 'confermato', 'completato', 'annullato', 'non_presentata'])
                    ChoiceChip(label: Text(statiAppuntamentoUi(s).$1), selected: _stato == s, onSelected: (_) => setState(() => _stato = s)),
                ]),
              ],
            ]),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        color: cs.surfaceContainerLowest,
        elevation: 8,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.m),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Row(children: [
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(F.euro(F.centDaTesto(_prezzo.text) ?? 0), style: t.titleLarge),
                      Text(durata > 0 ? '${F.giornoCorto(_inizio)} · ${F.intervallo(_inizio, fine)}' : 'Durata da indicare', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  FilledButton.icon(
                    onPressed: _salvando ? null : _salva,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(_modifica ? 'Salva' : 'Fissa appuntamento'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: S.xl)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sceltaCliente(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final cli = d.get('clienti', _clienteId);
    if (cli != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(S.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Avatar(nomeCliente(cli)),
              const SizedBox(width: S.m),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nomeCliente(cli), style: t.titleMedium),
                  if (comeStr(cli['telefono']).isNotEmpty) Text(telefonoLeggibile(comeStr(cli['telefono'])), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
              TextButton(onPressed: () => setState(() => _clienteId = null), child: const Text('Cambia')),
            ]),
            if (haAvvertenze(cli)) ...[const SizedBox(height: S.s), Avvertenze(comeStr(cli['avvertenze']))],
            if (_noteProssimaVolta(cli).isNotEmpty) ...[
              const SizedBox(height: S.s),
              Riquadro(tipo: 'info', titolo: 'Nota dall\'ultima volta', testo: _noteProssimaVolta(cli)),
            ],
          ]),
        ),
      );
    }
    if (_nuovaCliente) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(S.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Nuova cliente', style: t.titleSmall)),
              TextButton(onPressed: () => setState(() => _nuovaCliente = false), child: const Text('Cerca tra le clienti')),
            ]),
            Row(children: [
              Expanded(child: Campo(etichetta: 'Nome', controller: _nNome, maiuscole: TextCapitalization.words, autofocus: true)),
              const SizedBox(width: S.s),
              Expanded(child: Campo(etichetta: 'Cognome', controller: _nCognome, maiuscole: TextCapitalization.words)),
            ]),
            Campo(etichetta: 'Telefono / WhatsApp', controller: _nTel, tastiera: TextInputType.phone, aiuto: 'Puoi completare la scheda (preferenze, consensi) più tardi.'),
          ]),
        ),
      );
    }
    final q = norm(_cerca.text.trim());
    final qTel = _cerca.text.replaceAll(RegExp(r'\D'), '');
    final tutte = d.elenco('clienti');
    final trovate = (q.isEmpty
            ? (tutte..sort((a, b) => comeStr(b['updatedAt']).compareTo(comeStr(a['updatedAt'])))).take(5)
            : tutte.where((c) => norm('${c['nome']} ${c['cognome']} ${c['cognome']} ${c['nome']}').contains(q) || (qTel.length >= 3 && comeStr(c['telefono']).replaceAll(RegExp(r'\D'), '').contains(qTel))).take(8))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _cerca,
        decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Cerca per nome o telefono'),
        textCapitalization: TextCapitalization.words,
      ),
      const SizedBox(height: S.s),
      for (final c in trovate)
        ListTile(
          leading: Avatar(nomeCliente(c), dimensione: 36),
          title: Text(nomeCliente(c)),
          subtitle: comeStr(c['telefono']).isEmpty ? null : Text(telefonoLeggibile(comeStr(c['telefono']))),
          trailing: haAvvertenze(c) ? const Icon(Icons.warning_rounded, color: Color(0xFFB42318)) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () => setState(() {
            _clienteId = comeStr(c['id']);
            _cerca.clear();
            FocusScope.of(context).unfocus();
          }),
        ),
      ListTile(
        leading: CircleAvatar(backgroundColor: cs.primary.withValues(alpha: 0.12), child: Icon(Icons.person_add_alt_1_rounded, color: cs.primary)),
        title: Text(_cerca.text.trim().isEmpty ? 'Nuova cliente' : 'Nuova cliente: «${_cerca.text.trim()}»'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: () => setState(() {
          final testo = _cerca.text.trim();
          if (RegExp(r'^[+\d\s]+$').hasMatch(testo) && testo.isNotEmpty) {
            _nTel.text = testo;
          } else if (testo.isNotEmpty) {
            final parti = testo.split(RegExp(r'\s+'));
            _nNome.text = F.maiuscola(parti.first);
            _nCognome.text = parti.skip(1).map(F.maiuscola).join(' ');
          }
          _nuovaCliente = true;
        }),
      ),
    ]);
  }

  String _noteProssimaVolta(Doc cli) {
    final s = schedeCliente(context.dati, comeStr(cli['id']));
    return s.isEmpty ? '' : comeStr(s.first['noteProssimaVolta']);
  }

  Future<void> _trovaSlot(BuildContext context) async {
    final d = context.dati;
    final durata = _durataMin;
    final r = trovaSlotLiberi(d, durataMin: durata, operatriceId: d.piuOperatrici ? _operatrice : null, servizi: _servizi, escludiId: comeStr(widget.app?['id']), quanti: 12, da: DateTime.now().isAfter(_inizio) ? null : D.inizioGiorno(_inizio));
    if (r.errore != null) {
      avviso(context, r.errore!, errore: true);
      return;
    }
    final scelto = await showModalBottomSheet<DateTime>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.l),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Primi spazi liberi per ${F.durata(durata)}', style: Theme.of(c).textTheme.titleMedium),
            const SizedBox(height: S.m),
            if (r.slot.isEmpty) const Vuoto('Nessuno spazio libero nei prossimi 90 giorni.'),
            Wrap(spacing: S.s, runSpacing: S.s, children: [
              for (final s in r.slot) ActionChip(label: Text('${F.maiuscola(F.giornoBreve(s))} · ${D.hhmm(s)}'), onPressed: () => Navigator.pop(c, s)),
            ]),
          ]),
        ),
      ),
    );
    if (scelto != null) setState(() => _inizio = scelto);
  }
}
