import 'package:flutter/material.dart';

import '../core/date.dart';
import '../core/util.dart';
import '../dominio/agenda.dart';
import '../dominio/appunti.dart';
import '../dominio/demo.dart';
import '../dominio/magazzino.dart';
import '../dominio/backup.dart';
import '../servizi/aggiornamenti.dart';
import '../servizi/backup_android.dart';
import '../servizi/notifiche.dart';
import 'agenda/azioni.dart';
import 'agenda/dettaglio_appuntamento.dart';
import 'agenda/modulo_appuntamento.dart';
import 'app.dart';
import 'appunti/pagina_appunti.dart';
import 'clienti/pagina_clienti.dart';
import 'clienti/scheda_cliente.dart';
import 'comuni.dart';
import 'fornitori/ordini.dart';
import 'impostazioni/aggiornamenti.dart';
import 'impostazioni/pagina_altro.dart';
import 'magazzino/scheda_prodotto.dart';
import 'piattaforma.dart';
import 'tema.dart';

/// Cruscotto "Oggi": appuntamenti di oggi e domani, incassi, clienti da ricontattare, stato del backup.
class PaginaOggi extends StatelessWidget {
  const PaginaOggi({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: Listenable.merge([d, context.cloud, Aggiornamenti.istanza, backupAndroidTrovato]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final ora = DateTime.now();
        final oggi = D.inizioGiorno(ora), domani = D.aggiungiGiorni(oggi, 1);
        List<Doc> del(DateTime g) => appuntamentiTra(d, g, D.aggiungiGiorni(g, 1)).where((a) => statoApp(a) != 'annullato').toList()..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
        final appOggi = del(oggi), appDomani = del(domani);
        final visite = tutteLeVisite(d);
        final kOggi = D.key(oggi);
        final incOggi = incassoTra(visite, kOggi, kOggi) + venditeTra(d, kOggi, kOggi);
        final lun = D.inizioSettimana(oggi);
        final incSett = incassoTra(visite, D.key(lun), D.key(D.aggiungiGiorni(lun, 6))) + venditeTra(d, D.key(lun), D.key(D.aggiungiGiorni(lun, 6)));
        final mag = d.moduloAttivo('magazzino'), ord = d.moduloAttivo('ordini'), app = d.moduloAttivo('appunti');
        final avvMag = mag ? avvisiMagazzino(d) : null;
        final promemoria = app ? promemoriaInArrivo(d) : <Doc>[];
        final ordini = ord ? d.elenco('ordini_fornitore').where((o) => statiOrdineAttesa.contains(o['stato'])).toList() : <Doc>[];
        final daAvvisare = appDomani.where((a) => ['prenotato', 'confermato'].contains(statoApp(a)) && comeStr(d.get('clienti', comeStr(a['clienteId']))?['telefono']).isNotEmpty).toList();
        final previsto = appOggi.where((a) => ['prenotato', 'confermato'].contains(statoApp(a))).fold(0, (s, a) => s + (comeInt(a['prezzoTotaleCent']) ?? 0));
        final richiami = clientiDaRicontattare(d);
        final prossimo = appOggi.where((a) => fineApp(a).isAfter(ora) && ['prenotato', 'confermato'].contains(statoApp(a))).firstOrNull;
        final saluto = ora.hour < 13 ? 'Buongiorno' : (ora.hour < 18 ? 'Buon pomeriggio' : 'Buonasera');
        final titolare = comeStr(comeDoc(d.cfg['attivita'])['titolare']);
        final vuoto = d.conta('clienti') == 0 && d.conta('appuntamenti') == 0;
        final largo = eLargo(context);

        final colonnaAgenda = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (backupAndroidTrovato.value != null) ...[
            const _BackupAndroidTrovato(),
            const SizedBox(height: S.l),
          ],
          if (Aggiornamenti.istanza.daProporre(d)) ...[
            const RiquadroAggiornamento(),
            const SizedBox(height: S.l),
          ],
          if (prossimo != null) ...[
            _Prossimo(app: prossimo),
            const SizedBox(height: S.l),
          ],
          Sezione(
            titolo: appOggi.isEmpty ? 'Oggi' : 'Oggi · ${appOggi.length} ${appOggi.length == 1 ? 'appuntamento' : 'appuntamenti'}',
            azione: TextButton(onPressed: () => navigazione.vai('agenda', giorno: oggi), child: const Text('Agenda')),
            child: appOggi.isEmpty
                ? Text(intervalliGiorno(d, oggi).isEmpty && d.cfg['orari'] is Map ? 'Oggi è giorno di chiusura. Riposati! 🌿' : 'Nessun appuntamento oggi.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                : Column(children: [for (final a in appOggi) RigaAppuntamento(app: a, suTocco: () => apriAppuntamento(context, a))]),
          ),
          const SizedBox(height: S.l),
          Sezione(
            titolo: 'Domani${appDomani.isEmpty ? '' : ' · ${appDomani.length}'}',
            azione: TextButton(onPressed: () => navigazione.vai('agenda', giorno: domani), child: const Text('Vedi')),
            child: appDomani.isEmpty
                ? Text('Nessun appuntamento domani.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final a in appDomani) RigaAppuntamento(app: a, suTocco: () => apriAppuntamento(context, a)),
                    if (d.cfg['promemoriaWhatsApp'] != false && daAvvisare.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: S.s),
                        child: Builder(builder: (context) {
                          final mancano = daAvvisare.where((a) => a['promemoriaInviatoIl'] == null).length;
                          return mancano > 0
                              ? FilledButton.icon(onPressed: () => apriCodaPromemoria(context, daAvvisare), icon: const Icon(Icons.chat_rounded), label: Text('Invia i promemoria ($mancano)'))
                              : OutlinedButton.icon(onPressed: () => apriCodaPromemoria(context, daAvvisare), icon: const Icon(Icons.done_all_rounded), label: const Text('Promemoria inviati'));
                        }),
                      ),
                  ]),
          ),
        ]);

