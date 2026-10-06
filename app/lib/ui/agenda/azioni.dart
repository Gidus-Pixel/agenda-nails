import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dati/dati.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../tema.dart';

/// Testo breve per data e ora di un appuntamento ("Oggi, 9:00–10:30").
String quandoApp(Doc a) {
  final i = inizioApp(a), f = fineApp(a);
  return '${giornoRelativo(i)}, ${F.intervallo(i, f)}';
}

/// Sposta (o ridimensiona) un appuntamento: controlla i conflitti, chiede conferma, offre Annulla.
/// Per le serie ripetute chiede se spostare anche gli appuntamenti successivi.
Future<bool> spostaAppuntamento(BuildContext context, Doc app, DateTime inizio, DateTime fine) async {
  final d = context.dati;
  final vI = inizioApp(app), vF = fineApp(app);
  if (vI == inizio && vF == fine) return false;
  final cambiaDurata = D.minutiTra(vI, vF) != D.minutiTra(inizio, fine);
  final soloDurata = cambiaDurata && vI == inizio;

  // serie: questo o anche i successivi?
  var voci = <Doc>[app];
  final serie = comeStr(app['serieId']);
  if (serie.isNotEmpty && !soloDurata) {
    final succ = d.elenco('appuntamenti').where((x) => x['serieId'] == serie && x['id'] != app['id'] && comeStr(x['inizio']).compareTo(comeStr(app['inizio'])) > 0 && statiAttivi.contains(statoApp(x)) && statoApp(x) != 'completato').toList();
    if (succ.isNotEmpty) {
      final s = await sceltaTra(context, titolo: 'Appuntamento ripetuto', messaggio: 'Fa parte di una serie. Vuoi spostare anche i ${succ.length} appuntamenti successivi dello stesso intervallo?', opzioni: [
        ('solo', 'Solo questo', false),
        ('tutti', 'Anche i successivi', true),
      ]);
      if (s == null || !context.mounted) return false;
      if (s == 'tutti') voci = [app, ...succ];
    }
  }
  // spostamento "locale" (giorni + minuti), corretto anche nei giorni del cambio dell'ora
  final dg = D.diffGiorni(D.key(vI), D.key(inizio));
  final dm = D.minutiDelGiorno(inizio) - D.minutiDelGiorno(vI);
  final durNuova = D.minutiTra(inizio, fine);
  final nuovi = <String, ({DateTime i, DateTime f})>{};
  for (final v in voci) {
    if (identical(v, app)) {
      nuovi[comeStr(v['id'])] = (i: inizio, f: fine);
    } else {
      final ii = inizioApp(v);
      final ni = D.combina(D.aggiungiGiorniKey(D.key(ii), dg), D.hhmmDaMin((D.minutiDelGiorno(ii) + dm).clamp(0, 1439)));
      nuovi[comeStr(v['id'])] = (i: ni, f: D.aggiungiMinuti(ni, cambiaDurata ? durNuova : durataApp(v)));
    }
  }
  final problemi = <Problema>[];
  for (final v in voci) {
    final n = nuovi[comeStr(v['id'])]!;
    final pr = controllaSlot(d, inizio: n.i, fine: n.f, operatriceId: comeStr(v['operatriceId']).isEmpty ? null : comeStr(v['operatriceId']), escludiId: comeStr(v['id']), servizi: serviziApp(v));
    for (final p in pr) {
      problemi.add(voci.length > 1 ? Problema(p.tipo, '${F.giornoBreve(n.i)}: ${p.msg}') : p);
    }
  }
  if (!context.mounted) return false;
  final nome = nomeCliente(d.get('clienti', comeStr(app['clienteId']))).isNotEmpty ? nomeCliente(d.get('clienti', comeStr(app['clienteId']))) : comeStr(app['clienteNome']);
  final ok = await conferma(
    context,
    titolo: soloDurata ? 'Cambiare la durata?' : 'Spostare l\'appuntamento?',
    messaggio: soloDurata
        ? '$nome: ${F.intervallo(vI, vF)} → ${F.intervallo(inizio, fine)} (${F.durata(durNuova)}).'
        : '$nome\nda: ${F.giornoLungo(vI)}, ${F.intervallo(vI, vF)}\na: ${F.giornoLungo(inizio)}, ${F.intervallo(inizio, fine)}${voci.length > 1 ? '\n\n…e altri ${voci.length - 1} appuntamenti della serie.' : ''}',
    problemi: problemi,
    ok: problemi.isEmpty ? (soloDurata ? 'Cambia' : 'Sposta') : (soloDurata ? 'Cambia comunque' : 'Sposta comunque'),
  );
  if (!ok || !context.mounted) return false;
  final prima = {for (final v in voci) comeStr(v['id']): (inizio: v['inizio'], fine: v['fine'], dm: v['durataManuale'])};
  for (final v in voci) {
    final n = nuovi[comeStr(v['id'])]!;
    v['inizio'] = isoJs(n.i);
    v['fine'] = isoJs(n.f);
    if (cambiaDurata) v['durataManuale'] = true;
  }
  await d.salvaMolti('appuntamenti', voci);
  vibra(true);
  if (!context.mounted) return true;
  avviso(context, soloDurata ? 'Durata cambiata: ${F.durata(durNuova)}' : 'Spostato a ${giornoRelativo(inizio).toLowerCase()} alle ${D.hhmm(inizio)}${voci.length > 1 ? ' (+${voci.length - 1})' : ''}', annulla: () async {
    for (final v in voci) {
      final p = prima[comeStr(v['id'])]!;
      v['inizio'] = p.inizio;
      v['fine'] = p.fine;
      v['durataManuale'] = p.dm;
    }
    await d.salvaMolti('appuntamenti', voci);
  });
  return true;
}

