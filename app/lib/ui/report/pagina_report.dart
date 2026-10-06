import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../dominio/magazzino.dart';
import '../../dominio/report.dart';
import '../app.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../tema.dart';

/// Report: incassi, servizi più richiesti, non presentate, consumi, vendite, spesa fornitori. CSV per Excel.
class PaginaReport extends StatefulWidget {
  const PaginaReport({super.key});
  @override
  State<PaginaReport> createState() => _PaginaReportState();
}

class _PaginaReportState extends State<PaginaReport> {
  String _preset = 'mese';
  String? _da, _a, _gruppo;

  Future<void> _csv(BuildContext context, Report r, String quale) async {
    final tab = tabellaCsv(r, quale);
    await condividiFile(context, creaCsv(tab.intestazioni, tab.righe), '$quale-${r.da}_${r.a}.csv', tipo: 'text/csv');
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          final t = Theme.of(context).textTheme;
          final cs = Theme.of(context).colorScheme;
          final (da, a) = periodoReport(_preset, da: _da, a: _a);
          final r = calcolaReport(d, da, a, gruppo: _gruppo);
          final mag = d.moduloAttivo('magazzino'), ord = d.moduloAttivo('ordini');
          final largo = MediaQuery.sizeOf(context).width >= 900;

          Widget csv(String q) => IconButton(tooltip: 'Esporta CSV per Excel', onPressed: () => _csv(context, r, q), icon: const Icon(Icons.ios_share_rounded));
          Widget tabella(List<String> h, List<List<String>> righe) => Column(children: [
                Row(children: [for (var i = 0; i < h.length; i++) Expanded(flex: i == 0 ? 3 : 2, child: Text(h[i], textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)))]),
                const Divider(),
                if (righe.isEmpty) Padding(padding: const EdgeInsets.all(S.s), child: Text('Nessun dato nel periodo', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
                for (final riga in righe)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(children: [for (var i = 0; i < riga.length; i++) Expanded(flex: i == 0 ? 3 : 2, child: Text(riga[i], textAlign: i == 0 ? TextAlign.left : TextAlign.right, style: t.bodyMedium))]),
                  ),
              ]);

          final schede = <Widget>[
            Sezione(
              titolo: 'Servizi più richiesti',
              azione: csv('servizi'),
              child: Column(children: [
                if (r.servizi.isNotEmpty) BarreOrizzontali(dati: [for (final s in r.servizi.take(8)) (s.nome, s.n.toDouble())], formato: (v) => '${v.round()}×'),
                const SizedBox(height: S.s),
                tabella(['Servizio', 'Volte', 'A listino'], [for (final s in r.servizi) [s.nome, '${s.n}', F.euro(s.cent)]]),
              ]),
            ),
            Sezione(
              titolo: 'Appuntamenti',
              azione: csv('appuntamenti'),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                tabella(['Esito', 'Numero'], [
                  ['Completati', '${r.completati}'],
                  ['Non presentata', '${r.noShow}'],
                  ['Annullati', '${r.annullati}'],
                  ['Ancora da svolgere', '${r.daSvolgere}'],
                  ['Tasso di non presentazione', percentuale(r.tassoNoShow)],
                ]),
                Text('Tasso = non presentate ÷ (completati + non presentate).', style: t.bodySmall),
              ]),
            ),
            if (mag) Sezione(titolo: 'Consumo prodotti', azione: csv('consumi'), child: tabella(['Prodotto', 'Quantità', 'A costo'], [for (final x in r.consumi) [x.nome, fmtQta(x.q, x.unita), F.euro(x.cent)]])),
            if (mag) Sezione(titolo: 'Vendita prodotti', azione: csv('vendite'), child: tabella(['Prodotto', 'Quantità', 'Incasso'], [for (final x in r.vendite) [x.nome, fmtQta(x.q, x.unita), F.euro(x.cent)]])),
            if (ord)
              Sezione(
                titolo: 'Spesa per fornitore',
                azione: csv('fornitori'),
                child: Column(children: [
                  if (r.spesa.isNotEmpty) BarreOrizzontali(dati: [for (final x in r.spesa) (x.nome, x.cent.toDouble())], formato: (v) => F.euro(v.round())),
                  const SizedBox(height: S.s),
                  tabella(['Fornitore', 'Ordini', 'Spesa'], [for (final x in r.spesa) [x.nome, '${x.n}', F.euro(x.cent)]]),
                ]),
              ),
          ];

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
                SizedBox(
                  height: 46,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final e in presetReport.entries.where((e) => e.key != 'pers'))
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(label: Text(e.value), selected: _preset == e.key, onSelected: (_) => setState(() => _preset = e.key)),
                      ),
                  ]),
                ),
                const SizedBox(height: S.s),
                Wrap(spacing: S.s, runSpacing: S.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text('Dal ${F.dataKey(da)}'),
                    onPressed: () async {
                      final g = await scegliData(context, D.daKey(da));
                      if (g != null) {
                        setState(() {
                          _preset = 'pers';
                          _da = D.key(g);
                          _a = (_a ?? a).compareTo(_da!) < 0 ? _da : (_a ?? a);
                        });
                      }
                    },
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded),
                    label: Text('al ${F.dataKey(a)}'),
                    onPressed: () async {
                      final g = await scegliData(context, D.daKey(a));
                      if (g != null) {
                        setState(() {
                          _preset = 'pers';
                          _a = D.key(g);
                          _da = (_da ?? da).compareTo(_a!) > 0 ? _a : (_da ?? da);
                        });
                      }
                    },
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Raggruppa',
                    onSelected: (v) => setState(() => _gruppo = v.isEmpty ? null : v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: '', child: Text('Automatico')),
                      PopupMenuItem(value: 'giorno', child: Text('Per giorno')),
                      PopupMenuItem(value: 'settimana', child: Text('Per settimana')),
                      PopupMenuItem(value: 'mese', child: Text('Per mese')),
                    ],
                    child: Chip(avatar: const Icon(Icons.bar_chart_rounded, size: 18), label: Text('Per ${r.gruppo}')),
                  ),
                ]),
                const SizedBox(height: S.l),
                GrigliaTessere(colonne: largo ? 4 : 2, children: [
                  Tessera(valore: F.euro(r.totServizi + r.totVendite), etichetta: 'incasso totale'),
                  Tessera(valore: F.euro(r.totServizi), etichetta: 'servizi (${r.visite} visite)'),
                  Tessera(valore: r.visite == 0 ? '—' : F.euro(r.mediaVisita), etichetta: 'media per visita'),
                  Tessera(valore: percentuale(r.tassoNoShow), etichetta: 'non presentate (${r.noShow} su ${r.completati + r.noShow})'),
                  if (mag) Tessera(valore: F.euro(r.totVendite), etichetta: 'vendita prodotti'),
                  if (mag) Tessera(valore: F.euro(r.totConsumi), etichetta: 'prodotti consumati (a costo)'),
                  if (ord) Tessera(valore: F.euro(r.totSpesa), etichetta: 'spesa fornitori'),
                ]),
                const SizedBox(height: S.l),
                Sezione(
                  titolo: 'Incassi per ${r.gruppo}',
                  azione: csv('incassi'),
                  child: GraficoBarre(dati: [for (final k in r.chiavi) (etichettaBreve(k, r.gruppo), etichettaGruppo(k, r.gruppo), r.perGruppo[k]!.totale.toDouble())], formato: (v) => F.euro(v.round())),
                ),
                const SizedBox(height: S.l),
                if (largo)
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (var c = 0; c < 2; c++) ...[
                      if (c > 0) const SizedBox(width: S.l),
                      Expanded(child: Column(children: [for (var i = c; i < schede.length; i += 2) Padding(padding: const EdgeInsets.only(bottom: S.l), child: schede[i])])),
                    ],
                  ])
                else
                  for (final s in schede) Padding(padding: const EdgeInsets.only(bottom: S.l), child: s),
                const SizedBox(height: S.l),
                Text('Gli incassi dei servizi sono gli importi delle schede lavoro (o il prezzo degli appuntamenti completati senza scheda). Il report è uno strumento interno e non sostituisce la contabilità.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Grafico a barre verticali: tocca una barra per vederne il valore.
class GraficoBarre extends StatefulWidget {
  const GraficoBarre({super.key, required this.dati, required this.formato});
  final List<(String breve, String etichetta, double valore)> dati;
  final String Function(double) formato;
  @override
  State<GraficoBarre> createState() => _GraficoBarreState();
}

class _GraficoBarreState extends State<GraficoBarre> {
  int? _scelto;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final dati = widget.dati;
    final max = dati.fold<double>(1, (m, x) => math.max(m, x.$3));
    final ogni = dati.length <= 12 ? 1 : (dati.length / 8).ceil();
    final sel = _scelto != null && _scelto! < dati.length ? dati[_scelto!] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 22,
        child: Text(sel == null ? 'Tocca una barra per il dettaglio' : '${sel.$2}: ${widget.formato(sel.$3)}', style: sel == null ? t.bodySmall?.copyWith(color: cs.onSurfaceVariant) : t.titleSmall),
      ),
      SizedBox(
        height: 180,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < dati.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _scelto = i),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.symmetric(horizontal: dati.length > 20 ? 1 : 3),
                    height: dati[i].$3 <= 0 ? 0 : math.max(3, 176 * dati[i].$3 / max),
                    decoration: BoxDecoration(color: _scelto == i ? cs.primary : cs.primary.withValues(alpha: 0.55), borderRadius: const BorderRadius.vertical(top: Radius.circular(5))),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const Divider(height: 1),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < dati.length; i++)
          Expanded(child: Text(i % ogni == 0 ? dati[i].$1 : '', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.visible, softWrap: false, style: t.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
      ]),
    ]);
  }
}

/// Barre orizzontali con nome e valore.
class BarreOrizzontali extends StatelessWidget {
  const BarreOrizzontali({super.key, required this.dati, required this.formato});
  final List<(String, double)> dati;
  final String Function(double) formato;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final max = dati.fold<double>(1, (m, x) => math.max(m, x.$2));
    return Column(children: [
      for (final (nome, v) in dati)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(width: 120, child: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium)),
            Expanded(
              child: LayoutBuilder(
                builder: (c, k) => Align(
                  alignment: Alignment.centerLeft,
                  child: Container(height: 12, width: math.max(4, k.maxWidth * v / max), decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(6))),
                ),
              ),
            ),
            const SizedBox(width: S.s),
            Text(formato(v), style: t.labelLarge),
          ]),
        ),
    ]);
  }
}
