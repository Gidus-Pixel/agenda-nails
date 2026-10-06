import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
import '../clienti/scheda_cliente.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../storico/scheda_lavoro.dart';
import '../tema.dart';
import 'azioni.dart';
import 'modulo_appuntamento.dart';

/// Apre il dettaglio di un appuntamento (foglio dal basso; su tablet più stretto e centrato).
Future<void> apriAppuntamento(BuildContext context, Doc app) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (c) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (c, scroll) => _Dettaglio(id: comeStr(app['id']), scroll: scroll),
    ),
  );
}

class _Dettaglio extends StatelessWidget {
  const _Dettaglio({required this.id, required this.scroll});
  final String id;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final app = d.get('appuntamenti', id);
        if (app == null || app['archiviato'] == true) {
          return const Center(child: Vuoto('Appuntamento non più disponibile.', icona: Icons.event_busy_outlined));
        }
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final cli = d.get('clienti', comeStr(app['clienteId']));
        final nome = cli != null ? nomeCliente(cli) : (comeStr(app['clienteNome']).isEmpty ? 'Cliente eliminata' : comeStr(app['clienteNome']));
        final i = inizioApp(app), f = fineApp(app);
        final st = statoApp(app);
        final tel = comeStr(cli?['telefono']);
        final totale = comeInt(app['prezzoTotaleCent']) ?? 0;
        final acconto = comeInt(app['accontoCent']) ?? 0;
        final scheda = d.get('schede_lavoro', comeStr(app['schedaId']));
        final aperto = st == 'prenotato' || st == 'confermato';