/// Cambio di stato con Annulla.
Future<void> cambiaStato(BuildContext context, Doc app, String stato, {String? messaggio}) async {
  final d = context.dati;
  final prima = statoApp(app);
  if (prima == stato) return;
  app['stato'] = stato;
  await d.salva('appuntamenti', app);
  vibra();
  if (!context.mounted) return;
  avviso(context, messaggio ?? 'Stato: ${statiAppuntamento[stato]?.nome ?? stato}', annulla: () async {
    app['stato'] = prima;
    await d.salva('appuntamenti', app);
  });
}

/// Archivia (elimina con possibilità di ripristino).
Future<bool> eliminaAppuntamento(BuildContext context, Doc app) async {
  final ok = await conferma(context, titolo: 'Eliminare l\'appuntamento?', messaggio: 'Sparisce dall\'agenda. Potrai annullare subito, oppure ripristinarlo in seguito da Altro → Elementi archiviati.', ok: 'Elimina', pericolo: true);
  if (!ok || !context.mounted) return false;
  final d = context.dati;
  await d.archivia('appuntamenti', comeStr(app['id']));
  if (context.mounted) avviso(context, 'Appuntamento eliminato', annulla: () async => d.ripristina('appuntamenti', comeStr(app['id'])));
  return true;
}

/// File .ics dell'appuntamento (da aggiungere al calendario del telefono).
String icsAppuntamento(Dati d, Doc app) {
  String ts(DateTime t) => isoJs(t).replaceAll(RegExp(r'[-:]'), '').replaceAll(RegExp(r'\.\d{3}'), '');
  String esc(String s) => s.replaceAll('\\', '\\\\').replaceAll(';', '\\;').replaceAll(',', '\\,').replaceAll('\n', '\\n');
  final cli = d.get('clienti', comeStr(app['clienteId']));
  final nome = cli != null ? nomeCliente(cli) : comeStr(app['clienteNome']);
  final att = d.nomeAttivita;
  return [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Agenda Nails//IT', 'CALSCALE:GREGORIAN', 'BEGIN:VEVENT',
    'UID:${app['id']}@agenda-nails', 'DTSTAMP:${ts(DateTime.now())}', 'DTSTART:${ts(inizioApp(app))}', 'DTEND:${ts(fineApp(app))}',
    'SUMMARY:${esc('${serviziTesto(app)} — $nome')}',
    if (att.isNotEmpty) 'LOCATION:${esc(att)}',
    if (comeStr(app['note']).isNotEmpty) 'DESCRIPTION:${esc(comeStr(app['note']))}',
    'END:VEVENT', 'END:VCALENDAR', '',
  ].join('\r\n');
}

Future<void> condividiIcs(BuildContext context, Doc app) async {
  final d = context.dati;
  final testo = icsAppuntamento(d, app);
  await condividiFile(context, Uint8List.fromList(utf8.encode(testo)), 'appuntamento-${D.key(inizioApp(app))}.ics', tipo: 'text/calendar');
}

/// Riga di un appuntamento (elenchi di Oggi, Agenda → Elenco, scheda cliente).
class RigaAppuntamento extends StatelessWidget {
  const RigaAppuntamento({super.key, required this.app, required this.suTocco, this.mostraData = false, this.mostraCliente = true});
  final Doc app;
  final VoidCallback suTocco;
  final bool mostraData, mostraCliente;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final i = inizioApp(app), f = fineApp(app);
    final cli = d.get('clienti', comeStr(app['clienteId']));
    final nome = cli != null ? nomeCliente(cli) : (comeStr(app['clienteNome']).isEmpty ? 'Cliente' : comeStr(app['clienteNome']));
    final colore = Color(coloreApp(d, app));
    final st = statoApp(app);
    final spento = st == 'annullato' || st == 'non_presentata';
    return InkWell(
      onTap: suTocco,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: mostraData ? 76 : 54,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (mostraData) Text(F.giornoCorto(i), style: t.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              Text(D.hhmm(i), style: t.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], decoration: spento ? TextDecoration.lineThrough : null)),
              Text(D.hhmm(f), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
            ]),
          ),
          Container(width: 4, height: 44, margin: const EdgeInsets.only(right: 12, top: 2), decoration: BoxDecoration(color: spento ? cs.outline : colore, borderRadius: BorderRadius.circular(4))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (mostraCliente) Flexible(child: Text(nome, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (!mostraCliente) Flexible(child: Text(serviziTesto(app), style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (mostraCliente && haAvvertenze(cli)) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.warning_rounded, size: 18, color: Color(0xFFB42318))),
                if ((comeInt(app['accontoCent']) ?? 0) > 0) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.savings_outlined, size: 18, color: cs.primary)),
              ]),
              if (mostraCliente) Text(serviziTesto(app), maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              if (st != 'prenotato') Padding(padding: const EdgeInsets.only(top: 4), child: StatoPill(st)),
            ]),
          ),
          if ((comeInt(app['prezzoTotaleCent']) ?? 0) > 0)
            Padding(padding: const EdgeInsets.only(left: S.s, top: 2), child: Text(F.euro(comeInt(app['prezzoTotaleCent'])), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }
}