        final colonnaLato = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GrigliaTessere(
            colonne: 2,
            children: [
              Tessera(valore: F.euro(incOggi), etichetta: 'incassato oggi'),
              Tessera(valore: F.euro(incSett), etichetta: 'questa settimana'),
              Tessera(valore: F.euro(previsto), etichetta: 'ancora da fare oggi'),
              Tessera(valore: '${richiami.length}', etichetta: 'da ricontattare'),
            ],
          ),
          const SizedBox(height: S.l),
          if (richiami.isNotEmpty) ...[
            Sezione(
              titolo: 'Da ricontattare',
              padding: const EdgeInsets.fromLTRB(S.s, S.m, S.s, S.s),
              azione: TextButton(onPressed: () => navigazione.vai('clienti'), child: const Text('Tutte')),
              child: Column(children: [for (final r in richiami.take(4)) RigaRichiamo(r: r, suApri: () => apriSchedaCliente(context, comeStr(r.cliente['id'])))]),
            ),
            const SizedBox(height: S.l),
          ],
          if (avvMag != null && avvMag.totale > 0) ...[
            Sezione(
              titolo: 'Magazzino',
              padding: const EdgeInsets.fromLTRB(S.s, S.m, S.s, S.s),
              azione: TextButton(onPressed: () => navigazione.vai('magazzino'), child: const Text('Apri')),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (x, testo, tipo) in [
                  for (final x in avvMag.negativi) (x, 'giacenza negativa: controlla i carichi', 'pericolo'),
                  for (final x in avvMag.sottoScorta.where((x) => x.g >= 0)) (x, 'sotto scorta (minimo ${fmtQta(x.p['scortaMinima'], comeStr(x.p['unita']))})', 'avviso'),
                  for (final x in avvMag.scaduti) (x, 'scaduto il ${F.dataKey(comeStr(x.p['scadenza']))}', 'pericolo'),
                  for (final x in avvMag.inScadenza) (x, 'scade il ${F.dataKey(comeStr(x.p['scadenza']))}', 'avviso'),
                  for (final x in avvMag.paoSuperato) (x, 'aperto da oltre il PAO (dal ${F.dataKey(x.pao)})', 'pericolo'),
                ].take(6))
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: S.s),
                    leading: Icon(tipo == 'pericolo' ? Icons.error_outline_rounded : Icons.warning_amber_rounded, color: tipo == 'pericolo' ? const Color(0xFFB42318) : const Color(0xFF9A5B00)),
                    title: Text(nomeProdotto(x.p)),
                    subtitle: Text('$testo · hai ${fmtQta(x.g, comeStr(x.p['unita']))}'),
                    onTap: () => apriProdotto(context, comeStr(x.p['id'])),
                  ),
                if (ord && avvMag.sottoScorta.isNotEmpty)
                  Padding(padding: const EdgeInsets.fromLTRB(S.s, S.s, S.s, 0), child: OutlinedButton.icon(onPressed: () => creaOrdiniSottoScorta(context), icon: const Icon(Icons.local_shipping_outlined), label: const Text('Prepara gli ordini'))),
              ]),
            ),
            const SizedBox(height: S.l),
          ],
          if (ordini.isNotEmpty) ...[
            Sezione(
              titolo: 'Ordini in attesa',
              padding: const EdgeInsets.fromLTRB(S.s, S.m, S.s, S.s),
              azione: TextButton(onPressed: () => navigazione.vai('ordini'), child: const Text('Tutti')),
              child: Column(children: [for (final o in ordini.take(5)) RigaOrdine(o: o)]),
            ),
            const SizedBox(height: S.l),
          ],
          if (app) ...[
            Sezione(
              titolo: 'Promemoria',
              padding: const EdgeInsets.fromLTRB(S.s, S.m, S.s, S.s),
              azione: TextButton(onPressed: () => navigazione.vai('appunti'), child: const Text('Appunti')),
              child: promemoria.isEmpty
                  ? Padding(padding: const EdgeInsets.all(S.s), child: Text('Nessun promemoria nei prossimi 7 giorni.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
                  : Column(children: [
                      for (final a in promemoria.take(6))
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: S.s),
                          leading: Icon(Icons.alarm_rounded, color: statoPromemoria(a)?.$2 == 'pericolo' ? const Color(0xFFB42318) : cs.primary),
                          title: Text(comeStr(a['titolo']).isNotEmpty ? comeStr(a['titolo']) : comeStr(a['testo']), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(statoPromemoria(a)?.$1 ?? ''),
                          onTap: () => apriAppunto(context, appunto: a),
                        ),
                    ]),
            ),
            const SizedBox(height: S.l),
          ],
          _StatoBackup(),
          if (Notifiche.istanza.supportate && d.meta('notificheChieste') != true && d.moduloAttivo('agenda')) ...[
            const SizedBox(height: S.l),
            Riquadro(
              titolo: 'Vuoi un avviso la sera prima?',
              testo: 'L\'app può ricordarti gli appuntamenti del giorno dopo, i promemoria degli appunti e i prodotti da riordinare. Funziona anche senza internet.',
              azioni: [
                FilledButton(
                  onPressed: () async {
                    final si = await Notifiche.istanza.chiediPermesso();
                    await d.scriviMeta('notificheChieste', true);
                    d.aggiorna();
                    if (si) await Notifiche.istanza.riprogramma(d);
                    avvisa(si ? 'Notifiche attive. Le regoli da Altro → Notifiche.' : 'Va bene. Puoi attivarle quando vuoi da Altro → Notifiche.');
                  },
                  child: const Text('Attiva le notifiche'),
                ),
                TextButton(
                  onPressed: () async {
                    await d.scriviMeta('notificheChieste', true);
                    d.aggiorna();
                  },
                  child: const Text('No, grazie'),
                ),
              ],
            ),
          ],
        ]);

        return Scaffold(
          body: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.l, S.xl, S.s, S.l),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(F.giornoLungo(ora).toUpperCase(), style: t.labelMedium?.copyWith(color: cs.primary, letterSpacing: 1.2)),
                        const SizedBox(height: 4),
                        Text(titolare.isEmpty ? saluto : '$saluto, $titolare', style: t.headlineMedium),
                        if (d.nomeAttivita.isNotEmpty) Text(d.nomeAttivita, style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    IconButton(tooltip: 'Cerca una cliente', onPressed: () => navigazione.vai('clienti'), icon: const Icon(Icons.person_search_outlined)),
                  ]),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, 120),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (vuoto) ...[_Benvenuto(), const SizedBox(height: S.l)],
                      if (largo)
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 3, child: colonnaAgenda), const SizedBox(width: S.l), Expanded(flex: 2, child: colonnaLato)])
                      else ...[colonnaLato, const SizedBox(height: S.l), colonnaAgenda],
                    ]),
                  ),
                ),
              ),
            ),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'oggi-nuovo',
            onPressed: () => apriModuloAppuntamento(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Appuntamento'),
          ),
        );
      },
    );
  }
}

