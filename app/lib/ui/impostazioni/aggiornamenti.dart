import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../servizi/aggiornamenti.dart';
import '../app.dart';
import '../comuni.dart';
import '../piattaforma.dart';
import '../tema.dart';

/// Riquadro "Nuova versione disponibile" (Oggi e pagina Aggiornamenti).
class RiquadroAggiornamento extends StatelessWidget {
  const RiquadroAggiornamento({super.key, this.conPiuTardi = true});
  final bool conPiuTardi;

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final ag = Aggiornamenti.istanza;
    final v = ag.disponibile;
    if (v == null) return const SizedBox.shrink();
    return Riquadro(
      tipo: 'ok',
      titolo: 'Nuova versione disponibile${v.versione.isEmpty ? '' : ': ${v.versione}'}',
      testo: [
        if (v.data != null) 'Pubblicata il ${F.dataOra(v.data)}.',
        if (v.note.isNotEmpty) v.note,
        'Si scarica dal browser: apri il file e tocca Installa. I dati restano.',
      ].join(' '),
      azioni: [
        FilledButton.icon(onPressed: () => apriLink(context, Uri.parse(v.apk)), icon: const Icon(Icons.download_rounded), label: const Text('Scarica')),
        if (conPiuTardi)
          TextButton(
            onPressed: () async {
              await d.scriviMeta('aggiornamentoIgnorato', v.build);
              d.aggiorna();
            },
            child: const Text('Più tardi'),
          ),
      ],
    );
  }
}

class PaginaAggiornamenti extends StatelessWidget {
  const PaginaAggiornamenti({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.dati;
    final ag = Aggiornamenti.istanza;
    return Scaffold(
      appBar: AppBar(title: const Text('Aggiornamenti')),
      body: ListenableBuilder(
        listenable: Listenable.merge([ag, d]),
        builder: (context, _) {
          final t = Theme.of(context).textTheme;
          final cs = Theme.of(context).colorScheme;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(padding: const EdgeInsets.all(S.l), children: [
                Text('Versione installata', style: t.titleMedium),
                const SizedBox(height: S.xs),
                Text('${ag.versioneAttuale.isEmpty ? versioneApp : ag.versioneAttuale}${ag.buildAttuale == null ? '' : ' (build ${ag.buildAttuale})'}', style: t.headlineSmall),
                const SizedBox(height: S.l),
                if (ag.disponibile != null)
                  const RiquadroAggiornamento(conPiuTardi: false)
                else
                  Riquadro(
                    tipo: ag.errore != null ? 'avviso' : 'info',
                    testo: ag.errore ??
                        (ag.ultimoControllo == null
                            ? 'L\'app controlla da sola se ci sono versioni nuove, all\'avvio e quando ci torni.'
                            : 'Hai già l\'ultima versione (controllato alle ${D.hhmm(ag.ultimoControllo!)}).'),
                  ),
                const SizedBox(height: S.m),
                OutlinedButton.icon(
                  onPressed: ag.inCorso ? null : () => ag.controlla(d),
                  icon: ag.inCorso ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh_rounded),
                  label: const Text('Controlla adesso'),
                ),
                const SizedBox(height: S.l),
                Text(
                  'La prima volta Android chiede di consentire l\'installazione dal browser ("Installa app sconosciute"): consentila solo per il browser che usi. '
                  'Gli aggiornamenti si installano sopra la versione attuale senza toccare i dati. Prima di aggiornare, per sicurezza, l\'app crea comunque un punto di ripristino ogni giorno.',
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
