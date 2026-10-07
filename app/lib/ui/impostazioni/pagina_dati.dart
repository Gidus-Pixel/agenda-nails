
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/backup.dart';
import '../../dominio/cifratura.dart';
import '../../dominio/cloud.dart';
import '../../dominio/configurazione.dart';
import '../../dominio/demo.dart';
import '../../dominio/ripristino.dart';
import '../app.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../tema.dart';

/// Backup, ripristino, cloud cifrato, dati di prova, configurazione.
class PaginaDati extends StatefulWidget {
  const PaginaDati({super.key});
  @override
  State<PaginaDati> createState() => _PaginaDatiState();
}

class _PaginaDatiState extends State<PaginaDati> {
  bool _conFoto = true, _cifra = false, _occupato = false;
  String? _lavoro;

  Future<void> _conAttesa(String testo, Future<void> Function() fn) async {
    setState(() {
      _occupato = true;
      _lavoro = testo;
    });
    try {
      await fn();
    } on ErroreCloud catch (e) {
      if (mounted) avviso(context, e.messaggio, errore: true);
    } on FormatException catch (e) {
      if (mounted) avviso(context, e.message, errore: true);
    } on ErroreCifratura catch (e) {
      if (mounted) avviso(context, e.toString(), errore: true);
    } catch (e) {
      if (mounted) avviso(context, 'Errore: $e', errore: true);
    } finally {
      if (mounted) {
        setState(() {
          _occupato = false;
          _lavoro = null;
        });
      }
    }
  }

  /* ----------------------------- backup ----------------------------- */
  Future<void> _backup() async {
    final d = context.dati;
    String? password;
    if (_cifra) {
      password = await _chiediPassword(context, titolo: 'Password del backup', conferma: true, aiuto: 'Senza questa password il backup non si può aprire: annotala in un posto sicuro.');
      if (password == null) return;
    }
    if (!mounted) return;
    await _conAttesa('Preparo il backup…', () async {
      var b = await creaBackup(d, conFoto: _conFoto);
      if (password != null) b = await cifraBackup(b, password, attivita: d.nomeAttivita);
      if (!mounted) return;
      final ok = await condividiFile(context, b, nomeFileBackup(d, cifrato: password != null), tipo: password != null ? 'application/octet-stream' : 'application/json');
      if (ok) {
        await d.scriviMeta('ultimoBackup', adessoIso());
        d.aggiorna();
        if (mounted) avviso(context, 'Backup pronto (${(b.length / 1024 / 1024).toStringAsFixed(1)} MB). Conservalo fuori da questo dispositivo: iCloud Drive, Google Drive, email…');
      }
    });
  }

