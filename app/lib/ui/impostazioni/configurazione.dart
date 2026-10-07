import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../../dominio/sicurezza.dart';
import '../../servizi/biometria.dart';
import '../../servizi/notifiche.dart';
import '../app.dart';
import '../blocco.dart';
import '../comuni.dart';
import '../tema.dart';
import 'pagina_altro.dart';

/// Struttura comune delle pagine di impostazione con pulsante Salva.
class _PaginaModulo extends StatelessWidget {
  const _PaginaModulo({required this.titolo, required this.figli, required this.suSalva});
  final String titolo;
  final List<Widget> figli;
  final Future<void> Function() suSalva;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titolo), actions: [
        Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: suSalva, child: const Text('Salva'))),
      ]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              ...figli,
              const SizedBox(height: S.l),
              FilledButton(onPressed: suSalva, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Salva')),
            ]),
          ),
        ),
      ),
    );
  }
}

/* ============================ Attività ============================ */
class PaginaAttivita extends StatefulWidget {
  const PaginaAttivita({super.key});
  @override
  State<PaginaAttivita> createState() => _PaginaAttivitaState();
}

class _PaginaAttivitaState extends State<PaginaAttivita> {
  final _nome = TextEditingController(), _tit = TextEditingController(), _citta = TextEditingController(), _tel = TextEditingController(), _pref = TextEditingController();

  @override
  void initState() {
    super.initState();
    final a = comeDoc(Ambito.of(context).dati.cfg['attivita']);
    _nome.text = comeStr(a['nome']);
    _tit.text = comeStr(a['titolare']);
    _citta.text = comeStr(a['citta']);
    _tel.text = comeStr(a['telefono']);
    _pref.text = comeStr(a['prefissoInternazionale']).isEmpty ? '39' : comeStr(a['prefissoInternazionale']);
  }

  @override
  void dispose() {
    for (final c in [_nome, _tit, _citta, _tel, _pref]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salva() async {
    final pref = _pref.text.replaceAll(RegExp(r'\D'), '');
    await modificaConfig(context, (c) {
      c['attivita'] = {
        ...comeDoc(c['attivita']),
        'nome': _nome.text.trim(),
        'titolare': _tit.text.trim(),
        'citta': _citta.text.trim(),
        'telefono': _tel.text.trim().isEmpty ? '' : normalizzaTelefono(_tel.text, prefisso: pref.isEmpty ? '39' : pref),
        'prefissoInternazionale': pref.isEmpty ? '39' : pref,
      };
    });
    if (mounted) {
      Navigator.pop(context);
      avvisa('Dati dell\'attività salvati');
    }
  }

  @override
  Widget build(BuildContext context) => _PaginaModulo(titolo: 'Attività', suSalva: _salva, figli: [
        Campo(etichetta: 'Nome dell\'attività', controller: _nome, maiuscole: TextCapitalization.words, aiuto: 'Compare nei messaggi alle clienti ({attivita}).'),
        Campo(etichetta: 'Titolare', controller: _tit, maiuscole: TextCapitalization.words),
        Campo(etichetta: 'Città', controller: _citta, maiuscole: TextCapitalization.words),
        Campo(etichetta: 'Telefono / WhatsApp dell\'attività', controller: _tel, tastiera: TextInputType.phone),
        Campo(etichetta: 'Prefisso internazionale predefinito', controller: _pref, tastiera: TextInputType.number, aiuto: 'Aggiunto ai numeri delle clienti scritti senza prefisso (Italia: 39).'),
      ]);
}

/* ============================ Aspetto ============================ */
class PaginaAspetto extends StatelessWidget {
  const PaginaAspetto({super.key});
  static const _colori = [0xFFB4646E, 0xFFC97B84, 0xFF9C5B7A, 0xFF8E6C8A, 0xFF6B5B95, 0xFF3F6E8C, 0xFF2F7D6D, 0xFF5B8E7D, 0xFFB8860B, 0xFFC2703D, 0xFF8B5E3C, 0xFF3A2A2C];

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final attuale = coloreNum(comeDoc(d.cfg['brand'])['primario']);
        final tema = comeStr(d.cfg['tema']).isEmpty ? 'auto' : comeStr(d.cfg['tema']);
        return Scaffold(
          appBar: AppBar(title: const Text('Aspetto')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                Text('Colore del marchio', style: t.titleMedium),
                const SizedBox(height: S.m),
                Wrap(spacing: S.m, runSpacing: S.m, children: [
                  for (final c in _colori)
                    InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => modificaConfig(context, (x) => x['brand'] = {...comeDoc(x['brand']), 'primario': esadecimale(c)}),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(color: Color(c), shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: (attuale & 0xFFFFFF) == (c & 0xFFFFFF) ? 3 : 0)),
                        child: (attuale & 0xFFFFFF) == (c & 0xFFFFFF) ? Icon(Icons.check_rounded, color: Tema.testoSu(Color(c))) : null,
                      ),
                    ),
                ]),
                const SizedBox(height: S.m),
                TextFormField(
                  initialValue: esadecimale(attuale),
                  decoration: const InputDecoration(labelText: 'Oppure un codice colore (es. #C97B84)'),
                  onFieldSubmitted: (v) {
                    final n = coloreDaHex(v.trim().startsWith('#') ? v.trim() : '#${v.trim()}');
                    if (n == null) {
                      avviso(context, 'Codice colore non valido: usa il formato #RRGGBB.', errore: true);
                    } else {
                      modificaConfig(context, (x) => x['brand'] = {...comeDoc(x['brand']), 'primario': esadecimale(n)});
                    }
                  },
                ),
                const SizedBox(height: S.xl),
                Text('Tema', style: t.titleMedium),
                const SizedBox(height: S.m),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'auto', label: Text('Automatico'), icon: Icon(Icons.brightness_auto_outlined)),
                    ButtonSegment(value: 'chiaro', label: Text('Chiaro'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: 'scuro', label: Text('Scuro'), icon: Icon(Icons.dark_mode_outlined)),
                  ],
                  selected: {tema},
                  onSelectionChanged: (s) => modificaConfig(context, (x) => x['tema'] = s.first),
                ),
                const SizedBox(height: S.s),
                Text('"Automatico" segue l\'impostazione del telefono.', style: t.bodySmall),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/* ============================ Agenda ============================ */
