import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/telefono.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../../dominio/privacy.dart';
import '../agenda/azioni.dart';
import '../agenda/dettaglio_appuntamento.dart';
import '../agenda/modulo_appuntamento.dart';
import '../app.dart';
import '../comuni.dart';
import '../foto.dart';
import '../piattaforma.dart';
import '../storico/scheda_lavoro.dart';
import '../tema.dart';
import 'modulo_cliente.dart';

Future<void> apriSchedaCliente(BuildContext context, String id) {
  return Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SchedaCliente(id: id)));
}

/// Scheda cliente: dati, avvertenze, statistiche, prossimi appuntamenti, storico lavori con foto.
class SchedaCliente extends StatelessWidget {
  const SchedaCliente({super.key, required this.id, this.incorporata = false});
  final String id;
  final bool incorporata;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return ListenableBuilder(
      listenable: d,
      builder: (context, _) {
        final c = d.get('clienti', id);
        if (c == null) {
          return Scaffold(appBar: incorporata ? null : AppBar(), body: const Vuoto('Cliente non trovata (forse è stata eliminata).', icona: Icons.person_off_outlined));
        }
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;
        final tel = comeStr(c['telefono']);
        final st = statisticheCliente(d, id);
        final ora = adessoIso();
        final apps = appuntamentiCliente(d, id);
        final prossimi = apps.where((a) => comeStr(a['inizio']).compareTo(ora) >= 0 && ['prenotato', 'confermato'].contains(statoApp(a))).toList()..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
        final passati = apps.where((a) => comeStr(a['inizio']).compareTo(ora) < 0 || !['prenotato', 'confermato'].contains(statoApp(a))).toList();
        final schede = schedeCliente(d, id);
        final foto = d.elenco('foto', archiviati: true).where((f) => f['clienteId'] == id).toList();
        final p = comeDoc(c['preferenze']);
        final prefs = [
          if (comeStr(p['forma']).isNotEmpty) ('Forma', comeStr(p['forma'])),
          if (comeStr(p['lunghezza']).isNotEmpty) ('Lunghezza', comeStr(p['lunghezza'])),
          if (comeStr(p['tecnica']).isNotEmpty) ('Tecnica', comeStr(p['tecnica'])),
          if (comeStr(p['colori']).isNotEmpty) ('Colori', comeStr(p['colori'])),
        ];
        final largo = MediaQuery.sizeOf(context).width >= 1000 || (incorporata && MediaQuery.sizeOf(context).width >= 1200);

        final intestazione = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(nomeCliente(c), dimensione: 64),
            const SizedBox(width: S.l),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nomeCliente(c), style: t.headlineMedium),
                if (tel.isNotEmpty) Text(telefonoLeggibile(tel), style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                if (comeListaStr(c['tag']).isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 4, runSpacing: 4, children: [for (final tg in comeListaStr(c['tag'])) Etichetta(tg, colore: cs.primary)])),
              ]),
            ),
          ]),
          const SizedBox(height: S.l),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => apriModuloAppuntamento(context, clienteId: id),
                icon: const Icon(Icons.event_available_rounded),
                label: const Text('Appuntamento'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              ),
            ),
            const SizedBox(width: S.s),
            IconButton.filledTonal(
              tooltip: 'WhatsApp',
              onPressed: tel.isEmpty ? null : () => apriLink(context, linkWhatsApp(tel, 'Ciao ${comeStr(c['nome'])}, ', prefisso: d.prefisso)),
              icon: const Icon(Icons.chat_rounded),
              style: IconButton.styleFrom(minimumSize: const Size(50, 50)),
            ),
            const SizedBox(width: S.s),
            IconButton.filledTonal(tooltip: 'Chiama', onPressed: tel.isEmpty ? null : () => chiama(context, tel), icon: const Icon(Icons.call_rounded), style: IconButton.styleFrom(minimumSize: const Size(50, 50))),
          ]),
          if (haAvvertenze(c)) ...[const SizedBox(height: S.l), Avvertenze(comeStr(c['avvertenze']))],
          if (schede.isNotEmpty && comeStr(schede.first['noteProssimaVolta']).isNotEmpty) ...[
            const SizedBox(height: S.m),
            Riquadro(titolo: 'Nota per la prossima volta', testo: comeStr(schede.first['noteProssimaVolta'])),
          ],
          const SizedBox(height: S.l),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: S.s,
            mainAxisSpacing: S.s,
            childAspectRatio: eTablet(context) ? 1.9 : 0.82,
            children: [
              Tessera(valore: '${st.visite}', etichetta: 'visite'),
              Tessera(valore: F.euro(st.spesaCent).replaceAll(',00', ''), etichetta: 'spesa totale'),
              Tessera(valore: st.frequenzaGiorni == null ? '—' : '${st.frequenzaGiorni} gg', etichetta: 'ogni'),
              Tessera(valore: '${st.noShow}', etichetta: 'non venuta'),
            ],
          ),
        ]);

        final colonnaDati = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sezione(
            titolo: 'Preferenze',
            child: prefs.isEmpty
                ? Text('Nessuna preferenza annotata.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                : Column(children: [
                    for (final (k, v) in prefs)
                      Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 92, child: Text(k, style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant))), Expanded(child: Text(v))])),
                  ]),
          ),
          const SizedBox(height: S.l),
          Sezione(
            titolo: 'Consensi',
            child: Column(children: [
              for (final e in consensi.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Icon(haConsenso(c, e.key) ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: haConsenso(c, e.key) ? const Color(0xFF1F7A55) : cs.outline),
                    const SizedBox(width: S.s),
                    Expanded(child: Text(e.value)),
                    if (haConsenso(c, e.key) && comeStr(comeDoc(comeDoc(c['consensi'])[e.key])['data']).isNotEmpty) Text(F.dataKey(comeStr(comeDoc(comeDoc(c['consensi'])[e.key])['data'])), style: t.bodySmall),
                  ]),
                ),
            ]),
          ),
          if (comeStr(c['note']).isNotEmpty || comeStr(c['email']).isNotEmpty || comeStr(c['dataNascita']).isNotEmpty) ...[
            const SizedBox(height: S.l),
            Sezione(
              titolo: 'Altre informazioni',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (comeStr(c['email']).isNotEmpty) Text('Email: ${c['email']}'),
                if (comeStr(c['dataNascita']).isNotEmpty) Text('Nata il ${F.dataKey(comeStr(c['dataNascita']))}'),
                if (comeStr(c['note']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(comeStr(c['note']))),
              ]),
            ),
          ],
        ]);

        final colonnaStoria = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Sezione(
            titolo: 'Prossimi appuntamenti',
            child: prossimi.isEmpty
                ? Text('Nessun appuntamento in programma.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                : Column(children: [for (final a in prossimi) RigaAppuntamento(app: a, mostraData: true, mostraCliente: false, suTocco: () => apriAppuntamento(context, a))]),
          ),
          const SizedBox(height: S.l),
          Sezione(
            titolo: 'Storico lavori',
            azione: TextButton.icon(onPressed: () => apriSchedaLavoro(context, clienteId: id), icon: const Icon(Icons.add_rounded), label: const Text('Aggiungi')),
            child: schede.isEmpty
                ? Text('Ancora nessun lavoro registrato. Quando completi un appuntamento compili la scheda lavoro.', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
                : Column(children: [
                    for (final s in schede) _VoceStorico(scheda: s, foto: foto.where((f) => f['schedaId'] == s['id']).toList()),
                  ]),
          ),
          if (passati.where((a) => comeStr(a['schedaId']).isEmpty).isNotEmpty) ...[
            const SizedBox(height: S.l),
            Sezione(
              titolo: 'Appuntamenti passati senza scheda',
              child: Column(children: [
                for (final a in (passati.where((a) => comeStr(a['schedaId']).isEmpty).toList()..sort((a, b) => comeStr(b['inizio']).compareTo(comeStr(a['inizio'])))).take(20))
                  RigaAppuntamento(app: a, mostraData: true, mostraCliente: false, suTocco: () => apriAppuntamento(context, a)),
              ]),
            ),
          ],
        ]);

        final corpo = ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
          intestazione,
          const SizedBox(height: S.l),
          if (largo)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: colonnaStoria), const SizedBox(width: S.l), Expanded(child: colonnaDati)])
          else ...[colonnaStoria, const SizedBox(height: S.l), colonnaDati],
        ]);

        final menu = PopupMenuButton<String>(
          tooltip: 'Altre azioni',
          onSelected: (v) => _azione(context, c, v),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'modifica', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifica'), contentPadding: EdgeInsets.zero)),
            if (schede.isNotEmpty || passati.any((a) => statoApp(a) == 'completato'))
              const PopupMenuItem(value: 'ripeti', child: ListTile(leading: Icon(Icons.replay_rounded), title: Text('Ripeti ultimo lavoro'), contentPadding: EdgeInsets.zero)),
            const PopupMenuItem(value: 'esporta', child: ListTile(leading: Icon(Icons.ios_share_rounded), title: Text('Esporta i suoi dati (privacy)'), contentPadding: EdgeInsets.zero)),
            if (c['archiviato'] == true)
              const PopupMenuItem(value: 'ripristina', child: ListTile(leading: Icon(Icons.unarchive_outlined), title: Text('Ripristina'), contentPadding: EdgeInsets.zero))
            else
              const PopupMenuItem(value: 'archivia', child: ListTile(leading: Icon(Icons.archive_outlined), title: Text('Archivia'), contentPadding: EdgeInsets.zero)),
            const PopupMenuItem(value: 'cancella', child: ListTile(leading: Icon(Icons.delete_forever_outlined, color: Color(0xFFB42318)), title: Text('Cancella definitivamente', style: TextStyle(color: Color(0xFFB42318))), contentPadding: EdgeInsets.zero)),
          ],
        );

        if (incorporata) {
          return Scaffold(
            appBar: AppBar(automaticallyImplyLeading: false, title: const Text(''), actions: [IconButton(tooltip: 'Modifica', onPressed: () => apriModuloCliente(context, cliente: c), icon: const Icon(Icons.edit_outlined)), menu]),
            body: corpo,
          );
        }
        return Scaffold(
          appBar: AppBar(title: Text(nomeCliente(c)), actions: [IconButton(tooltip: 'Modifica', onPressed: () => apriModuloCliente(context, cliente: c), icon: const Icon(Icons.edit_outlined)), menu]),
          body: corpo,
        );
      },
    );
  }

  Future<void> _azione(BuildContext context, Doc c, String v) async {
    final d = context.dati;
    switch (v) {
      case 'modifica':
        await apriModuloCliente(context, cliente: c);
      case 'ripeti':
        final schede = schedeCliente(d, id);
        final ultimoApp = (appuntamentiCliente(d, id).where((a) => statoApp(a) == 'completato').toList()..sort((a, b) => comeStr(b['inizio']).compareTo(comeStr(a['inizio'])))).firstOrNull;
        final servizi = schede.isNotEmpty ? comeListaDoc(schede.first['servizi']) : (ultimoApp != null ? serviziApp(ultimoApp) : <Doc>[]);
        final colori = schede.isNotEmpty ? comeStr(schede.first['colori']) : '';
        final durata = servizi.fold<int>(0, (t, s) => t + (comeInt(s['durata']) ?? 0) * (comeInt(s['quantita']) ?? 1));
        final slot = trovaSlotLiberi(d, durataMin: durata, servizi: servizi, quanti: 1);
        if (!context.mounted) return;
        await apriModuloAppuntamento(context, clienteId: id, servizi: servizi, inizio: slot.slot.isNotEmpty ? slot.slot.first : null, note: colori.isEmpty ? null : 'Come l\'ultima volta: $colori');
      case 'esporta':
        final dati = await esportaDatiCliente(d, id);
        if (!context.mounted) return;
        await condividiFile(context, Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(dati))), 'dati-${norm(nomeCliente(c)).replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${D.oggiKey()}.json');
      case 'archivia':
        await d.archivia('clienti', id);
        if (context.mounted) {
          if (!incorporata) Navigator.pop(context);
          avvisa('Cliente archiviata: non compare più nelle ricerche, lo storico resta.', annulla: () async => d.ripristina('clienti', id));
        }
      case 'ripristina':
        await d.ripristina('clienti', id);
      case 'cancella':
        final ok1 = await conferma(context, titolo: 'Cancellare ${nomeCliente(c)}?', messaggio: 'I suoi dati personali e le foto verranno cancellati da questo dispositivo (e dal cloud). Appuntamenti e schede restano in forma anonima, così le statistiche non cambiano.', ok: 'Continua', pericolo: true);
        if (!ok1 || !context.mounted) return;
        final ok2 = await conferma(context, titolo: 'Sei sicuro?', messaggio: 'Questa operazione non si può annullare.', ok: 'Cancella definitivamente', pericolo: true);
        if (!ok2 || !context.mounted) return;
        if (!incorporata) Navigator.pop(context);
        await eliminaClienteConAnonimizzazione(d, id);
        avvisa('Cliente cancellata. Lo storico resta in forma anonima.');
    }
  }
}