  Future<void> _ripristina() async {
    final d = context.dati;
    final f = await scegliFile();
    if (f == null || !mounted) return;
    var b = f.dati;
    if (leggiConfigurazione(b) != null) {
      avviso(context, 'Questo è un file di configurazione: usa "Importa configurazione".', errore: true);
      return;
    }
    if (eBackupCifrato(b)) {
      final pw = await _chiediPassword(context, titolo: 'Backup cifrato', aiuto: 'Scrivi la password scelta quando hai creato il backup.');
      if (pw == null || !mounted) return;
      Uint8List? chiaro;
      await _conAttesa('Decifro il backup…', () async => chiaro = await decifraBackup(b, pw));
      if (chiaro == null || !mounted) return;
      b = chiaro!;
    }
    late BackupLetto letto;
    try {
      letto = leggiBackup(b);
    } on FormatException catch (e) {
      avviso(context, e.message, errore: true);
      return;
    }
    final righe = [
      ('Attività', letto.attivita.isEmpty ? '—' : letto.attivita),
      ('Creato il', letto.creato == null ? '—' : F.dataOra(letto.creato)),
      ('Clienti', '${letto.conta('clienti')}'),
      ('Appuntamenti', '${letto.conta('appuntamenti')}'),
      ('Schede lavoro', '${letto.conta('schede_lavoro')}'),
      ('Foto', letto.conFoto ? '${letto.conta('foto')}' : 'non incluse (restano quelle attuali)'),
    ];
    final ok1 = await conferma(
      context,
      titolo: 'Ripristinare questo backup?',
      contenuto: Padding(
        padding: const EdgeInsets.only(top: S.s),
        child: Column(children: [
          for (final (k, v) in righe) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(v))])),
          const SizedBox(height: S.m),
          const Text('TUTTI i dati attuali di questo dispositivo verranno sostituiti da quelli del backup.'),
        ]),
      ),
      ok: 'Continua',
      pericolo: true,
    );
    if (!ok1 || !mounted) return;
    final ok2 = await conferma(context, titolo: 'Sei sicuro?', messaggio: 'Consiglio: fai prima un backup dei dati attuali, se ti servono.', ok: 'Ripristina', pericolo: true);
    if (!ok2 || !mounted) return;
    await _conAttesa('Ripristino in corso…', () async {
      await applicaBackup(d, letto);
      if (!mounted) return;
      final cloud = context.cloud;
      if (cloud.attivo) {
        final s = await sceltaTra(context, titolo: 'Cloud', messaggio: 'Vuoi che anche il cloud e gli altri dispositivi collegati passino a questi dati?', opzioni: [('no', 'No, solo qui', false), ('si', 'Sì, sostituisci nel cloud', true)]);
        if (s == 'si') await cloud.sostituisciTuttoNelCloud();
      }
      if (mounted) avviso(context, 'Backup ripristinato.');
    });
  }

  /* ----------------------------- configurazione ----------------------------- */
  Future<void> _esportaConfig() async {
    final d = context.dati;
    final b = esportaConfigurazione(d);
    final nome = norm(d.nomeAttivita).replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    await condividiFile(context, b, 'configurazione-${nome.isEmpty ? 'agenda' : nome}.json');
  }

  Future<void> _importaConfig() async {
    final d = context.dati;
    final f = await scegliFile();
    if (f == null || !mounted) return;
    final obj = leggiConfigurazione(f.dati);
    if (obj == null) {
      avviso(context, 'Questo file non è una configurazione dell\'agenda.', errore: true);
      return;
    }
    final ok = await conferma(context,
        titolo: 'Importare la configurazione?',
        messaggio: 'Attività: ${comeStr(comeDoc(comeDoc(obj['config'])['attivita'])['nome']).isEmpty ? '—' : comeDoc(comeDoc(obj['config'])['attivita'])['nome']}\nServizi nel file: ${comeListaDoc(obj['servizi']).length}\n\nLe impostazioni attuali verranno sostituite. I servizi con lo stesso nome verranno aggiornati, quelli nuovi aggiunti. Clienti e appuntamenti non vengono toccati.',
        ok: 'Importa');
    if (!ok) return;
    await importaConfigurazione(d, obj);
    if (mounted) avviso(context, 'Configurazione importata.');
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cloud = context.cloud;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup e cloud')),
      body: ListenableBuilder(
        listenable: Listenable.merge([d, cloud]),
        builder: (context, _) {
          final t = Theme.of(context).textTheme;
          final cs = Theme.of(context).colorScheme;
          final ultimo = comeStr(d.meta('ultimoBackup'));
          final demo = ciSonoDatiDemo(d);
          return Stack(children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
                  Riquadro(
                    titolo: 'Dove sono i dati',
                    testo: 'Clienti, appuntamenti e foto sono salvati su questo ${kIsWeb ? 'browser' : 'dispositivo'}: ${d.conta('clienti')} clienti, ${d.conta('appuntamenti')} appuntamenti, ${d.conta('schede_lavoro')} schede lavoro, ${d.elenco('foto', archiviati: true).length} foto. Se il dispositivo si rompe o viene perso, senza backup o cloud i dati vanno persi.',
                  ),
                  const SizedBox(height: S.l),
                  _SezioneCloud(conAttesa: _conAttesa),
                  const SizedBox(height: S.l),
                  Sezione(
                    titolo: 'Backup manuale',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(ultimo.isEmpty ? 'Nessun backup fatto da questo dispositivo.' : 'Ultimo backup: ${F.dataOra(D.daIso(ultimo))}', style: t.bodyMedium),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Includi le foto'), subtitle: const Text('Il file diventa più grande'), value: _conFoto, onChanged: (v) => setState(() => _conFoto = v)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Proteggi con password'), subtitle: const Text('Consigliato se lo invii per email o lo salvi su un cloud'), value: _cifra, onChanged: (v) => setState(() => _cifra = v)),
                      const SizedBox(height: S.s),
                      FilledButton.icon(onPressed: _occupato ? null : _backup, icon: const Icon(Icons.ios_share_rounded), label: const Text('Crea backup e salvalo'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
                      const SizedBox(height: S.s),
                      Text('Si apre la finestra di condivisione: scegli "Salva su File" (iCloud Drive), Google Drive, oppure invialo a te stessa per email.', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  const SizedBox(height: S.l),
                  Sezione(
                    titolo: 'Ripristina un backup',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Funziona con i backup creati su iPhone, iPad, Android o dalla versione web (anche quelli protetti da password).', style: t.bodyMedium),
                      const SizedBox(height: S.m),
                      OutlinedButton.icon(onPressed: _occupato ? null : _ripristina, icon: const Icon(Icons.restore_rounded), label: const Text('Scegli il file di backup')),
                    ]),
                  ),
                  const SizedBox(height: S.l),
                  _SezionePuntiRipristino(conAttesa: _conAttesa, occupato: _occupato),
                  const SizedBox(height: S.l),
                  Sezione(
                    titolo: 'Dati di prova',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text(demo ? 'Sono presenti dati di prova (clienti "Prova", appuntamenti di esempio). Rimuovili prima di iniziare a lavorare davvero.' : 'Per provare l\'app senza inserire dati veri. Si rimuovono con un tocco.', style: t.bodyMedium),
                      const SizedBox(height: S.m),
                      if (!demo)
                        OutlinedButton.icon(
                          onPressed: () async {
                            await caricaDatiDemo(d, configura: true);
                            if (context.mounted) avviso(context, 'Dati di prova caricati.');
                          },
                          icon: const Icon(Icons.science_outlined),
                          label: const Text('Carica dati di prova'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: () async {
                            final ok = await conferma(context, titolo: 'Rimuovere i dati di prova?', messaggio: 'Vengono cancellati tutti i dati segnati come prova e le clienti "Prova" con i loro appuntamenti. I tuoi dati veri non vengono toccati.', ok: 'Rimuovi', pericolo: true);
                            if (!ok) return;
                            await rimuoviDatiDemo(d);
                            if (context.mounted) avviso(context, 'Dati di prova rimossi.');
                          },
                          icon: Icon(Icons.delete_sweep_outlined, color: cs.error),
                          label: Text('Rimuovi dati di prova', style: TextStyle(color: cs.error)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: S.l),
                  Sezione(
                    titolo: 'Configurazione',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Solo impostazioni e listino, senza clienti: serve a preparare la stessa configurazione su un altro dispositivo o per un\'altra attività.', style: t.bodyMedium),
                      const SizedBox(height: S.m),
                      Row(children: [
                        Expanded(child: OutlinedButton(onPressed: _esportaConfig, child: const Text('Esporta'))),
                        const SizedBox(width: S.s),
                        Expanded(child: OutlinedButton(onPressed: _importaConfig, child: const Text('Importa'))),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
            if (_occupato)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(S.xl),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [const CircularProgressIndicator(), const SizedBox(height: S.l), Text(_lavoro ?? 'Attendi…')]),
                      ),
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

/// Chiede una password (con conferma facoltativa).
Future<String?> _chiediPassword(BuildContext context, {required String titolo, bool conferma = false, String? aiuto, int minimo = 8}) {
  final a = TextEditingController(), b = TextEditingController();
  String? errore;
  var visibile = false;
  return showDialog<String>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: Text(titolo),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (aiuto != null) Padding(padding: const EdgeInsets.only(bottom: S.m), child: Text(aiuto)),
          TextField(
            controller: a,
            obscureText: !visibile,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(onPressed: () => set(() => visibile = !visibile), icon: Icon(visibile ? Icons.visibility_off_outlined : Icons.visibility_outlined))),
          ),
          if (conferma) ...[
            const SizedBox(height: S.s),
            TextField(controller: b, obscureText: !visibile, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Ripeti la password')),
          ],
          if (errore != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text(errore!, style: TextStyle(color: Theme.of(c).colorScheme.error))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
          FilledButton(
            onPressed: () {
              if (conferma && a.text.length < minimo) return set(() => errore = 'Usa almeno $minimo caratteri.');
              if (conferma && a.text != b.text) return set(() => errore = 'Le due password non coincidono.');
              if (a.text.isEmpty) return set(() => errore = 'Scrivi la password.');
              Navigator.pop(c, a.text);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
}

/* ================================ CLOUD ================================ */
class _SezioneCloud extends StatelessWidget {
  const _SezioneCloud({required this.conAttesa});
  final Future<void> Function(String, Future<void> Function()) conAttesa;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final cloud = context.cloud;
    final t = Theme.of(context).textTheme;
    final s = cloud.stato;

    if (!cloud.configurato) {
      return Sezione(
        titolo: 'Backup automatico nel cloud',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Salva da solo, ogni pochi minuti, una copia cifrata dei dati e tiene allineati iPhone, iPad, computer. La password la conosci solo tu: senza, nessuno può leggere i dati (nemmeno noi).'),
          const SizedBox(height: S.m),
          FilledButton.icon(onPressed: () => _attiva(context), icon: const Icon(Icons.cloud_upload_outlined), label: const Text('Attiva il cloud'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50))),
          const SizedBox(height: S.s),
          OutlinedButton.icon(onPressed: () => _collega(context), icon: const Icon(Icons.devices_rounded), label: const Text('Collega a un cloud già attivo')),
        ]),
      );
    }
    if (comeBool(s['serveNuovaPassword'])) {
      return Sezione(
        titolo: 'Cloud: serve la password',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Riquadro(tipo: 'avviso', testo: 'La password del cloud è stata cambiata (o il collegamento non è finito). Scrivi la password attuale per riprendere la sincronizzazione.'),
          const SizedBox(height: S.m),
          FilledButton(onPressed: () => _nuovaPassword(context), child: const Text('Inserisci la password')),
          TextButton(onPressed: () => _scollega(context), child: const Text('Scollega questo dispositivo')),
        ]),
      );
    }
    if (comeBool(s['scollegato']) || !cloud.attivo) {
      return Sezione(
        titolo: 'Cloud',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Riquadro(tipo: 'pericolo', testo: 'Questo dispositivo è stato scollegato dal cloud (da un altro dispositivo o perché la licenza è sospesa). I dati qui restano.'),
          const SizedBox(height: S.m),
          OutlinedButton(onPressed: () => _scollega(context, remoto: false), child: const Text('Rimuovi il collegamento e ricomincia')),
        ]),
      );
    }
    final errore = cloud.esito.stato == 'errore' || cloud.esito.stato == 'offline';
    return Sezione(
      titolo: 'Cloud attivo',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(errore ? Icons.cloud_off_rounded : (cloud.esito.stato == 'sync' ? Icons.cloud_sync_rounded : Icons.cloud_done_rounded), color: errore ? Theme.of(context).colorScheme.error : const Color(0xFF1F7A55)),
          const SizedBox(width: S.s),
          Expanded(child: Text(cloud.esito.testo.isEmpty ? 'Attivo' : cloud.esito.testo, style: t.titleSmall)),
        ]),
        if (s['ultimaSync'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ultima sincronizzazione riuscita: ${F.dataOra(D.daIso(comeStr(s['ultimaSync'])))}', style: t.bodySmall)),
        const SizedBox(height: S.m),
        FilledButton.tonalIcon(
          onPressed: () => conAttesa('Sincronizzo…', () async {
            final r = await cloud.sincronizza(manuale: true);
            if (context.mounted && r != null) avviso(context, 'Fatto: ${r['ricevuti']} ricevuti, ${r['inviati']} inviati.');
          }),
          icon: const Icon(Icons.sync_rounded),
          label: const Text('Sincronizza ora'),
        ),
        const SizedBox(height: S.s),
        OutlinedButton.icon(onPressed: () => _codice(context), icon: const Icon(Icons.qr_code_2_rounded), label: const Text('Collega un altro dispositivo')),
        const SizedBox(height: S.s),
        OutlinedButton.icon(onPressed: () => _dispositivi(context), icon: const Icon(Icons.devices_other_rounded), label: const Text('Dispositivi collegati')),
        const SizedBox(height: S.s),
        OutlinedButton.icon(onPressed: () => _cambiaPassword(context), icon: const Icon(Icons.password_rounded), label: const Text('Cambia la password del cloud')),
        TextButton(onPressed: () => _scollega(context), child: Text('Scollega questo dispositivo', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Text('Spazio ${comeStr(s['spazioId']).isEmpty ? '' : comeStr(s['spazioId']).substring(0, comeStr(s['spazioId']).length.clamp(0, 8))} · ${d.nomeAttivita}', style: t.bodySmall),
      ]),
    );
  }

  String _nomeDispositivo(BuildContext context) => switch (Theme.of(context).platform) {
        TargetPlatform.iOS => MediaQuery.sizeOf(context).shortestSide >= 600 ? 'iPad' : 'iPhone',
        TargetPlatform.android => MediaQuery.sizeOf(context).shortestSide >= 600 ? 'Tablet Android' : 'Telefono Android',
        _ => 'Browser',
      };

  Future<Map<String, String>?> _modulo(BuildContext context, {required String titolo, required List<(String chiave, String etichetta, String iniziale, bool segreto)> campi, String? testo, String ok = 'Continua'}) {
    final ctr = {for (final c in campi) c.$1: TextEditingController(text: c.$3)};
    return showDialog<Map<String, String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titolo),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (testo != null) Padding(padding: const EdgeInsets.only(bottom: S.m), child: Text(testo)),
            for (final f in campi)
              Padding(
                padding: const EdgeInsets.only(bottom: S.s),
                child: TextField(controller: ctr[f.$1], obscureText: f.$4, autocorrect: false, enableSuggestions: !f.$4, decoration: InputDecoration(labelText: f.$2)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(c, {for (final e in ctr.entries) e.key: e.value.text.trim()}), child: Text(ok)),
        ],
      ),
    );
  }

  Future<void> _attiva(BuildContext context) async {
    final d = context.dati;
    final cloud = context.cloud;
    final m = await _modulo(context, titolo: 'Attiva il cloud', testo: 'Ti servono l\'indirizzo del servizio e il codice di licenza che hai ricevuto. Scegli una password lunga (almeno 10 caratteri): se la dimentichi i dati nel cloud non si recuperano, ma restano su questo dispositivo.', campi: [
      ('url', 'Indirizzo del servizio', cloud.url, false),
      ('licenza', 'Codice di licenza', '', false),
      ('pw', 'Password del cloud', '', true),
      ('pw2', 'Ripeti la password', '', true),
      ('nome', 'Nome di questo dispositivo', _nomeDispositivo(context), false),
    ]);
    if (m == null || !context.mounted) return;
    if ((m['url'] ?? '').isEmpty || (m['licenza'] ?? '').isEmpty) return avviso(context, 'Servono indirizzo e codice di licenza.', errore: true);
    if ((m['pw'] ?? '').length < 10) return avviso(context, 'La password deve avere almeno 10 caratteri.', errore: true);
    if (m['pw'] != m['pw2']) return avviso(context, 'Le due password non coincidono.', errore: true);
    await conAttesa('Attivo il cloud e carico i dati…', () async {
      await cloud.attiva(base: m['url']!, licenza: m['licenza']!, password: m['pw']!, nome: m['nome']!.isEmpty ? _nomeDispositivo(context) : m['nome']!);
      d.aggiorna();
      if (context.mounted) avviso(context, 'Cloud attivo: i dati sono al sicuro e si sincronizzano da soli.');
    });
  }

  Future<void> _collega(BuildContext context) async {
    final d = context.dati;
    final cloud = context.cloud;
    final m = await _modulo(context, titolo: 'Collega questo dispositivo', testo: 'Sul dispositivo già collegato apri Altro → Backup e cloud → "Collega un altro dispositivo" e scrivi qui il codice che compare.', campi: [
      ('url', 'Indirizzo del servizio', cloud.url, false),
      ('codice', 'Codice di collegamento', '', false),
      ('pw', 'Password del cloud', '', true),
      ('nome', 'Nome di questo dispositivo', _nomeDispositivo(context), false),
    ]);
    if (m == null || !context.mounted) return;
    var giusta = false;
    await conAttesa('Collego…', () async {
      giusta = await cloud.collega(base: m['url']!, codice: m['codice']!.replaceAll(RegExp(r'\s'), '').toUpperCase(), password: m['pw']!, nome: m['nome']!.isEmpty ? _nomeDispositivo(context) : m['nome']!);
    });
    if (!context.mounted || !cloud.configurato) return;
    if (!giusta) {
      avviso(context, 'Password errata: riprova da "Inserisci la password".', errore: true);
      return;
    }
    await _completa(context, d.conta('clienti') + d.conta('appuntamenti') > 0);
  }

  Future<void> _completa(BuildContext context, bool ciSonoDati) async {
    final cloud = context.cloud;
    var unisci = false;
    if (ciSonoDati) {
      final s = await sceltaTra(context, titolo: 'Ci sono già dei dati qui', messaggio: 'Su questo dispositivo ci sono già dati. Cosa vuoi fare?', opzioni: [
        ('unisci', 'Uniscili a quelli del cloud', false),
        ('sostituisci', 'Usa solo quelli del cloud', true),
      ]);
      if (s == null) return;
      unisci = s == 'unisci';
    }
    if (!context.mounted) return;
    await conAttesa('Scarico i dati dal cloud…', () async {
      await cloud.completaCollegamento(unisci: unisci);
      if (context.mounted) avviso(context, 'Dispositivo collegato.');
    });
  }

  Future<void> _nuovaPassword(BuildContext context) async {
    final d = context.dati;
    final cloud = context.cloud;
    final pw = await _chiediPassword(context, titolo: 'Password del cloud', minimo: 1);
    if (pw == null || !context.mounted) return;
    var ok = false;
    final eraAttivo = cloud.stato['attivatoIl'] != null;
    await conAttesa('Controllo la password…', () async => ok = await cloud.impostaPassword(pw));
    if (!context.mounted) return;
    if (!ok) return avviso(context, 'Password errata.', errore: true);
    if (eraAttivo) {
      await conAttesa('Riscarico i dati con la nuova password…', () => cloud.riallineaDopoNuovaPassword());
    } else {
      await _completa(context, d.conta('clienti') + d.conta('appuntamenti') > 0);
    }
  }

  Future<void> _codice(BuildContext context) async {
    final cloud = context.cloud;
    Map<String, dynamic>? r;
    await conAttesa('Creo il codice…', () async => r = await cloud.codiceCollegamento());
    if (r == null || !context.mounted) return;
    final scade = comeStr(r!['scade']).isEmpty ? null : D.daIso(comeStr(r!['scade']));
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Codice di collegamento'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Sull\'altro dispositivo apri l\'app → Altro → Backup e cloud → "Collega a un cloud già attivo" e scrivi:'),
          const SizedBox(height: S.l),
          SelectableText(comeStr(r!['codice']), style: Theme.of(c).textTheme.displaySmall?.copyWith(letterSpacing: 4, fontFeatures: const [FontFeature.tabularFigures()])),
          if (scade != null) Padding(padding: const EdgeInsets.only(top: S.s), child: Text('Valido fino alle ${D.hhmm(scade)}')),
          const SizedBox(height: S.s),
          const Text('Servirà anche la password del cloud.'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fatto'))],
      ),
    );
  }

  Future<void> _dispositivi(BuildContext context) async {
    final cloud = context.cloud;
    Map<String, dynamic>? info;
    await conAttesa('Carico…', () async => info = await cloud.info());
    if (info == null || !context.mounted) return;
    final lista = comeListaDoc(info!['dispositivi']);
    final mio = comeStr(cloud.stato['dispositivoId']);
    await showModalBottomSheet<void>(
      context: context,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(S.l, 0, S.l, S.l), children: [
          Text('Dispositivi collegati', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: S.s),
          for (final x in lista)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.smartphone_rounded),
              title: Text('${comeStr(x['nome']).isEmpty ? 'Dispositivo' : x['nome']}${x['id'] == mio ? ' (questo)' : ''}'),
              subtitle: Text(comeStr(x['ultimo']).isEmpty ? '' : 'Ultimo accesso ${F.dataOra(D.daIso(comeStr(x['ultimo'])))}'),
              trailing: x['id'] == mio
                  ? null
                  : TextButton(
                      onPressed: () async {
                        Navigator.pop(c);
                        final ok = await conferma(context, titolo: 'Scollegare ${x['nome']}?', messaggio: 'Non riceverà più i dati dal cloud. I dati già presenti su quel dispositivo restano lì.', ok: 'Scollega', pericolo: true);
                        if (ok) await conAttesa('Scollego…', () => cloud.revoca(comeStr(x['id'])));
                      },
                      child: const Text('Scollega'),
                    ),
            ),
        ]),
      ),
    );
  }

  Future<void> _cambiaPassword(BuildContext context) async {
    final cloud = context.cloud;
    final pw = await _chiediPassword(context, titolo: 'Nuova password del cloud', conferma: true, minimo: 10, aiuto: 'Gli altri dispositivi ti chiederanno la nuova password. Annotala in un posto sicuro.');
    if (pw == null || !context.mounted) return;
    await conAttesa('Cifro di nuovo tutti i dati…', () async {
      await cloud.cambiaPassword(pw);
      if (context.mounted) avviso(context, 'Password cambiata.');
    });
  }

  Future<void> _scollega(BuildContext context, {bool remoto = true}) async {
    final cloud = context.cloud;
    final ok = await conferma(context, titolo: 'Scollegare questo dispositivo?', messaggio: 'Smette di sincronizzarsi. I dati presenti qui restano, e restano anche nel cloud per gli altri dispositivi.', ok: 'Scollega', pericolo: true);
    if (!ok || !context.mounted) return;
    await conAttesa('Scollego…', () => cloud.scollega(remoto: remoto));
  }
}

