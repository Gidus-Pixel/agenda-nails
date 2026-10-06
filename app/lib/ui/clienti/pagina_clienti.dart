import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../agenda/modulo_appuntamento.dart';
import '../app.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../tema.dart';
import 'modulo_cliente.dart';
import 'scheda_cliente.dart';

enum _Filtro { tutte, ricontattare, archiviate }

class PaginaClienti extends StatefulWidget {
  const PaginaClienti({super.key});
  @override
  State<PaginaClienti> createState() => _PaginaClientiState();
}

class _PaginaClientiState extends State<PaginaClienti> {
  final _cerca = TextEditingController();
  _Filtro _filtro = _Filtro.tutte;
  String? _tag;
  bool _perUltimaVisita = false;
  String? _scelta; // tablet: cliente mostrata a destra

  @override
  void initState() {
    super.initState();
    _cerca.addListener(() => setState(() {}));
    if (schermataAvvio == 'cliente') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final d = context.dati;
        final cl = d.elenco('clienti');
        final c = cl.where(haAvvertenze).firstOrNull ?? cl.firstOrNull;
        if (c == null) return;
        if (eLargo(context)) {
          setState(() => _scelta = comeStr(c['id']));
        } else {
          apriSchedaCliente(context, comeStr(c['id']));
        }
      });
    }
  }

  @override
  void dispose() {
    _cerca.dispose();
    super.dispose();
  }

  Future<void> _nuova() async {
    final id = await apriModuloCliente(context);
    if (id != null && mounted) {
      if (eLargo(context)) {
        setState(() => _scelta = id);
      } else {
        await apriSchedaCliente(context, id);
      }
    }
  }

  void _apri(String id) {
    if (eLargo(context)) {
      setState(() => _scelta = id);
    } else {
      apriSchedaCliente(context, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final largo = eLargo(context);
    final elenco = Scaffold(
      appBar: AppBar(
        title: const Text('Clienti'),
        actions: [
          IconButton(
            tooltip: _perUltimaVisita ? 'Ordina per nome' : 'Ordina per ultima visita',
            icon: Icon(_perUltimaVisita ? Icons.sort_by_alpha_rounded : Icons.history_rounded),
            onPressed: () => setState(() => _perUltimaVisita = !_perUltimaVisita),
          ),
        ],
      ),
      floatingActionButton: largo ? null : FloatingActionButton.extended(heroTag: 'clienti-nuova', onPressed: _nuova, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Nuova')),
      body: ListenableBuilder(listenable: d, builder: (context, _) => _contenuto(context)),
    );
    if (!largo) return elenco;
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      SizedBox(
        width: 380,
        child: Scaffold(
          floatingActionButton: FloatingActionButton.extended(heroTag: 'clienti-nuova', onPressed: _nuova, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Nuova')),
          body: elenco,
        ),
      ),
      VerticalDivider(width: 1, color: cs.outlineVariant),
      Expanded(
        child: _scelta == null
            ? const Scaffold(body: Center(child: Vuoto('Scegli una cliente dall\'elenco.', icona: Icons.person_search_outlined)))
            : SchedaCliente(key: ValueKey(_scelta), id: _scelta!, incorporata: true),
      ),
    ]);
  }

  Widget _contenuto(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final ricontattare = clientiDaRicontattare(d);
    final testa = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
        child: TextField(
          controller: _cerca,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: 'Cerca nome, cognome o telefono',
            suffixIcon: _cerca.text.isEmpty ? null : IconButton(onPressed: _cerca.clear, icon: const Icon(Icons.close_rounded), tooltip: 'Cancella'),
          ),
          textCapitalization: TextCapitalization.words,
        ),
      ),
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.l), children: [
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Tutte'), selected: _filtro == _Filtro.tutte && _tag == null, onSelected: (_) => setState(() {
                _filtro = _Filtro.tutte;
                _tag = null;
              }))),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('Da ricontattare${ricontattare.isEmpty ? '' : ' (${ricontattare.length})'}'),
              selected: _filtro == _Filtro.ricontattare,
              onSelected: (_) => setState(() {
                _filtro = _Filtro.ricontattare;
                _tag = null;
              }),
            ),
          ),
          for (final tg in {for (final c in d.elenco('clienti')) ...comeListaStr(c['tag'])}.toList()..sort())
            Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: Text('#$tg'), selected: _tag == tg, onSelected: (s) => setState(() {
                  _filtro = _Filtro.tutte;
                  _tag = s ? tg : null;
                }))),
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Archiviate'), selected: _filtro == _Filtro.archiviate, onSelected: (_) => setState(() {
                _filtro = _Filtro.archiviate;
                _tag = null;
              }))),
        ]),
      ),
    ];

    if (_filtro == _Filtro.ricontattare) {
      return ListView(padding: const EdgeInsets.only(bottom: 100), children: [
        ...testa,
        Padding(
          padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.s),
          child: Text('Clienti per cui è passato l\'intervallo di richiamo del loro ultimo servizio (es. refill) e senza appuntamenti in programma.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        if (ricontattare.isEmpty) const Vuoto('Nessuna cliente da ricontattare. 👏', icona: Icons.mark_chat_read_outlined),
        for (final r in ricontattare) RigaRichiamo(r: r, suApri: () => _apri(comeStr(r.cliente['id']))),
      ]);
    }

    final q = norm(_cerca.text.trim());
    final qTel = _cerca.text.replaceAll(RegExp(r'\D'), '');
    var lista = (_filtro == _Filtro.archiviate ? d.elenco('clienti', archiviati: true).where((c) => c['archiviato'] == true) : d.elenco('clienti')).where((c) {
      if (_tag != null && !comeListaStr(c['tag']).contains(_tag)) return false;
      if (q.isEmpty) return true;
      return norm('${c['nome']} ${c['cognome']} ${c['cognome']} ${c['nome']}').contains(q) || (qTel.length >= 3 && comeStr(c['telefono']).replaceAll(RegExp(r'\D'), '').contains(qTel));
    }).toList();
    final ultime = <String, String>{};
    for (final v in tutteLeVisite(d)) {
      final k = v.clienteId ?? '';
      if ((ultime[k] ?? '').compareTo(v.data) < 0) ultime[k] = v.data;
    }
    if (_perUltimaVisita) {
      lista.sort((a, b) => (ultime[b['id']] ?? '').compareTo(ultime[a['id']] ?? ''));
    } else {
      lista.sort((a, b) => norm(nomeCliente(a)).compareTo(norm(nomeCliente(b))));
    }
    if (lista.isEmpty) {
      return ListView(children: [
        ...testa,
        Vuoto(d.conta('clienti') == 0 && _filtro == _Filtro.tutte ? 'Ancora nessuna cliente. Tocca "Nuova" per aggiungere la prima, oppure crea la cliente direttamente quando fissi un appuntamento.' : 'Nessuna cliente trovata.', icona: Icons.people_outline_rounded),
      ]);
    }
    // intestazioni alfabetiche (ordine per nome)
    final righe = <Widget>[...testa];
    String? lettera;
    for (final c in lista) {
      if (!_perUltimaVisita) {
        final n = norm(nomeCliente(c));
        final l = n.isEmpty ? '#' : n[0].toUpperCase();
        if (l != lettera) {
          lettera = l;
          righe.add(Padding(padding: const EdgeInsets.fromLTRB(S.l + 4, S.m, S.l, 2), child: Text(l, style: t.labelLarge?.copyWith(color: cs.primary))));
        }
      }
      final ult = ultime[c['id']];
      righe.add(ListTile(
        selected: _scelta == c['id'] && eLargo(context),
        selectedTileColor: cs.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Avatar(nomeCliente(c)),
        title: Row(children: [
          Flexible(child: Text(nomeCliente(c), maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (haAvvertenze(c)) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.warning_rounded, size: 18, color: Color(0xFFB42318))),
        ]),
        subtitle: Text([if (comeStr(c['telefono']).isNotEmpty) telefonoLeggibile(comeStr(c['telefono'])), if (ult != null) 'ultima visita ${F.dataKey(ult)}'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: () => _apri(comeStr(c['id'])),
      ));
    }
    righe.add(Padding(padding: const EdgeInsets.all(S.l), child: Text('${lista.length} ${lista.length == 1 ? 'cliente' : 'clienti'}', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant))));
    righe.add(const SizedBox(height: 80));
    return ListView(padding: const EdgeInsets.symmetric(horizontal: 4), children: righe);
  }
}