class _VoceStorico extends StatelessWidget {
  const _VoceStorico({required this.scheda, required this.foto});
  final Doc scheda;
  final List<Doc> foto;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final s = scheda;
    final dett = [comeStr(s['tecnica']), comeStr(s['forma']), comeStr(s['lunghezza'])].where((x) => x.isNotEmpty).join(' · ');
    foto.sort((a, b) => (a['tipo'] == 'prima' ? 0 : 1).compareTo(b['tipo'] == 'prima' ? 0 : 1));
    return InkWell(
      onTap: () => apriSchedaLavoro(context, scheda: s),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.m, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(F.maiuscola(F.giornoBreve(D.daKey(comeStr(s['data'])))), style: t.titleSmall?.copyWith(color: cs.primary))),
            if ((comeInt(s['importoCent']) ?? 0) > 0) Text(F.euro(comeInt(s['importoCent'])), style: t.titleSmall),
          ]),
          const SizedBox(height: 2),
          Text(comeListaDoc(s['servizi']).map((x) => comeStr(x['nome'])).join(' + ').isEmpty ? 'Lavoro' : comeListaDoc(s['servizi']).map((x) => comeStr(x['nome'])).join(' + '), style: t.bodyLarge),
          if (dett.isNotEmpty) Text(dett, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          if (comeStr(s['colori']).isNotEmpty) Text('🎨 ${s['colori']}', style: t.bodyMedium),
          if (comeStr(s['noteProssimaVolta']).isNotEmpty) Text('➜ ${s['noteProssimaVolta']}', style: t.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          if (foto.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: S.s),
              child: Wrap(spacing: S.s, runSpacing: S.s, children: [for (final f in foto) FotoMiniatura(key: ValueKey(f['id']), id: comeStr(f['id']), dimensione: 76, etichetta: comeStr(f['tipo']))]),
            ),
          const Divider(height: S.l * 1.5),
        ]),
      ),
    );
  }
}