class _Prossimo extends StatelessWidget {
  const _Prossimo({required this.app});
  final Doc app;
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final cli = d.get('clienti', comeStr(app['clienteId']));
    final nome = cli != null ? nomeCliente(cli) : comeStr(app['clienteNome']);
    final i = inizioApp(app);
    final ora = DateTime.now();
    final inCorso = !i.isAfter(ora);
    final tra = D.minutiTra(ora, i);
    final quando = inCorso ? 'In corso · fino alle ${D.hhmm(fineApp(app))}' : (tra < 60 ? 'Tra $tra min · ${D.hhmm(i)}' : 'Alle ${D.hhmm(i)}');
    final colore = cs.primary;
    return Material(
      color: colore,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => apriAppuntamento(context, app),
        child: Padding(
          padding: const EdgeInsets.all(S.l),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(inCorso ? 'ORA' : 'PROSSIMA', style: t.labelMedium?.copyWith(color: cs.onPrimary.withValues(alpha: 0.8), letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Text(nome, style: t.headlineSmall?.copyWith(color: cs.onPrimary)),
                Text(serviziTesto(app), style: t.bodyLarge?.copyWith(color: cs.onPrimary.withValues(alpha: 0.9))),
                const SizedBox(height: 6),
                Text(quando, style: t.titleSmall?.copyWith(color: cs.onPrimary)),
                if (haAvvertenze(cli))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [Icon(Icons.warning_rounded, size: 18, color: cs.onPrimary), const SizedBox(width: 4), Expanded(child: Text(comeStr(cli!['avvertenze']), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700)))]),
                  ),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onPrimary, size: 30),
          ]),
        ),
      ),
    );
  }
}