class PaginaOpzioniAgenda extends StatelessWidget {
  const PaginaOpzioniAgenda({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final a = comeDoc(d.cfg['agenda']);
        void imposta(String k, dynamic v) => modificaConfig(context, (c) => c['agenda'] = {...comeDoc(c['agenda']), k: v});
        Widget scelte<T>(String titolo, String? aiuto, List<(T, String)> opz, T valore, String chiave) => Padding(
              padding: const EdgeInsets.only(bottom: S.xl),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(titolo, style: t.titleMedium),
                if (aiuto != null) Text(aiuto, style: t.bodySmall),
                const SizedBox(height: S.s),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final (v, txt) in opz) ChoiceChip(label: Text(txt), selected: valore == v, onSelected: (_) => imposta(chiave, v))]),
              ]),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Agenda')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                scelte<int>('Intervallo dell\'agenda', 'Passo per orari e trascinamento.', const [(5, '5 min'), (10, '10 min'), (15, '15 min'), (20, '20 min'), (30, '30 min')], d.slotMinuti, 'slotMinuti'),
                scelte<int>('Tempo di pulizia tra appuntamenti', 'Pulizia e sterilizzazione: ricevi un avviso se due appuntamenti sono troppo vicini. Si può cambiare per singolo servizio.', const [(0, 'Nessuno'), (5, '5 min'), (10, '10 min'), (15, '15 min'), (20, '20 min'), (30, '30 min')], d.cuscinettoMinuti, 'cuscinettoMinuti'),
                scelte<String>('Vista iniziale su tablet', null, const [('timeGridDay', 'Giorno'), ('timeGridWeek', 'Settimana'), ('dayGridMonth', 'Mese'), ('listWeek', 'Elenco')], comeStr(a['vistaPredefinita']), 'vistaPredefinita'),
                scelte<String>('Vista iniziale sul telefono', null, const [('timeGridDay', 'Giorno'), ('timeGridWeek', '3 giorni'), ('dayGridMonth', 'Mese'), ('listWeek', 'Elenco')], comeStr(a['vistaTelefono']), 'vistaTelefono'),
                scelte<String>('Colore degli appuntamenti', null, const [('servizio', 'Per servizio'), ('stato', 'Per stato')], comeStr(a['coloreEventiPer']).isEmpty ? 'servizio' : comeStr(a['coloreEventiPer']), 'coloreEventiPer'),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/* ============================ Operatrici ============================ */
