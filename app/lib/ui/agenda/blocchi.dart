import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';

/// Elenco di pause, ferie, chiusure e impegni.
class PaginaBlocchi extends StatelessWidget {
  const PaginaBlocchi({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Pause, ferie e chiusure')),
      floatingActionButton: FloatingActionButton.extended(heroTag: 'blocchi-nuovo', onPressed: () => apriModuloBlocco(context), icon: const Icon(Icons.add_rounded), label: const Text('Nuovo')),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final oggi = D.oggiKey();
          final ora = adessoIso();
          final tutti = d.elenco('blocchi')
            ..sort((a, b) => comeStr(a['inizio'] ?? comeDoc(a['ricorrenza'])['dal']).compareTo(comeStr(b['inizio'] ?? comeDoc(b['ricorrenza'])['dal'])));
          bool attuale(Doc b) => b['ricorrenza'] is Map ? (comeStr(comeDoc(b['ricorrenza'])['al']).isEmpty || comeStr(comeDoc(b['ricorrenza'])['al']).compareTo(oggi) >= 0) : comeStr(b['fine']).compareTo(ora) >= 0;
          final attuali = tutti.where(attuale).toList(), passati = tutti.where((b) => !attuale(b)).toList().reversed.toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, 100), children: [
                const Riquadro(testo: 'La pausa pranzo fissa si imposta negli orari di apertura (Altro → Orari). Qui metti ferie, chiusure straordinarie, impegni o pause ricorrenti diverse.'),
                const SizedBox(height: S.l),
                Sezione(
                  titolo: 'In programma',
                  child: attuali.isEmpty
                      ? const Vuoto('Nessuna pausa o chiusura in programma.', icona: Icons.beach_access_outlined)
                      : Column(children: [for (final b in attuali) _riga(context, b)]),
                ),
                if (passati.isNotEmpty) ...[
                  const SizedBox(height: S.l),
                  Sezione(titolo: 'Passati', child: Column(children: [for (final b in passati.take(30)) _riga(context, b)])),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _riga(BuildContext context, Doc b) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(switch (comeStr(b['tipo'])) { 'ferie' => Icons.beach_access_rounded, 'chiusura' => Icons.store_mall_directory_outlined, 'pausa' => Icons.coffee_outlined, _ => Icons.event_note_outlined }),
        title: Text(descriviBlocco(b)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => apriModuloBlocco(context, blocco: b),
      );
}

Future<void> apriModuloBlocco(BuildContext context, {Doc? blocco, DateTime? giorno}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (c) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom),
      child: _ModuloBlocco(blocco: blocco, giorno: giorno ?? D.inizioGiorno(DateTime.now())),
    ),
  );
}

class _ModuloBlocco extends StatefulWidget {
  const _ModuloBlocco({this.blocco, required this.giorno});
  final Doc? blocco;
  final DateTime giorno;
  @override
  State<_ModuloBlocco> createState() => _ModuloBloccoState();
}

class _ModuloBloccoState extends State<_ModuloBlocco> {
  String _tipo = 'personale';
  final _titolo = TextEditingController();
  bool _ricorrente = false, _tuttoIlGiorno = false;
  late DateTime _dal, _al; // giorni (tutto il giorno) o istanti
  String _oraI = '13:00', _oraF = '14:00';
  Set<int> _giorniSett = {};
  String? _fineRic;

  @override
  void initState() {
    super.initState();
    final b = widget.blocco;
    final g = widget.giorno;
    _dal = D.combina(D.key(g), '13:00');
    _al = D.combina(D.key(g), '14:00');
    _giorniSett = {D.jsDay(g)};
    if (b != null) {
      _tipo = comeStr(b['tipo']).isEmpty ? 'personale' : comeStr(b['tipo']);
      _titolo.text = comeStr(b['titolo']);
      final r = b['ricorrenza'];
      if (r is Map) {
        _ricorrente = true;
        _giorniSett = (r['giorni'] as List? ?? const []).map((x) => comeInt(x) ?? 0).toSet();
        _oraI = comeStr(r['oraInizio']);
        _oraF = comeStr(r['oraFine']);
        _dal = D.daKey(comeStr(r['dal']).isEmpty ? D.oggiKey() : comeStr(r['dal']));
        _fineRic = comeStr(r['al']).isEmpty ? null : comeStr(r['al']);
      } else {
        _tuttoIlGiorno = b['tuttoIlGiorno'] == true;
        _dal = D.daIso(comeStr(b['inizio']));
        _al = D.daIso(comeStr(b['fine']));
        if (_tuttoIlGiorno) _al = D.aggiungiGiorni(_al, -1);
      }
    }
  }