/// Riga "da ricontattare" con messaggio WhatsApp precompilato e nuovo appuntamento.
class RigaRichiamo extends StatelessWidget {
  const RigaRichiamo({super.key, required this.r, required this.suApri});
  final Richiamo r;
  final VoidCallback suApri;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final c = r.cliente;
    final tel = comeStr(c['telefono']);
    final msg = compilaModello(comeStr(comeDoc(d.cfg['messaggi'])['richiamo']), {...valoriMessaggio(d, c, null), 'servizio': r.servizi});
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.s),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Avatar(nomeCliente(c)),
        title: Text(nomeCliente(c)),
        subtitle: Text('${r.servizi} · ultima visita ${F.dataKey(r.ultimaVisita)}${r.ritardo > 0 ? ' · da ${r.ritardo} gg' : ' · da oggi'}', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        onTap: suApri,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: 'Scrivi su WhatsApp', onPressed: tel.isEmpty ? null : () => apriLink(context, linkWhatsApp(tel, msg, prefisso: d.prefisso)), icon: const Icon(Icons.chat_rounded)),
          IconButton(tooltip: 'Fissa appuntamento', onPressed: () => apriModuloAppuntamento(context, clienteId: comeStr(c['id'])), icon: const Icon(Icons.event_available_rounded)),
        ]),
      ),
    );
  }
}