class PaginaOperatrici extends StatelessWidget {
  const PaginaOperatrici({super.key});
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final ops = d.operatrici;
        return Scaffold(
          appBar: AppBar(title: const Text('Operatrici')),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'operatrici-nuova',
            onPressed: () => _modifica(context, null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Aggiungi'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                const Riquadro(testo: 'Se lavori da sola lascia una sola operatrice: l\'agenda resta semplice. Con più operatrici puoi filtrare l\'agenda e i conflitti si controllano per ciascuna.'),
                const SizedBox(height: S.l),
                Card(
                  child: Column(children: [
                    for (final o in ops)
                      ListTile(
                        leading: CircleAvatar(backgroundColor: Color(coloreNum(o['colore']))),
                        title: Text(comeStr(o['nome']).isEmpty ? 'Operatrice (senza nome)' : comeStr(o['nome'])),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => _modifica(context, o),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  Future<void> _modifica(BuildContext context, Doc? o) async {
    final d = context.dati;
    final nome = TextEditingController(text: comeStr(o?['nome']));
    var colore = coloreNum(o?['colore'], paletteServizi[d.operatrici.length % paletteServizi.length]);
    final esito = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(o == null ? 'Nuova operatrice' : 'Operatrice'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, decoration: const InputDecoration(labelText: 'Nome'), textCapitalization: TextCapitalization.words, autofocus: true),
            const SizedBox(height: S.m),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in paletteServizi)
                GestureDetector(
                  onTap: () => set(() => colore = p),
                  child: CircleAvatar(radius: 18, backgroundColor: Color(p), child: (p & 0xFFFFFF) == (colore & 0xFFFFFF) ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null),
                ),
            ]),
          ]),
          actions: [
            if (o != null && d.operatrici.length > 1) TextButton(onPressed: () => Navigator.pop(c, 'elimina'), child: Text('Rimuovi', style: TextStyle(color: Theme.of(c).colorScheme.error))),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
            FilledButton(onPressed: () => Navigator.pop(c, 'salva'), child: const Text('Salva')),
          ],
        ),
      ),
    );
    if (esito == null || !context.mounted) return;
    await modificaConfig(context, (c) {
      final lista = comeListaDoc(c['operatrici']);
      if (esito == 'elimina') {
        lista.removeWhere((x) => x['id'] == o!['id']);
      } else if (o == null) {
        lista.add({'id': 'op-${uid().substring(0, 8)}', 'nome': nome.text.trim(), 'colore': esadecimale(colore)});
      } else {
        final i = lista.indexWhere((x) => x['id'] == o['id']);
        if (i >= 0) lista[i] = {...lista[i], 'nome': nome.text.trim(), 'colore': esadecimale(colore)};
      }
      c['operatrici'] = lista;
    });
  }
}

/* ============================ Messaggi ============================ */
class PaginaMessaggi extends StatefulWidget {
  const PaginaMessaggi({super.key});
  @override
  State<PaginaMessaggi> createState() => _PaginaMessaggiState();
}

class _PaginaMessaggiState extends State<PaginaMessaggi> {
  final _prom = TextEditingController(), _rich = TextEditingController();

  @override
  void initState() {
    super.initState();
    final m = comeDoc(Ambito.of(context).dati.cfg['messaggi']);
    _prom.text = comeStr(m['promemoria']);
    _rich.text = comeStr(m['richiamo']);
    _prom.addListener(() => setState(() {}));
    _rich.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _prom.dispose();
    _rich.dispose();
    super.dispose();
  }