  @override
  void dispose() {
    _titolo.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    final d = context.dati;
    final rec = widget.blocco != null ? clonaDoc(widget.blocco!) : <String, dynamic>{'operatriceId': null, 'archiviato': false};
    rec['tipo'] = _tipo;
    rec['titolo'] = _titolo.text.trim();
    DateTime da, a;
    if (_ricorrente) {
      if (_giorniSett.isEmpty) {
        avviso(context, 'Scegli almeno un giorno della settimana.', errore: true); return; }
      if (D.minDaHHMM(_oraF) <= D.minDaHHMM(_oraI)) {
        avviso(context, 'L\'ora di fine deve essere dopo quella di inizio.', errore: true); return; }
      rec['ricorrenza'] = {'giorni': _giorniSett.toList()..sort(), 'oraInizio': _oraI, 'oraFine': _oraF, 'dal': D.key(_dal), 'al': _fineRic};
      rec['inizio'] = null;
      rec['fine'] = null;
      rec['tuttoIlGiorno'] = false;
      da = D.inizioGiorno(_dal);
      a = _fineRic != null ? D.aggiungiGiorni(D.daKey(_fineRic!), 1) : D.aggiungiGiorni(da, 365);
    } else {
      rec['ricorrenza'] = null;
      rec['tuttoIlGiorno'] = _tuttoIlGiorno;
      if (_tuttoIlGiorno) {
        da = D.inizioGiorno(_dal);
        a = D.aggiungiGiorni(D.inizioGiorno(_al), 1);
      } else {
        da = _dal;
        a = _al;
      }
      if (!a.isAfter(da)) {
        avviso(context, 'La fine deve essere dopo l\'inizio.', errore: true); return; }
      rec['inizio'] = isoJs(da);
      rec['fine'] = isoJs(a);
    }
    // appuntamenti già fissati che cadono nel blocco
    final prova = {...rec, 'id': '__prova'};
    final apps = appuntamentiTra(d, da, a).where((x) => statiAttivi.contains(statoApp(x)) && statoApp(x) != 'completato').where((x) {
      final r = prova['ricorrenza'];
      final i = inizioApp(x), f = fineApp(x);
      if (r is Map) {
        final k = D.key(i);
        if (!_giorniSett.contains(D.jsDay(i)) || k.compareTo(comeStr(r['dal'])) < 0 || (r['al'] != null && k.compareTo(comeStr(r['al'])) > 0)) return false;
        return D.combina(k, _oraI).isBefore(f) && D.combina(k, _oraF).isAfter(i);
      }
      return da.isBefore(f) && a.isAfter(i);
    }).toList();
    if (apps.isNotEmpty) {
      final ok = await conferma(context,
          titolo: 'Ci sono appuntamenti',
          messaggio: 'In questo periodo ci sono già ${apps.length} appuntamenti:\n${apps.take(6).map((x) => '• ${F.giornoBreve(inizioApp(x))} ${D.hhmm(inizioApp(x))} — ${comeStr(x['clienteNome'])}').join('\n')}${apps.length > 6 ? '\n…' : ''}\n\nRestano in agenda: spostali o avvisa le clienti.',
          ok: 'Salva lo stesso');
      if (!ok || !mounted) return;
    }
    await d.salva('blocchi', rec);
    if (!mounted) return;
    Navigator.pop(context);
    avvisa(widget.blocco == null ? 'Salvato: ${descriviBlocco(rec)}' : 'Modifiche salvate');
  }