        Widget azione(IconData ic, String testo, VoidCallback? fn, {bool principale = false}) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: principale
                    ? FilledButton.tonal(onPressed: fn, style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), minimumSize: const Size(0, 64)), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(ic), const SizedBox(height: 4), Text(testo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))]))
                    : OutlinedButton(onPressed: fn, style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10), minimumSize: const Size(0, 64)), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(ic), const SizedBox(height: 4), Text(testo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))])),
              ),
            );

        return ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.xl), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Avatar(nome, dimensione: 48, colore: Color(coloreApp(d, app))),
            const SizedBox(width: S.m),
            Expanded(
              child: InkWell(
                onTap: cli == null ? null : () => apriSchedaCliente(context, comeStr(cli['id'])),
                borderRadius: BorderRadius.circular(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nome, style: t.headlineSmall),
                  if (tel.isNotEmpty) Text(telefonoLeggibile(tel), style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
            StatoPill(st),
          ]),
          const SizedBox(height: S.m),
          Container(
            padding: const EdgeInsets.all(S.m),
            decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.schedule_rounded, size: 20, color: cs.primary),
                const SizedBox(width: S.s),
                Expanded(child: Text('${F.giornoLungo(i)}\n${F.intervallo(i, f)} · ${F.durata(D.minutiTra(i, f))}', style: t.titleMedium)),
              ]),
              if (d.piuOperatrici) ...[
                const SizedBox(height: S.s),
                Row(children: [Icon(Icons.person_outline_rounded, size: 20, color: cs.primary), const SizedBox(width: S.s), Text(nomeOperatrice(d, comeStr(app['operatriceId'])))]),
              ],
            ]),
          ),
          if (haAvvertenze(cli)) ...[const SizedBox(height: S.m), Avvertenze(comeStr(cli!['avvertenze']))],
          const SizedBox(height: S.m),
          for (final s in serviziApp(app))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(coloreServizio(d, {'servizi': [s]})), shape: BoxShape.circle)),
                const SizedBox(width: S.s),
                Expanded(child: Text('${s['nome']}${(comeInt(s['quantita']) ?? 1) > 1 ? ' ×${s['quantita']}' : ''}', style: t.bodyLarge)),
                Text(F.durata((comeInt(s['durata']) ?? 0) * (comeInt(s['quantita']) ?? 1)), style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: S.m),
                Text(F.euro((comeInt(s['prezzoCent']) ?? 0) * (comeInt(s['quantita']) ?? 1))),
              ]),
            ),
          if (serviziApp(app).isEmpty) Text('Nessun servizio indicato', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          const Divider(height: S.l),
          Row(children: [
            Expanded(child: Text('Totale', style: t.titleMedium)),
            Text(F.euro(totale), style: t.titleMedium),
          ]),
          if (acconto > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.savings_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(child: Text('Acconto versato ${F.euro(acconto)}')),
                Text('da incassare ${F.euro((totale - acconto).clamp(0, 1 << 31))}', style: t.bodySmall),
              ]),
            ),
          if (comeStr(app['note']).isNotEmpty) ...[
            const SizedBox(height: S.m),
            Text('Note', style: t.labelLarge),
            Text(comeStr(app['note'])),
          ],
          if (comeStr(app['serieId']).isNotEmpty) ...[
            const SizedBox(height: S.m),
            Text('🔁 Fa parte di una serie di appuntamenti ripetuti.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: S.l),
          Row(children: [
            azione(Icons.chat_rounded, app['promemoriaInviatoIl'] != null ? 'Inviato ✓' : 'WhatsApp', tel.isEmpty ? null : () async {
              await apriLink(context, linkPromemoria(d, cli!, app));
              app['promemoriaInviatoIl'] = adessoIso();
              await d.salva('appuntamenti', app);
            }, principale: true),
            azione(Icons.call_rounded, 'Chiama', tel.isEmpty ? null : () => chiama(context, tel)),
            azione(Icons.open_with_rounded, 'Sposta', aperto ? () => _sposta(context, app) : null),
            azione(Icons.edit_outlined, 'Modifica', () async {
              final r = radice(context);
              Navigator.pop(context);
              await apriModuloAppuntamento(r, app: app);
            }),
          ]),
          const SizedBox(height: S.l),
          if (st == 'prenotato')
            _Bottone(icona: Icons.check_circle_outline_rounded, testo: 'Segna come confermato', fn: () => cambiaStato(context, app, 'confermato', messaggio: 'Appuntamento confermato')),
          if (aperto)
            _Bottone(
              icona: Icons.task_alt_rounded,
              testo: 'Completa e compila la scheda lavoro',
              principale: true,
              fn: () async {
                final r = radice(context);
                Navigator.pop(context);
                await apriSchedaLavoro(r, app: app);
              },
            ),
          if (scheda != null)
            _Bottone(
              icona: Icons.description_outlined,
              testo: 'Apri la scheda lavoro',
              fn: () async {
                final r = radice(context);
                Navigator.pop(context);
                await apriSchedaLavoro(r, scheda: scheda);
              },
            ),
          if (st == 'completato' && scheda == null)
            _Bottone(
              icona: Icons.note_add_outlined,
              testo: 'Compila la scheda lavoro',
              fn: () async {
                final r = radice(context);
                Navigator.pop(context);
                await apriSchedaLavoro(r, app: app);
              },
            ),
          if (aperto && i.isBefore(DateTime.now())) _Bottone(icona: Icons.person_off_outlined, testo: 'Non si è presentata', fn: () => cambiaStato(context, app, 'non_presentata', messaggio: 'Segnata come non presentata')),
          if (aperto) _Bottone(icona: Icons.event_busy_outlined, testo: 'Annulla l\'appuntamento', fn: () => cambiaStato(context, app, 'annullato', messaggio: 'Appuntamento annullato')),
          if (st == 'annullato' || st == 'non_presentata') _Bottone(icona: Icons.restore_rounded, testo: 'Riporta a "prenotato"', fn: () => cambiaStato(context, app, 'prenotato')),
          _Bottone(icona: Icons.calendar_today_outlined, testo: 'Aggiungi al calendario del telefono (.ics)', fn: () => condividiIcs(context, app)),
          _Bottone(
            icona: Icons.delete_outline_rounded,
            testo: 'Elimina',
            pericolo: true,
            fn: () async {
              if (await eliminaAppuntamento(context, app) && context.mounted) Navigator.pop(context);
            },
          ),
        ]);
      },
    );
  }

  Future<void> _sposta(BuildContext context, Doc app) async {
    final r = await chiediNuovoOrario(context, app);
    if (r == null || !context.mounted) return;
    await spostaAppuntamento(context, app, r.inizio, r.fine);
  }
}