  Future<void> _salva() async {
    await modificaConfig(context, (c) => c['messaggi'] = {...comeDoc(c['messaggi']), 'promemoria': _prom.text.trim(), 'richiamo': _rich.text.trim()});
    if (mounted) {
      Navigator.pop(context);
      avvisa('Messaggi salvati');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final t = Theme.of(context).textTheme;
    final esempioApp = {'inizio': isoJs(D.combina(D.aggiungiGiorniKey(D.oggiKey(), 1), '10:30')), 'fine': isoJs(D.combina(D.aggiungiGiorniKey(D.oggiKey(), 1), '12:00')), 'servizi': [{'nome': 'Refill gel'}]};
    final v = valoriMessaggio(d, {'nome': 'Anna'}, esempioApp);
    return _PaginaModulo(titolo: 'Messaggi WhatsApp', suSalva: _salva, figli: [
      const Riquadro(testo: 'Il messaggio si apre già scritto in WhatsApp: lo controlli e lo invii tu. Segnaposto: {nome} {giorno} {ora} {servizio} {attivita}.'),
      const SizedBox(height: S.l),
      Campo(etichetta: 'Promemoria appuntamento', controller: _prom, righe: 4),
      Text('Anteprima', style: t.labelMedium),
      _Anteprima(compilaModello(_prom.text, v)),
      const SizedBox(height: S.xl),
      Campo(etichetta: 'Richiamo (clienti da ricontattare)', controller: _rich, righe: 4),
      Text('Anteprima', style: t.labelMedium),
      _Anteprima(compilaModello(_rich.text, v)),
    ]);
  }
}

class _Anteprima extends StatelessWidget {
  const _Anteprima(this.testo);
  final String testo;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 6, left: 40),
          padding: const EdgeInsets.all(S.m),
          decoration: const BoxDecoration(color: Color(0xFFDCF8C6), borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14), bottomLeft: Radius.circular(14), bottomRight: Radius.circular(4))),
          child: Text(testo, style: const TextStyle(color: Color(0xFF111B21))),
        ),
      );
}