  Future<void> _elimina() async {
    final b = widget.blocco!;
    final d = context.dati;
    Navigator.pop(context);
    await d.archivia('blocchi', comeStr(b['id']));
    avvisa('Eliminato', annulla: () async => d.ripristina('blocchi', comeStr(b['id'])));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget bottoneData(String etichetta, DateTime v, ValueChanged<DateTime> fn, {bool ora = true}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etichetta, style: t.labelLarge),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final g = await scegliData(context, v);
                    if (g != null) fn(D.combina(D.key(g), D.hhmm(v)));
                  },
                  child: Text(F.giornoBreve(v)),
                ),
              ),
              if (ora) ...[
                const SizedBox(width: 4),
                OutlinedButton(
                  onPressed: () async {
                    final o = await scegliOra(context, TimeOfDay(hour: v.hour, minute: v.minute));
                    if (o != null) fn(D.combina(D.key(v), '${D.p2(o.hour)}:${D.p2(o.minute)}'));
                  },
                  child: Text(D.hhmm(v)),
                ),
              ],
            ]),
          ]),
        );
    Widget bottoneOra(String etichetta, String v, ValueChanged<String> fn) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etichetta, style: t.labelLarge),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final m = D.minDaHHMM(v);
                  final o = await scegliOra(context, TimeOfDay(hour: m ~/ 60, minute: m % 60));
                  if (o != null) fn('${D.p2(o.hour)}:${D.p2(o.minute)}');
                },
                child: Text(v),
              ),
            ),
          ]),
        );
    const nomi = ['Dom', 'Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab'];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.l),
      child: SafeArea(
        top: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.blocco == null ? 'Blocca un orario' : 'Pausa / chiusura', style: t.headlineSmall),
          const SizedBox(height: S.m),
          Wrap(spacing: S.s, runSpacing: S.s, children: [
            for (final e in tipiBlocco.entries) ChoiceChip(label: Text(e.value), selected: _tipo == e.key, onSelected: (_) => setState(() => _tipo = e.key)),
          ]),
          const SizedBox(height: S.m),
          Campo(etichetta: 'Descrizione (facoltativa)', controller: _titolo, placeholder: 'es. dentista, fiera, corso'),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Si ripete ogni settimana'), value: _ricorrente, onChanged: (v) => setState(() => _ricorrente = v)),
          if (_ricorrente) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final g in const [1, 2, 3, 4, 5, 6, 0])
                FilterChip(
                  label: Text(nomi[g]),
                  selected: _giorniSett.contains(g),
                  onSelected: (s) => setState(() => s ? _giorniSett.add(g) : _giorniSett.remove(g)),
                ),
            ]),
            const SizedBox(height: S.m),
            Row(children: [bottoneOra('Dalle', _oraI, (v) => setState(() => _oraI = v)), const SizedBox(width: S.s), bottoneOra('Alle', _oraF, (v) => setState(() => _oraF = v))]),
            const SizedBox(height: S.m),
            Row(children: [
              bottoneData('A partire dal', _dal, (v) => setState(() => _dal = v), ora: false),
              const SizedBox(width: S.s),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Fino al', style: t.labelLarge),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final g = await scegliData(context, _fineRic == null ? D.aggiungiGiorni(_dal, 30) : D.daKey(_fineRic!));
                          if (g != null) setState(() => _fineRic = D.key(g));
                        },
                        child: Text(_fineRic == null ? 'Sempre' : F.dataKey(_fineRic)),
                      ),
                    ),
                    if (_fineRic != null) IconButton(onPressed: () => setState(() => _fineRic = null), icon: const Icon(Icons.close_rounded), tooltip: 'Senza fine'),
                  ]),
                ]),
              ),
            ]),
          ] else ...[
            SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Tutto il giorno'), value: _tuttoIlGiorno, onChanged: (v) => setState(() => _tuttoIlGiorno = v)),
            Row(children: [
              bottoneData(_tuttoIlGiorno ? 'Dal' : 'Inizio', _dal, (v) => setState(() {
                    _dal = v;
                    if (!_al.isAfter(_dal)) _al = _tuttoIlGiorno ? _dal : D.aggiungiMinuti(_dal, 60);
                  }), ora: !_tuttoIlGiorno),
              const SizedBox(width: S.s),
              bottoneData(_tuttoIlGiorno ? 'Al (compreso)' : 'Fine', _al, (v) => setState(() => _al = v), ora: !_tuttoIlGiorno),
            ]),
          ],
          const SizedBox(height: S.xl),
          Row(children: [
            if (widget.blocco != null) TextButton.icon(onPressed: _elimina, icon: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error), label: Text('Elimina', style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
            const SizedBox(width: S.s),
            FilledButton(onPressed: _salva, child: const Text('Salva')),
          ]),
        ]),
      ),
    );
  }
}