class _Benvenuto extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final passi = [
      (d.nomeAttivita.isNotEmpty, 'Nome dell\'attività e colori', 'attivita'),
      (d.cfg['orari'] is Map, 'Orari di apertura e pausa', 'orari'),
      (serviziAttivi(d).isNotEmpty, 'Listino dei servizi', 'servizi'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(S.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Benvenuta! 💅', style: t.headlineSmall),
          const SizedBox(height: S.s),
          const Text('Tre passi per iniziare. Puoi anche provare l\'app con dei dati di prova, da cancellare quando vuoi.'),
          const SizedBox(height: S.m),
          for (final (fatto, testo, dove) in passi)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(fatto ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: fatto ? const Color(0xFF1F7A55) : null),
              title: Text(testo, style: TextStyle(decoration: fatto ? TextDecoration.lineThrough : null)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => apriImpostazione(context, dove),
            ),
          const SizedBox(height: S.s),
          OutlinedButton.icon(
            onPressed: () async {
              await caricaDatiDemo(d, configura: true);
              if (context.mounted) avviso(context, 'Dati di prova caricati. Li rimuovi da Altro → Dati di prova.');
            },
            icon: const Icon(Icons.science_outlined),
            label: const Text('Carica dati di prova'),
          ),
        ]),
      ),
    );
  }
}