/* ============================ Funzioni attive ============================ */
class PaginaModuli extends StatelessWidget {
  const PaginaModuli({super.key});
  static const _moduli = [
    ('agenda', 'Agenda', 'Appuntamenti, spostamenti, pause'),
    ('clienti', 'Clienti', 'Schede, preferenze, consensi'),
    ('storico', 'Storico lavori', 'Schede lavoro con foto'),
    ('magazzino', 'Magazzino', 'Prodotti, giacenze, scadenze'),
    ('fornitori', 'Fornitori', 'Anagrafica e contatti'),
    ('ordini', 'Ordini', 'Ordini ai fornitori con carico automatico (richiede il magazzino)'),
    ('appunti', 'Appunti', 'Note, promemoria, collegamenti'),
    ('report', 'Report', 'Incassi, servizi, consumi, CSV'),
  ];
  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final m = comeDoc(d.cfg['moduli']);
        return Scaffold(
          appBar: AppBar(title: const Text('Funzioni attive')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                const Riquadro(testo: 'Le funzioni spente spariscono dal menu e dal cruscotto. I dati non vengono cancellati: riaccendendole li ritrovi.'),
                const SizedBox(height: S.l),
                Card(
                  child: Column(children: [
                    for (final (k, titolo, sotto) in _moduli)
                      SwitchListTile(
                        title: Text(titolo),
                        subtitle: Text(sotto),
                        value: m[k] != false,
                        onChanged: (v) => modificaConfig(context, (c) => c['moduli'] = {...comeDoc(c['moduli']), k: v}),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/* ============================ Magazzino e ordini ============================ */
class PaginaOpzioniMagazzino extends StatefulWidget {
  const PaginaOpzioniMagazzino({super.key});
  @override
  State<PaginaOpzioniMagazzino> createState() => _PaginaOpzioniMagazzinoState();
}

class _PaginaOpzioniMagazzinoState extends State<PaginaOpzioniMagazzino> {
  late final _scad = TextEditingController(text: comeStr(comeDoc(Ambito.of(context).dati.cfg['avvisi'])['scadenzaGiorni']));
  late final _molt = TextEditingController(text: comeStr(comeDoc(Ambito.of(context).dati.cfg['magazzino'])['moltiplicatoreRiordino']));
  late final _msg = TextEditingController(text: comeStr(Ambito.of(context).dati.cfg['messaggiOrdine']));
  late final _cat = TextEditingController(text: comeListaStr(Ambito.of(context).dati.cfg['categorieProdotti']).join(', '));

  @override
  void dispose() {
    for (final c in [_scad, _molt, _msg, _cat]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _salva() async {
    await modificaConfig(context, (c) {
      c['avvisi'] = {...comeDoc(c['avvisi']), 'scadenzaGiorni': (int.tryParse(_scad.text.trim()) ?? 30).clamp(1, 365)};
      c['magazzino'] = {...comeDoc(c['magazzino']), 'moltiplicatoreRiordino': (int.tryParse(_molt.text.trim()) ?? 2).clamp(1, 20)};
      c['messaggiOrdine'] = _msg.text.trim();
      final cat = _cat.text.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toSet().toList();
      if (cat.isNotEmpty) c['categorieProdotti'] = cat;
    });
    if (mounted) {
      Navigator.pop(context);
      avvisa('Impostazioni del magazzino salvate');
    }
  }

  @override
  Widget build(BuildContext context) => _PaginaModulo(titolo: 'Magazzino e ordini', suSalva: _salva, figli: [
        Campo(etichetta: 'Avviso di scadenza (giorni prima)', controller: _scad, tastiera: TextInputType.number),
        Campo(etichetta: 'Riordino: porta la giacenza a N volte la scorta minima', controller: _molt, tastiera: TextInputType.number),
        Campo(etichetta: 'Inizio del messaggio d\'ordine', controller: _msg, righe: 3, aiuto: 'Segnaposto: {attivita} {fornitore} {referente}'),
        Campo(etichetta: 'Categorie dei prodotti (separate da virgola)', controller: _cat, righe: 4, maiuscole: TextCapitalization.none),
      ]);
}

/* ============================ Blocco con PIN e Face ID ============================ */
class PaginaSicurezza extends StatefulWidget {
  const PaginaSicurezza({super.key});
  @override
  State<PaginaSicurezza> createState() => _PaginaSicurezzaState();
}

class _PaginaSicurezzaState extends State<PaginaSicurezza> {
  String? _bio;

  @override
  void initState() {
    super.initState();
    Biometria.disponibile().then((n) {
      if (mounted) setState(() => _bio = n);
    });
  }

  /// Chiede uno o più PIN in una finestra. Restituisce i valori o null.
  Future<List<String>?> _chiedi(String titolo, List<String> etichette, {String? nota}) {
    final ctr = [for (final _ in etichette) TextEditingController()];
    return showDialog<List<String>>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titolo),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (nota != null) Padding(padding: const EdgeInsets.only(bottom: S.m), child: Text(nota)),
          for (var i = 0; i < etichette.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: S.s),
              child: TextField(
                controller: ctr[i],
                autofocus: i == 0,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: etichette[i], counterText: ''),
              ),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(c, [for (final x in ctr) x.text]), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _imposta({required bool cambio}) async {
    final d = context.dati;
    final v = await _chiedi(cambio ? 'Cambia PIN' : 'Imposta un PIN', [if (cambio) 'PIN attuale', cambio ? 'Nuovo PIN (4–8 cifre)' : 'PIN (4–8 cifre)', 'Ripeti il PIN'],
        nota: cambio ? null : 'Lo chiederà l\'app all\'apertura e quando ci torni dopo un po\'. Annotalo in un posto sicuro.');
    if (v == null || !mounted) return;
    final i = cambio ? 1 : 0;
    if (cambio && !await verificaPin(d, v[0])) {
      if (mounted) avviso(context, 'PIN attuale errato.', errore: true);
      return;
    }
    if (!pinValido(v[i])) {
      if (mounted) avviso(context, 'Il PIN deve avere da 4 a 8 cifre.', errore: true);
      return;
    }
    if (v[i] != v[i + 1]) {
      if (mounted) avviso(context, 'I due PIN non coincidono.', errore: true);
      return;
    }
    await impostaPin(d, v[i]);
    if (mounted) avviso(context, cambio ? 'PIN cambiato' : 'PIN impostato: l\'agenda si bloccherà quando esci.');
  }

  Future<void> _rimuovi() async {
    final d = context.dati;
    final v = await _chiedi('Rimuovi il PIN', ['PIN attuale']);
    if (v == null || !mounted) return;
    if (!await verificaPin(d, v[0])) {
      if (mounted) avviso(context, 'PIN errato.', errore: true);
      return;
    }
    await rimuoviPin(d);
    if (mounted) avviso(context, 'PIN rimosso');
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final attivo = pinImpostato(d);
        final minuti = minutiBlocco(d);
        return Scaffold(
          appBar: AppBar(title: const Text('Blocco con PIN')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                const Riquadro(
                  titolo: 'Cosa fa',
                  testo: 'Blocca l\'agenda all\'apertura e quando ci torni dopo un po\', così chi prende in mano il telefono o il tablet non vede clienti e incassi. Nel multitasking l\'anteprima resta coperta. Il PIN vale solo su questo dispositivo.',
                ),
                const SizedBox(height: S.l),
                if (!attivo)
                  FilledButton.icon(onPressed: () => _imposta(cambio: false), icon: const Icon(Icons.lock_outline_rounded), label: const Text('Imposta un PIN'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)))
                else ...[
                  Card(
                    child: Column(children: [
                      if (_bio != null)
                        SwitchListTile(
                          secondary: Icon(_bio == 'Face ID' ? Icons.face_retouching_natural_rounded : Icons.fingerprint_rounded),
                          title: Text('Sblocca con $_bio'),
                          subtitle: const Text('Il PIN resta come alternativa'),
                          value: biometriaAttiva(d),
                          onChanged: (v) async {
                            if (v && !await Biometria.verifica('Attiva lo sblocco con $_bio')) return;
                            await impostaBiometria(d, v);
                          },
                        )
                      else
                        const ListTile(leading: Icon(Icons.fingerprint_rounded), title: Text('Face ID / impronta'), subtitle: Text('Non disponibile o non configurato su questo dispositivo')),
                      const Divider(indent: 16),
                      ListTile(leading: const Icon(Icons.password_rounded), title: const Text('Cambia PIN'), trailing: const Icon(Icons.chevron_right_rounded), onTap: () => _imposta(cambio: true)),
                      const Divider(indent: 16),
                      ListTile(leading: const Icon(Icons.lock_rounded), title: const Text('Blocca adesso'), onTap: () => bloccoAttivo.value = true),
                    ]),
                  ),
                  const SizedBox(height: S.l),
                  Text('Chiedi il PIN quando torno nell\'app dopo', style: t.titleMedium),
                  const SizedBox(height: S.s),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final (m, txt) in const [(0, 'Subito'), (1, '1 minuto'), (5, '5 minuti'), (15, '15 minuti'), (60, '1 ora')])
                      ChoiceChip(label: Text(txt), selected: minuti == m, onSelected: (_) => modificaConfig(context, (c) => c['sicurezza'] = {...comeDoc(c['sicurezza']), 'bloccoAppMinuti': m})),
                  ]),
                  const SizedBox(height: S.xl),
                  OutlinedButton.icon(onPressed: _rimuovi, icon: Icon(Icons.lock_open_rounded, color: Theme.of(context).colorScheme.error), label: Text('Rimuovi il PIN', style: TextStyle(color: Theme.of(context).colorScheme.error))),
                ],
                const SizedBox(height: S.l),
                Text('Il PIN non cifra i dati sul dispositivo: per proteggere le copie fuori dal dispositivo usa il backup con password o il cloud cifrato. Se dimentichi il PIN, reinstalla l\'app e ripristina un backup (o ricollegati al cloud).', style: t.bodySmall),
              ]),
            ),
          ),
        );
      },
    );
  }
}

