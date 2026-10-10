import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/util.dart';
import '../../dominio/sicurezza.dart';
import '../agenda/blocchi.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';
import '../../servizi/aggiornamenti.dart';
import 'aggiornamenti.dart';
import 'archivio.dart';
import 'configurazione.dart';
import 'orari.dart';
import 'pagina_dati.dart';
import 'servizi.dart';

/// Apre una sezione delle impostazioni per nome.
Future<void> apriImpostazione(BuildContext context, String dove) {
  final Widget pagina = switch (dove) {
    'attivita' => const PaginaAttivita(),
    'aspetto' => const PaginaAspetto(),
    'orari' => const PaginaOrari(),
    'agenda' => const PaginaOpzioniAgenda(),
    'servizi' => const PaginaServizi(),
    'operatrici' => const PaginaOperatrici(),
    'messaggi' => const PaginaMessaggi(),
    'blocchi' => const PaginaBlocchi(),
    'archivio' => const PaginaArchivio(),
    'info' => const PaginaInfo(),
    'moduli' => const PaginaModuli(),
    'sicurezza' => const PaginaSicurezza(),
    'notifiche' => const PaginaNotifiche(),
    'magazzino' => const PaginaOpzioniMagazzino(),
    'aggiornamenti' => const PaginaAggiornamenti(),
    _ => const PaginaDati(),
  };
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => pagina));
}

class PaginaAltro extends StatefulWidget {
  const PaginaAltro({super.key});
  @override
  State<PaginaAltro> createState() => _PaginaAltroState();
}

