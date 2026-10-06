import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';
import 'azioni.dart';
import 'blocchi.dart';
import 'calendario.dart';
import 'dettaglio_appuntamento.dart';
import 'modulo_appuntamento.dart';

enum Vista { giorno, tre, settimana, mese, elenco }

extension on Vista {
  String get nome => switch (this) { Vista.giorno => 'Giorno', Vista.tre => '3 giorni', Vista.settimana => 'Settimana', Vista.mese => 'Mese', Vista.elenco => 'Elenco' };
}

class PaginaAgenda extends StatefulWidget {
  const PaginaAgenda({super.key});
  @override
  State<PaginaAgenda> createState() => _PaginaAgendaState();
}

class _PaginaAgendaState extends State<PaginaAgenda> {
  Vista? _vista;
  DateTime _giorno = D.inizioGiorno(DateTime.now());
  bool _annullati = false;
  String? _operatrice;

  @override
  void initState() {
    super.initState();
    navigazione.addListener(_daNavigazione);
    if (schermataAvvio == 'agenda-settimana') _vista = Vista.settimana;
    if (schermataAvvio == 'appuntamento') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final d = context.dati;
        final ora = DateTime.now();
        final prossimi = d.elenco('appuntamenti').where((a) => fineApp(a).isAfter(ora) && statiAttivi.contains(statoApp(a))).toList()..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
        final conAvv = prossimi.where((a) => haAvvertenze(d.get('clienti', comeStr(a['clienteId'])))).toList();
        final a = conAvv.isNotEmpty ? conAvv.first : (prossimi.isNotEmpty ? prossimi.first : null);
        if (a != null) {
          setState(() => _giorno = D.inizioGiorno(inizioApp(a)));
          apriAppuntamento(context, a);
        }
      });
    }
  }

  @override
  void dispose() {
    navigazione.removeListener(_daNavigazione);
    super.dispose();
  }

  void _daNavigazione() {
    final g = navigazione.giornoAgenda;
    if (g != null) {
      navigazione.giornoAgenda = null;
      setState(() {
        _giorno = D.inizioGiorno(g);
        if (_vista == Vista.mese) _vista = eTablet(context) ? Vista.settimana : Vista.giorno;
      });
    }
  }

  Vista _predefinita(BuildContext context) {
    final cfg = comeDoc(context.dati.cfg['agenda']);
    final v = eTablet(context) ? comeStr(cfg['vistaPredefinita']) : comeStr(cfg['vistaTelefono']);
    return switch (v) {
      'timeGridDay' => Vista.giorno,
      'timeGridWeek' => eTablet(context) ? Vista.settimana : Vista.tre,
      'dayGridMonth' => Vista.mese,
      'listWeek' => Vista.elenco,
      _ => eTablet(context) ? Vista.settimana : Vista.giorno,
    };
  }

  List<DateTime> _giorni(Vista v) => switch (v) {
        Vista.giorno => [_giorno],
        Vista.tre => [for (var i = 0; i < 3; i++) D.aggiungiGiorni(_giorno, i)],
        _ => [for (var i = 0; i < 7; i++) D.aggiungiGiorni(D.inizioSettimana(_giorno), i)],
      };

  void _sposta(Vista v, int verso) {
    vibra();
    setState(() {
      _giorno = switch (v) {
        Vista.giorno => D.aggiungiGiorni(_giorno, verso),
        Vista.tre => D.aggiungiGiorni(_giorno, 3 * verso),
        Vista.settimana || Vista.elenco => D.aggiungiGiorni(_giorno, 7 * verso),
        Vista.mese => DateTime(_giorno.year, _giorno.month + verso, 1),
      };
    });
  }

  String _titolo(Vista v) {
    switch (v) {
      case Vista.giorno:
        return giornoRelativo(_giorno) == 'Oggi' || giornoRelativo(_giorno) == 'Domani' || giornoRelativo(_giorno) == 'Ieri' ? '${giornoRelativo(_giorno)}, ${F.giornoMsg(_giorno).split(' ').skip(1).join(' ')}' : F.giornoLungo(_giorno);
      case Vista.mese:
        return F.meseAnno(_giorno);
      default:
        final g = _giorni(v);
        final a = g.first, b = g.last;
        if (a.month == b.month) return '${a.day}–${b.day} ${F.meseAnno(a).toLowerCase()}';
        return '${F.giornoBreve(a)} – ${F.giornoBreve(b)}';
    }
  }

  DateTime _inizioPredefinito() {
    final d = context.dati;
    final passo = d.slotMinuti < 5 ? 5 : d.slotMinuti;
    final ora = DateTime.now();
    if (D.stessoGiorno(_giorno, ora)) return D.arrotondaSu(ora, passo);
    final iv = intervalliGiorno(d, _giorno);
    return D.combina(D.key(_giorno), iv.isEmpty ? '09:00' : D.hhmmDaMin(iv.first[0]));
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final vista = _vista ?? _predefinita(context);
    final tablet = eTablet(context);
    final viste = tablet ? const [Vista.giorno, Vista.settimana, Vista.mese, Vista.elenco] : const [Vista.giorno, Vista.tre, Vista.settimana, Vista.mese, Vista.elenco];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: S.l,
        title: GestureDetector(
          onTap: () async {
            final g = await scegliData(context, _giorno);
            if (g != null) setState(() => _giorno = D.inizioGiorno(g));
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(F.maiuscola(_titolo(vista)), overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down_rounded),
          ]),
        ),
        actions: [
          IconButton(tooltip: 'Indietro', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _sposta(vista, -1)),
          TextButton(onPressed: () => setState(() => _giorno = D.inizioGiorno(DateTime.now())), child: const Text('Oggi')),
          IconButton(tooltip: 'Avanti', icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _sposta(vista, 1)),
          if (tablet)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.s),
              child: SegmentedButton<Vista>(
                showSelectedIcon: false,
                segments: [for (final v in viste) ButtonSegment(value: v, label: Text(v.nome))],
                selected: {vista},
                onSelectionChanged: (s) => setState(() => _vista = s.first),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'Altre opzioni',
            onSelected: (v) async {
              switch (v) {
                case 'annullati':
                  setState(() => _annullati = !_annullati);
                case 'blocchi':
                  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PaginaBlocchi()));
                case 'blocco':
                  await apriModuloBlocco(context, giorno: _giorno);
                default:
                  if (v.startsWith('vista:')) setState(() => _vista = Vista.values.byName(v.substring(6)));
              }
            },
            itemBuilder: (c) => [
              if (!tablet)
                for (final v in viste) CheckedPopupMenuItem(value: 'vista:${v.name}', checked: v == vista, child: Text(v.nome)),
              if (!tablet) const PopupMenuDivider(),
              CheckedPopupMenuItem(value: 'annullati', checked: _annullati, child: const Text('Mostra annullati')),
              const PopupMenuItem(value: 'blocco', child: ListTile(leading: Icon(Icons.block_rounded), title: Text('Blocca un orario'), contentPadding: EdgeInsets.zero)),
              const PopupMenuItem(value: 'blocchi', child: ListTile(leading: Icon(Icons.beach_access_outlined), title: Text('Pause, ferie e chiusure'), contentPadding: EdgeInsets.zero)),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'agenda-nuovo',
        onPressed: () => apriModuloAppuntamento(context, inizio: _inizioPredefinito()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Appuntamento'),
      ),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          return Column(children: [
            if (d.cfg['orari'] is! Map)
              Padding(
                padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.s),
                child: Riquadro(
                  tipo: 'avviso',
                  testo: 'Imposta gli orari di apertura per vedere chiusure e pause e ricevere gli avvisi "fuori orario".',
                  azioni: [OutlinedButton(onPressed: () => navigazione.vai(3), child: const Text('Vai alle impostazioni'))],
                ),
              ),
            if (d.piuOperatrici)
              SizedBox(
                height: 48,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: S.l), children: [
                  Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(label: const Text('Tutte'), selected: _operatrice == null, onSelected: (_) => setState(() => _operatrice = null))),
                  for (final o in d.operatrici)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        avatar: CircleAvatar(radius: 6, backgroundColor: Color(coloreDaHexSicuro(o['colore']))),
                        label: Text(comeStr(o['nome']).isEmpty ? 'Operatrice' : comeStr(o['nome'])),
                        selected: _operatrice == o['id'],
                        onSelected: (_) => setState(() => _operatrice = comeStr(o['id'])),
                      ),
                    ),
                ]),
              ),
            if (vista == Vista.giorno && !tablet) _StrisciaSettimana(giorno: _giorno, suScelta: (g) => setState(() => _giorno = g)),
            Expanded(
              child: GestureDetector(
                onHorizontalDragEnd: (det) {
                  final v = det.primaryVelocity ?? 0;
                  if (v.abs() > 350) _sposta(vista, v < 0 ? 1 : -1);
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey('${vista.name}-${D.key(vista == Vista.mese ? DateTime(_giorno.year, _giorno.month) : _giorni(vista).first)}'),
                    child: switch (vista) {
                      Vista.mese => _Mese(mese: _giorno, operatrice: _operatrice, annullati: _annullati, suGiorno: (g) => setState(() {
                            _giorno = g;
                            _vista = tablet ? Vista.settimana : Vista.giorno;
                          })),
                      Vista.elenco => _Elenco(giorni: _giorni(vista), operatrice: _operatrice, annullati: _annullati),
                      _ => Calendario(
                          dati: d,
                          giorni: _giorni(vista),
                          mostraAnnullati: _annullati,
                          operatrice: _operatrice,
                          suTocco: (inizio) => apriModuloAppuntamento(context, inizio: inizio),
                          suApri: (a) => apriAppuntamento(context, a),
                          suSposta: (a, i, f) => spostaAppuntamento(context, a, i, f),
                          suTockoBlocco: (b) => apriModuloBlocco(context, blocco: b),
                        ),
                    },
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

int coloreDaHexSicuro(dynamic hex) {
  final s = comeStr(hex).replaceAll('#', '');
  return s.length == 6 ? 0xFF000000 | (int.tryParse(s, radix: 16) ?? 0xB4646E) : 0xFFB4646E;
}

/// Striscia dei giorni della settimana (telefono, vista giorno).
class _StrisciaSettimana extends StatelessWidget {
  const _StrisciaSettimana({required this.giorno, required this.suScelta});
  final DateTime giorno;
  final ValueChanged<DateTime> suScelta;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final lun = D.inizioSettimana(giorno);
    final oggi = D.inizioGiorno(DateTime.now());
    final giorni = [for (var i = 0; i < 7; i++) D.aggiungiGiorni(lun, i)];
    final conteggi = {for (final g in giorni) D.key(g): appuntamentiTra(d, g, D.aggiungiGiorni(g, 1)).where((a) => statiAttivi.contains(statoApp(a))).length};
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.s, 0, S.s, S.s),
      child: Row(children: [
        for (final g in giorni)
          Expanded(
            child: GestureDetector(
              onTap: () {
                vibra();
                suScelta(g);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: D.stessoGiorno(g, giorno) ? cs.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Text(D.giorniNome[D.giornoKey(g)]!.substring(0, 3), style: t.labelSmall?.copyWith(color: D.stessoGiorno(g, giorno) ? cs.onPrimary : cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text('${g.day}',
                      style: t.titleMedium?.copyWith(
                        color: D.stessoGiorno(g, giorno) ? cs.onPrimary : (D.stessoGiorno(g, oggi) ? cs.primary : cs.onSurface),
                        fontWeight: D.stessoGiorno(g, oggi) ? FontWeight.w800 : FontWeight.w600,
                      )),
                  const SizedBox(height: 2),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < math.min(3, conteggi[D.key(g)] ?? 0); i++)
                      Container(width: 4, height: 4, margin: const EdgeInsets.symmetric(horizontal: 1), decoration: BoxDecoration(shape: BoxShape.circle, color: D.stessoGiorno(g, giorno) ? cs.onPrimary : cs.primary)),
                    if ((conteggi[D.key(g)] ?? 0) == 0) const SizedBox(height: 4),
                  ]),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Vista mese: griglia con i pallini (telefono) o le prime righe (tablet).
class _Mese extends StatelessWidget {
  const _Mese({required this.mese, required this.suGiorno, this.operatrice, required this.annullati});
  final DateTime mese;
  final ValueChanged<DateTime> suGiorno;
  final String? operatrice;
  final bool annullati;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final primo = DateTime(mese.year, mese.month, 1);
    final inizio = D.inizioSettimana(primo);
    final oggi = D.inizioGiorno(DateTime.now());
    final fine = D.aggiungiGiorni(inizio, 42);
    final apps = appuntamentiTra(d, inizio, fine).where((a) {
      if (!annullati && statoApp(a) == 'annullato') return false;
      if (operatrice != null && comeStr(a['operatriceId']).isNotEmpty && a['operatriceId'] != operatrice) return false;
      return true;
    }).toList()
      ..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
    final perGiorno = <String, List<Doc>>{};
    for (final a in apps) {
      perGiorno.putIfAbsent(D.key(inizioApp(a)), () => []).add(a);
    }
    final tablet = eTablet(context);
    final settimane = D.aggiungiGiorni(inizio, 35).month == mese.month ? 6 : 5;
    return Column(children: [
      Row(children: [
        for (final k in D.giorniKey)
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(D.giorniNome[k]!.substring(0, 3), textAlign: TextAlign.center, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)))),
      ]),
      Expanded(
        child: Column(children: [
          for (var w = 0; w < settimane; w++)
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < 7; i++)
                  Builder(builder: (context) {
                    final g = D.aggiungiGiorni(inizio, w * 7 + i);
                    final lista = perGiorno[D.key(g)] ?? const <Doc>[];
                    final fuori = g.month != mese.month;
                    final chiuso = d.cfg['orari'] is Map && intervalliGiorno(d, g).isEmpty;
                    return Expanded(
                      child: InkWell(
                        onTap: () => suGiorno(g),
                        child: Container(
                          decoration: BoxDecoration(
                            color: chiuso ? cs.onSurface.withValues(alpha: 0.035) : null,
                            border: Border(top: BorderSide(color: cs.outlineVariant), left: i > 0 ? BorderSide(color: cs.outlineVariant) : BorderSide.none),
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: D.stessoGiorno(g, oggi) ? BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(99)) : null,
                              child: Text('${g.day}', style: t.labelLarge?.copyWith(color: D.stessoGiorno(g, oggi) ? cs.onPrimary : (fuori ? cs.outline : cs.onSurface))),
                            ),
                            const SizedBox(height: 2),
                            if (tablet)
                              Expanded(
                                child: ClipRect(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                    for (final a in lista.take(4))
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(color: Color(coloreApp(d, a)).withValues(alpha: 0.16), borderRadius: BorderRadius.circular(4)),
                                        child: Text('${D.hhmm(inizioApp(a))} ${nomeCliente(d.get('clienti', comeStr(a['clienteId']))).isEmpty ? comeStr(a['clienteNome']) : nomeCliente(d.get('clienti', comeStr(a['clienteId'])))}', maxLines: 1, overflow: TextOverflow.clip, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                      ),
                                    if (lista.length > 4) Text('+${lista.length - 4}', style: t.labelSmall),
                                  ]),
                                ),
                              )
                            else if (lista.isNotEmpty)
                              Wrap(spacing: 2, runSpacing: 2, children: [
                                for (final a in lista.take(6)) Container(width: 6, height: 6, decoration: BoxDecoration(color: Color(coloreApp(d, a)), shape: BoxShape.circle)),
                              ]),
                          ]),
                        ),
                      ),
                    );
                  }),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// Vista elenco della settimana, raggruppata per giorno.
class _Elenco extends StatelessWidget {
  const _Elenco({required this.giorni, this.operatrice, required this.annullati});
  final List<DateTime> giorni;
  final String? operatrice;
  final bool annullati;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final righe = <Widget>[];
    for (final g in giorni) {
      final lista = appuntamentiTra(d, g, D.aggiungiGiorni(g, 1)).where((a) {
        if (!annullati && statoApp(a) == 'annullato') return false;
        if (operatrice != null && comeStr(a['operatriceId']).isNotEmpty && a['operatriceId'] != operatrice) return false;
        return true;
      }).toList()
        ..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
      final blocchi = istanzeBlocchi(d, g, D.aggiungiGiorni(g, 1));
      if (lista.isEmpty && blocchi.isEmpty) continue;
      final incasso = lista.where((a) => statiAttivi.contains(statoApp(a))).fold(0, (s, a) => s + (comeInt(a['prezzoTotaleCent']) ?? 0));
      righe.add(Padding(
        padding: const EdgeInsets.fromLTRB(S.l, S.l, S.l, S.xs),
        child: Row(children: [
          Expanded(child: Text(F.maiuscola(giornoRelativo(g) == F.giornoLungo(g) ? F.giornoLungo(g) : '${giornoRelativo(g)} · ${F.giornoMsg(g)}'), style: t.titleSmall?.copyWith(color: cs.primary))),
          if (incasso > 0) Text(F.euro(incasso), style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ));
      for (final b in blocchi) {
        righe.add(ListTile(
          dense: true,
          leading: const Icon(Icons.block_rounded),
          title: Text(descriviBlocco(b.blocco)),
          subtitle: Text(F.intervallo(b.inizio, b.fine)),
          onTap: () => apriModuloBlocco(context, blocco: b.blocco),
        ));
      }
      for (final a in lista) {
        righe.add(Padding(padding: const EdgeInsets.symmetric(horizontal: S.m), child: RigaAppuntamento(app: a, suTocco: () => apriAppuntamento(context, a))));
      }
    }
    if (righe.isEmpty) return const Vuoto('Nessun appuntamento in questa settimana.', icona: Icons.event_available_outlined);
    return ListView(padding: const EdgeInsets.only(bottom: 100), children: righe);
  }
}