/* ============================ Notifiche ============================ */
class PaginaNotifiche extends StatefulWidget {
  const PaginaNotifiche({super.key});
  @override
  State<PaginaNotifiche> createState() => _PaginaNotificheState();
}

class _PaginaNotificheState extends State<PaginaNotifiche> {
  int? _programmate;

  @override
  void initState() {
    super.initState();
    _conta();
  }

  Future<void> _conta() async {
    final n = await Notifiche.istanza.quanteProgrammate();
    if (mounted) setState(() => _programmate = n);
  }

  Future<void> _imposta(String k, dynamic v) async {
    final d = context.dati;
    await modificaConfig(context, (c) => c['notifiche'] = {...comeDoc(c['notifiche']), k: v});
    await Notifiche.istanza.riprogramma(d);
    await _conta();
  }

  Future<void> _ora(String k, String attuale) async {
    final m = D.minDaHHMM(attuale);
    final o = await scegliOra(context, TimeOfDay(hour: m ~/ 60, minute: m % 60));
    if (o != null) await _imposta(k, '${D.p2(o.hour)}:${D.p2(o.minute)}');
  }

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final t = Theme.of(context).textTheme;
        final op = OpzioniNotifiche(d.cfg);
        final ok = Notifiche.istanza.supportate;
        return Scaffold(
          appBar: AppBar(title: const Text('Notifiche')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                Riquadro(
                  tipo: ok ? 'info' : 'avviso',
                  testo: ok
                      ? 'Le notifiche sono preparate dall\'app sul dispositivo: funzionano anche senza internet e si aggiornano da sole quando cambi l\'agenda. ${_programmate == null ? '' : 'Ora ne sono in programma $_programmate.'}'
                      : 'Le notifiche sono disponibili nell\'app per iPhone, iPad e Android.',
                  azioni: [
                    if (ok)
                      FilledButton.tonal(
                        onPressed: () async {
                          final si = await Notifiche.istanza.chiediPermesso();
                          await d.scriviMeta('notificheChieste', true);
                          if (!context.mounted) return;
                          if (si) {
                            await Notifiche.istanza.prova();
                            await Notifiche.istanza.riprogramma(d);
                            await _conta();
                          } else {
                            avviso(context, 'Permesso negato: puoi attivarle da Impostazioni del telefono → Notifiche → Agenda.', errore: true);
                          }
                        },
                        child: const Text('Consenti e prova'),
                      ),
                  ],
                ),
                const SizedBox(height: S.l),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      title: const Text('Riepilogo la sera prima'),
                      subtitle: Text('Quanti appuntamenti ci sono domani e chi è la prima · alle ${op.oraRiepilogo}'),
                      value: op.riepilogo,
                      onChanged: (v) => _imposta('riepilogoSerale', v),
                    ),
                    if (op.riepilogo) ListTile(contentPadding: const EdgeInsets.only(left: 32, right: 16), title: const Text('Orario del riepilogo'), trailing: Text(op.oraRiepilogo, style: t.titleMedium), onTap: () => _ora('oraRiepilogo', op.oraRiepilogo)),
                    const Divider(indent: 16),
                    SwitchListTile(
                      title: const Text('Promemoria degli appunti'),
                      subtitle: Text('Il giorno indicato nell\'appunto · alle ${op.oraAppunti}'),
                      value: op.appunti,
                      onChanged: (v) => _imposta('promemoriaAppunti', v),
                    ),
                    if (op.appunti) ListTile(contentPadding: const EdgeInsets.only(left: 32, right: 16), title: const Text('Orario dei promemoria'), trailing: Text(op.oraAppunti, style: t.titleMedium), onTap: () => _ora('oraPromemoria', op.oraAppunti)),
                    const Divider(indent: 16),
                    SwitchListTile(
                      title: const Text('Avvisi di magazzino'),
                      subtitle: const Text('Prodotti da riordinare, in scadenza o aperti da troppo'),
                      value: op.magazzino,
                      onChanged: (v) => _imposta('magazzino', v),
                    ),
                  ]),
                ),
                const SizedBox(height: S.l),
                Text('Avviso prima di ogni appuntamento', style: t.titleMedium),
                const SizedBox(height: S.s),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final (m, txt) in const [(0, 'No'), (10, '10 min prima'), (15, '15 min prima'), (30, '30 min prima'), (60, '1 ora prima')])
                    ChoiceChip(label: Text(txt), selected: op.primaMinuti == m, onSelected: (_) => _imposta('primaAppuntamento', m)),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}
