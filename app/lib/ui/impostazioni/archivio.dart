import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/util.dart';
import '../../dominio/agenda.dart';
import '../../dominio/privacy.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';

/// Elementi archiviati: ripristino o eliminazione definitiva (con doppia conferma).
class PaginaArchivio extends StatelessWidget {
  const PaginaArchivio({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    return Scaffold(
      appBar: AppBar(title: const Text('Elementi archiviati')),
      body: ListenableBuilder(
        listenable: d,
        builder: (context, _) {
          String desc(String a, Doc r) => switch (a) {
                'clienti' => nomeCliente(r),
                'appuntamenti' => '${F.dataOra(inizioApp(r))} — ${nomeCliente(d.get('clienti', comeStr(r['clienteId']))).isEmpty ? comeStr(r['clienteNome']) : nomeCliente(d.get('clienti', comeStr(r['clienteId'])))}',
                'schede_lavoro' => '${F.dataKey(comeStr(r['data']))} — ${nomeCliente(d.get('clienti', comeStr(r['clienteId']))).isEmpty ? 'cliente eliminata' : nomeCliente(d.get('clienti', comeStr(r['clienteId'])))}',
                'servizi' => comeStr(r['nome']),
                'blocchi' => descriviBlocco(r),
                _ => comeStr(r['nome'] ?? r['titolo'] ?? r['id']),
              };
          const gruppi = [('clienti', 'Clienti'), ('appuntamenti', 'Appuntamenti'), ('schede_lavoro', 'Schede lavoro'), ('servizi', 'Servizi'), ('blocchi', 'Pause e chiusure')];
          final contenuto = <Widget>[];
          for (final (a, titolo) in gruppi) {
            final lista = d.elenco(a, archiviati: true).where((r) => r['archiviato'] == true).toList()..sort((x, y) => comeStr(y['archiviatoIl'] ?? y['updatedAt']).compareTo(comeStr(x['archiviatoIl'] ?? x['updatedAt'])));
            if (lista.isEmpty) continue;
            contenuto.add(Padding(
              padding: const EdgeInsets.only(bottom: S.l),
              child: Sezione(
                titolo: '$titolo (${lista.length})',
                child: Column(children: [
                  for (final r in lista)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(desc(a, r)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Ripristina',
                          icon: const Icon(Icons.unarchive_outlined),
                          onPressed: () async {
                            await d.ripristina(a, comeStr(r['id']));
                            if (context.mounted) avviso(context, 'Ripristinato');
                          },
                        ),
                        IconButton(
                          tooltip: 'Elimina definitivamente',
                          icon: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
                          onPressed: () => _elimina(context, a, r, desc(a, r)),
                        ),
                      ]),
                    ),
                ]),
              ),
            ));
          }
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                if (contenuto.isEmpty) const Vuoto('Nessun elemento archiviato.', icona: Icons.inventory_2_outlined) else ...contenuto,
              ]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _elimina(BuildContext context, String a, Doc r, String nome) async {
    final d = context.dati;
    final cosa = a == 'clienti' ? 'la cliente $nome: i suoi dati personali e le foto verranno cancellati; appuntamenti e schede restano anonimi per le statistiche' : '"$nome"';
    final ok1 = await conferma(context, titolo: 'Eliminare definitivamente?', messaggio: 'Stai per eliminare $cosa.', ok: 'Continua', pericolo: true);
    if (!ok1 || !context.mounted) return;
    final ok2 = await conferma(context, titolo: 'Sei sicuro?', messaggio: 'Questa operazione non si può annullare.', ok: 'Elimina definitivamente', pericolo: true);
    if (!ok2 || !context.mounted) return;
    final id = comeStr(r['id']);
    if (a == 'clienti') {
      await eliminaClienteConAnonimizzazione(d, id);
    } else if (a == 'schede_lavoro') {
      await d.inBlocco(() async {
        await d.eliminaMolti('foto', d.elenco('foto', archiviati: true).where((f) => f['schedaId'] == id).map((f) => comeStr(f['id'])).toList());
        await d.elimina('schede_lavoro', id);
      });
    } else {
      await d.elimina(a, id);
    }
    if (context.mounted) avviso(context, 'Eliminato definitivamente');
  }
}