/// Punti di ripristino automatici (una copia al giorno + prima delle operazioni in blocco).
class _SezionePuntiRipristino extends StatefulWidget {
  const _SezionePuntiRipristino({required this.conAttesa, required this.occupato});
  final Future<void> Function(String, Future<void> Function()) conAttesa;
  final bool occupato;
  @override
  State<_SezionePuntiRipristino> createState() => _SezionePuntiRipristinoState();
}

class _SezionePuntiRipristinoState extends State<_SezionePuntiRipristino> {
  List<Doc>? _copie;
  bool _tutte = false;

  @override
  void initState() {
    super.initState();
    copieCambiate.addListener(_carica);
    _carica();
  }

  @override
  void dispose() {
    copieCambiate.removeListener(_carica);
    super.dispose();
  }

  Future<void> _carica() async {
    try {
      final c = await elencoCopie();
      if (mounted) setState(() => _copie = c);
    } catch (_) {
      if (mounted) setState(() => _copie = const []);
    }
  }

  String _conteggi(Doc c) {
    final n = comeDoc(c['conteggi']);
    return '${n['clienti'] ?? 0} clienti · ${n['appuntamenti'] ?? 0} appuntamenti · ${n['schede'] ?? 0} schede · ${n['prodotti'] ?? 0} prodotti · ${n['appunti'] ?? 0} appunti';
  }

