import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../app.dart';
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
      final r = radice(context);
      Navigator.pop(context);
      avviso(r, 'Dati dell\'attività salvati');
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
      final r = radice(context);
      Navigator.pop(context);
      avviso(r, 'Messaggi salvati');
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