class _PaginaAltroState extends State<PaginaAltro> {
  @override
  void initState() {
    super.initState();
    final s = schermataAvvio;
    if (s == 'impostazioni-orari' || s == 'dati' || s == 'sicurezza' || s == 'notifiche') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) apriImpostazione(context, s == 'impostazioni-orari' ? 'orari' : s!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: Listenable.merge([d, context.cloud, Aggiornamenti.istanza]),
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final cloud = context.cloud;
        Widget voce(IconData ic, String titolo, String sotto, String dove, {Widget? coda}) => ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Icon(ic, color: cs.primary),
              ),
              title: Text(titolo),
              subtitle: Text(sotto, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: coda ?? const Icon(Icons.chevron_right_rounded),
              onTap: () => apriImpostazione(context, dove),
            );
        Widget gruppo(String titolo, List<Widget> voci) => Padding(
              padding: const EdgeInsets.only(bottom: S.l),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(padding: const EdgeInsets.fromLTRB(S.s, 0, S.s, S.s), child: Text(titolo.toUpperCase(), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 1))),
                Card(child: Column(children: [for (var i = 0; i < voci.length; i++) ...[if (i > 0) const Divider(indent: 72), voci[i]]])),
              ]),
            );
        final orari = d.cfg['orari'];
        final inBarra = vociVisibili(context).map((v) => v.chiave).toSet();
        final sezioni = [
          if (d.moduloAttivo('magazzino') && !inBarra.contains('magazzino')) ('magazzino', Icons.inventory_2_outlined, 'Magazzino', '${d.conta('prodotti')} prodotti'),
          if (d.moduloAttivo('ordini') && !inBarra.contains('ordini')) ('ordini', Icons.local_shipping_outlined, 'Ordini ai fornitori', '${d.elenco('ordini_fornitore').where((o) => statiOrdineAperti.contains(o['stato'])).length} aperti'),
          if (d.moduloAttivo('fornitori') && !inBarra.contains('fornitori')) ('fornitori', Icons.storefront_outlined, 'Fornitori', '${d.conta('fornitori')} fornitori'),
          if (d.moduloAttivo('appunti') && !inBarra.contains('appunti')) ('appunti', Icons.sticky_note_2_outlined, 'Appunti', '${d.conta('appunti')} appunti'),
          if (d.moduloAttivo('report') && !inBarra.contains('report')) ('report', Icons.insights_outlined, 'Report', 'Incassi, servizi, consumi, spesa'),
        ];
        return Scaffold(
          appBar: AppBar(title: const Text('Altro')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
                if (sezioni.isNotEmpty)
                  gruppo('Gestione', [
                    for (final (k, ic, titolo, sotto) in sezioni)
                      ListTile(
                        leading: Container(width: 40, height: 40, decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(ic, color: cs.primary)),
                        title: Text(titolo),
                        subtitle: Text(sotto),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => apriSezione(context, k),
                      ),
                  ]),
                gruppo('I tuoi dati', [
                  voce(Icons.cloud_done_outlined, 'Backup e cloud', cloud.attivo ? 'Cloud attivo · ${cloud.esito.testo}' : 'Backup, ripristino, sincronizzazione tra dispositivi', 'dati',
                      coda: cloud.attivo ? Icon(cloud.esito.stato == 'errore' ? Icons.error_outline_rounded : Icons.check_circle_rounded, color: cloud.esito.stato == 'errore' ? cs.error : const Color(0xFF1F7A55)) : null),
                  voce(Icons.lock_outline_rounded, 'Blocco con PIN', pinImpostato(d) ? (biometriaAttiva(d) ? 'Attivo, con Face ID / impronta' : 'Attivo') : 'Non attivo', 'sicurezza'),
                  voce(Icons.inventory_2_outlined, 'Elementi archiviati', 'Ripristina o elimina definitivamente', 'archivio'),
                ]),
                gruppo('Attività', [
                  voce(Icons.storefront_outlined, 'Attività', d.nomeAttivita.isEmpty ? 'Nome, titolare, telefono' : d.nomeAttivita, 'attivita'),
                  voce(Icons.palette_outlined, 'Aspetto', 'Colore del marchio, tema chiaro o scuro', 'aspetto'),
                  voce(Icons.schedule_outlined, 'Orari di apertura', orari is Map ? 'Impostati' : 'Da impostare', 'orari'),
                  voce(Icons.beach_access_outlined, 'Pause, ferie e chiusure', '${d.conta('blocchi')} in archivio', 'blocchi'),
                ]),
                gruppo('Lavoro', [
                  voce(Icons.spa_outlined, 'Servizi e listino', '${d.conta('servizi')} servizi', 'servizi'),
                  voce(Icons.calendar_view_week_outlined, 'Agenda', 'Intervallo, tempo di pulizia, vista, colori', 'agenda'),
                  voce(Icons.groups_outlined, 'Operatrici', '${d.operatrici.length} ${d.operatrici.length == 1 ? 'operatrice' : 'operatrici'}', 'operatrici'),
                  voce(Icons.chat_outlined, 'Messaggi WhatsApp', 'Promemoria e richiamo', 'messaggi'),
                  voce(Icons.notifications_none_rounded, 'Notifiche', 'Riepilogo serale, promemoria degli appunti, prossimo appuntamento', 'notifiche'),
                  if (d.moduloAttivo('magazzino')) voce(Icons.inventory_outlined, 'Magazzino e ordini', 'Avvisi di scadenza, riordino, testo degli ordini', 'magazzino'),
                  voce(Icons.dashboard_customize_outlined, 'Funzioni attive', 'Mostra o nascondi magazzino, fornitori, appunti, report…', 'moduli'),
                ]),
                gruppo('Informazioni', [
                  if (Aggiornamenti.istanza.supportati)
                    voce(Icons.system_update_outlined, 'Aggiornamenti', Aggiornamenti.istanza.disponibile != null ? 'Nuova versione disponibile' : 'Versione $versioneApp', 'aggiornamenti',
                        coda: Aggiornamenti.istanza.disponibile != null ? Icon(Icons.fiber_new_rounded, color: cs.primary) : null),
                  voce(Icons.info_outline_rounded, 'Informazioni e privacy', 'Versione $versioneApp · note fiscali', 'info'),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/// Pagina informazioni: versione, note su privacy e adempimenti fiscali.
class PaginaInfo extends StatelessWidget {
  const PaginaInfo({super.key});
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Informazioni')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(S.l), children: [
            Text('Agenda', style: t.headlineMedium),
            Text('Versione $versioneApp · dati in formato ${comeStr(d.meta('schemaVersion'))}', style: t.bodyMedium),
            const SizedBox(height: S.l),
            const Riquadro(tipo: 'avviso', titolo: 'Adempimenti fiscali', testo: 'Questa app è un gestionale interno: non sostituisce il documento commerciale / registratore telematico né la fatturazione.'),
            const SizedBox(height: S.m),
            const Riquadro(
              titolo: 'Dove sono i tuoi dati',
              testo: 'Clienti, appuntamenti e foto restano su questo dispositivo. Se attivi il cloud, una copia cifrata (che nessuno può leggere senza la tua password) viene usata per sincronizzare gli altri dispositivi.',
            ),
            const SizedBox(height: S.m),
            const Riquadro(
              titolo: 'Privacy delle clienti (GDPR)',
              testo: 'Registra i consensi nella scheda di ogni cliente. Le avvertenze sanitarie si possono scrivere solo con il consenso ai dati sanitari. Dalla scheda puoi esportare i dati di una cliente o cancellarla (lo storico resta anonimo).',
            ),
          ]),
        ),
      ),
    );
  }
}

/// Salva una modifica della configurazione.
Future<void> modificaConfig(BuildContext context, void Function(Doc c) fn, {String? messaggio}) async {
  final d = context.dati;
  final c = clonaDoc(d.cfg);
  fn(c);
  await d.salvaConfig(c);
  if (messaggio != null && context.mounted) avviso(context, messaggio);
}

int coloreNum(dynamic hex, [int predefinito = 0xFFB4646E]) => coloreDaHex(hex) ?? predefinito;