  Future<void> _ripristina(Doc c) async {
    final d = context.dati;
    final quando = F.dataOra(D.daIso(comeStr(c['creata'])));
    final ok = await conferma(
      context,
      titolo: 'Tornare a questo punto di ripristino?',
      contenuto: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('$quando — ${motiviCopia[c['motivo']] ?? c['motivo']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(_conteggi(c)),
        const SizedBox(height: S.m),
        const Riquadro(tipo: 'avviso', testo: 'Le modifiche fatte dopo andranno perse. Prima di procedere l\'app salva in automatico la situazione attuale, così puoi tornare indietro. Le foto non cambiano.'),
      ]),
      ok: 'Ripristina',
      pericolo: true,
    );
    if (!ok || !mounted) return;
    await widget.conAttesa('Ripristino in corso…', () async {
      final fatto = await ripristinaCopia(d, comeStr(c['id']));
      if (!mounted) return;
      if (!fatto) {
        avviso(context, 'Punto di ripristino non trovato.', errore: true);
        return;
      }
      final cloud = context.cloud;
      if (cloud.attivo) {
        final s = await sceltaTra(context, titolo: 'Cloud', messaggio: 'Vuoi che anche il cloud e gli altri dispositivi collegati tornino a questi dati?', opzioni: [('no', 'No, solo qui', false), ('si', 'Sì, anche nel cloud', true)]);
        if (s == 'si') await cloud.sostituisciTuttoNelCloud();
      }
      if (mounted) avviso(context, 'Dati riportati al $quando.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final copie = _copie;
    final visibili = copie == null ? const <Doc>[] : (_tutte ? copie : copie.take(4).toList());
    return Sezione(
      titolo: 'Punti di ripristino',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          kIsWeb
              ? 'Nell\'anteprima web i punti di ripristino durano finché la pagina resta aperta.'
              : 'Ogni giorno l\'app salva da sola una copia dei dati su questo dispositivo (ultime ${maxCopie['giornaliera']}), e un\'altra prima di ogni ripristino o pulizia. Serve a rimediare agli errori, per esempio una cancellazione sbagliata. Non sostituisce il backup: se il dispositivo si rompe o viene perso, anche queste copie si perdono. Le foto non sono incluse.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: S.s),
        if (copie == null)
          const Padding(padding: EdgeInsets.all(S.m), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))))
        else if (copie.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: S.s), child: Text('Ancora nessun punto di ripristino.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)))
        else
          for (final c in visibili)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (comeStr(c['motivo'])) { 'giornaliera' => Icons.event_repeat_rounded, 'prima' => Icons.shield_outlined, _ => Icons.bookmark_border_rounded }, color: cs.primary),
              title: Text(F.dataOra(D.daIso(comeStr(c['creata'])))),
              subtitle: Text('${motiviCopia[c['motivo']] ?? c['motivo']}\n${_conteggi(c)}'),
              isThreeLine: true,
              trailing: TextButton(onPressed: widget.occupato ? null : () => _ripristina(c), child: const Text('Ripristina')),
            ),
        if (copie != null && copie.length > 4)
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => _tutte = !_tutte), child: Text(_tutte ? 'Mostra meno' : 'Mostra tutti (${copie.length})'))),
        const SizedBox(height: S.s),
        OutlinedButton.icon(
          onPressed: widget.occupato
              ? null
              : () async {
                  final d = context.dati;
                  try {
                    await creaCopia(d, 'manuale');
                    if (context.mounted) avviso(context, 'Punto di ripristino creato.');
                  } catch (e) {
                    if (context.mounted) avviso(context, 'Non è stato possibile crearlo: $e', errore: true);
                  }
                },
          icon: const Icon(Icons.add_task_rounded),
          label: const Text('Crea un punto di ripristino adesso'),
        ),
      ]),
    );
  }
}