class _Bottone extends StatelessWidget {
  const _Bottone({required this.icona, required this.testo, required this.fn, this.principale = false, this.pericolo = false});
  final IconData icona;
  final String testo;
  final VoidCallback fn;
  final bool principale, pericolo;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.s),
      child: principale
          ? FilledButton.icon(onPressed: fn, icon: Icon(icona), label: Text(testo), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: S.l)))
          : OutlinedButton.icon(
              onPressed: fn,
              icon: Icon(icona, color: pericolo ? cs.error : null),
              label: Text(testo, style: TextStyle(color: pericolo ? cs.error : null)),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50), alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: S.l)),
            ),
    );
  }
}

/// Finestra "Sposta": nuova data e ora (durata invariata), con i primi spazi liberi suggeriti.
Future<({DateTime inizio, DateTime fine})?> chiediNuovoOrario(BuildContext context, Doc app) {
  return showDialog<({DateTime inizio, DateTime fine})>(context: context, builder: (c) => _DialogoSposta(app: app));
}

class _DialogoSposta extends StatefulWidget {
  const _DialogoSposta({required this.app});
  final Doc app;
  @override
  State<_DialogoSposta> createState() => _DialogoSpostaState();
}

class _DialogoSpostaState extends State<_DialogoSposta> {
  late DateTime _inizio = inizioApp(widget.app);
  late final int _durata = durataApp(widget.app);

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final fine = D.aggiungiMinuti(_inizio, _durata);
    final problemi = controllaSlot(d, inizio: _inizio, fine: fine, operatriceId: comeStr(widget.app['operatriceId']).isEmpty ? null : comeStr(widget.app['operatriceId']), escludiId: comeStr(widget.app['id']), servizi: serviziApp(widget.app));
    final liberi = trovaSlotLiberi(d, durataMin: _durata, operatriceId: comeStr(widget.app['operatriceId']).isEmpty ? null : comeStr(widget.app['operatriceId']), servizi: serviziApp(widget.app), escludiId: comeStr(widget.app['id']), quanti: 6, da: D.inizioGiorno(_inizio));
    return AlertDialog(
      title: const Text('Sposta appuntamento'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Durata: ${F.durata(_durata)}', style: t.bodyMedium),
          const SizedBox(height: S.m),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded),
                label: Text(F.giornoBreve(_inizio)),
                onPressed: () async {
                  final g = await scegliData(context, _inizio);
                  if (g != null) setState(() => _inizio = D.combina(D.key(g), D.hhmm(_inizio)));
                },
              ),
            ),
            const SizedBox(width: S.s),
            Expanded(
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
          const SizedBox(height: S.s),
          Text('Nuovo orario: ${F.intervallo(_inizio, fine)}', style: t.titleSmall),
          if (problemi.isNotEmpty) ...[
            const SizedBox(height: S.s),
            Riquadro(tipo: 'avviso', testo: problemi.map((p) => '• ${p.msg}').join('\n')),
          ],
          if (liberi.slot.isNotEmpty) ...[
            const SizedBox(height: S.m),
            Text('Primi spazi liberi', style: t.labelLarge),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in liberi.slot)
                ActionChip(label: Text('${F.giornoCorto(s)} ${D.hhmm(s)}'), onPressed: () => setState(() => _inizio = s)),
            ]),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        FilledButton(onPressed: () => Navigator.pop(context, (inizio: _inizio, fine: fine)), child: const Text('Continua')),
      ],
    );
  }
}