class _StatoBackup extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cloud = context.cloud;
    final ultimo = comeStr(d.meta('ultimoBackup'));
    final giorni = ultimo.isEmpty ? null : D.diffGiorni(D.key(D.daIso(ultimo)), D.oggiKey());
    final limite = comeInt(comeDoc(d.cfg['avvisi'])['backupGiorni']) ?? 7;
    if (cloud.attivo) {
      final errore = cloud.esito.stato == 'errore';
      return Riquadro(
        tipo: errore ? 'avviso' : 'ok',
        titolo: errore ? 'Cloud: c\'è un problema' : 'Backup automatico nel cloud attivo',
        testo: cloud.esito.testo.isEmpty ? 'I dati vengono cifrati e salvati da soli.' : cloud.esito.testo,
        azioni: [OutlinedButton(onPressed: () => apriImpostazione(context, 'dati'), child: const Text('Dettagli'))],
      );
    }
    if (d.conta('clienti') == 0) return const SizedBox.shrink();
    final scaduto = giorni == null || giorni > limite;
    return Riquadro(
      tipo: scaduto ? 'avviso' : 'ok',
      titolo: giorni == null ? 'Nessun backup ancora' : (giorni == 0 ? 'Backup fatto oggi' : 'Ultimo backup $giorni giorni fa'),
      testo: scaduto ? 'I dati sono salvati solo su questo dispositivo: se si rompe o lo perdi, li perdi. Fai un backup o attiva il cloud.' : 'Bene così.',
      azioni: [if (scaduto) FilledButton(onPressed: () => apriImpostazione(context, 'dati'), child: const Text('Fai il backup'))],
    );
  }
}

const statiOrdineAttesa = ['inviato', 'parziale'];

/// Promemoria WhatsApp per gli appuntamenti di domani: uno alla volta, segnando quelli inviati.
Future<void> apriCodaPromemoria(BuildContext context, List<Doc> apps) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (c) => ListenableBuilder(
      listenable: c.dati,
      builder: (c, _) {
        final d = c.dati;
        final t = Theme.of(c).textTheme;
        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.xl), children: [
          Text('Promemoria per domani', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text('Tocca WhatsApp: il messaggio si apre già scritto, lo invii tu. Poi torna qui per il successivo.', style: t.bodyMedium),
          const SizedBox(height: S.m),
          for (final a in apps)
            Builder(builder: (c) {
              final x = d.get('appuntamenti', comeStr(a['id'])) ?? a;
              final cli = d.get('clienti', comeStr(x['clienteId']));
              final inviato = x['promemoriaInviatoIl'] != null;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(inviato ? Icons.check_circle_rounded : Icons.schedule_rounded, color: inviato ? const Color(0xFF1F7A55) : null),
                title: Text(nomeCliente(cli)),
                subtitle: Text('${D.hhmm(inizioApp(x))} · ${serviziTesto(x)}${inviato ? ' · inviato' : ''}'),
                trailing: cli == null
                    ? null
                    : FilledButton.tonalIcon(
                        onPressed: () async {
                          await apriLink(c, linkPromemoria(d, cli, x));
                          x['promemoriaInviatoIl'] = adessoIso();
                          await d.salva('appuntamenti', x);
                        },
                        icon: const Icon(Icons.chat_rounded),
                        label: const Text('WhatsApp'),
                      ),
              );
            }),
        ]);
      },
    ),
  );
}

/// Dopo una reinstallazione: Android ha riportato la copia dei dati dal backup di Google.
class _BackupAndroidTrovato extends StatelessWidget {
  const _BackupAndroidTrovato();
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final b = backupAndroidTrovato.value;
    if (b == null) return const SizedBox.shrink();
    return Riquadro(
      tipo: 'ok',
      titolo: 'Ho ritrovato i tuoi dati',
      testo: 'Android ha recuperato dal backup di Google una copia${b.creato == null ? '' : ' del ${F.dataOra(b.creato)}'}: '
          '${b.conta('clienti')} clienti, ${b.conta('appuntamenti')} appuntamenti, ${b.conta('prodotti')} prodotti. Le foto non sono incluse.',
      azioni: [
        FilledButton(
          onPressed: () async {
            await applicaBackup(d, b);
            backupAndroidTrovato.value = null;
            avvisa('Dati recuperati.');
          },
          child: const Text('Recupera i dati'),
        ),
        TextButton(
          onPressed: () async {
            await d.scriviMeta('backupAndroidIgnorato', true);
            backupAndroidTrovato.value = null;
          },
          child: const Text('No, parto da zero'),
        ),
      ],
    );
  }
}
