import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'core/ambiente.dart';
import 'dati/archivio.dart';
import 'dati/copie.dart';
import 'dati/dati.dart';
import 'dominio/cloud.dart';
import 'dominio/configurazione.dart';
import 'dominio/demo.dart';
import 'dominio/ripristino.dart';
import 'servizi/notifiche.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it');
  Intl.defaultLocale = 'it';
  try {
    final dati = Dati(creaArchivio());
    await dati.avvia();
    await seminaServizi(dati);
    final cloud = Cloud(dati);
    await preparaAmbiente();
    schermataAvvio = variabileAmbiente('AGENDA_SCHERMATA');
    if (variabileAmbiente('AGENDA_DEMO') == '1') await caricaDatiDemo(dati, configura: true);
    await cloud.avvia();
    archivioCopie = creaArchivioCopie();
    // le notifiche si preparano prima di disegnare l'app: così si sa se l'ha aperta un tocco su una notifica
    await Notifiche.istanza.avvia(dati).timeout(const Duration(seconds: 4), onTimeout: () {});
    dati.addListener(() => Notifiche.istanza.programma(dati));
    runApp(AppAgenda(dati: dati, cloud: cloud, schermataIniziale: schermataAvvio));
    avviaCopieAutomatiche(dati);
  } catch (e, st) {
    debugPrint('Errore di avvio: $e\n$st');
    runApp(ErroreAvvio(errore: '$e'));
  }
}

/// Schermata mostrata se l'archivio non si apre (invece di una pagina bianca).
class ErroreAvvio extends StatelessWidget {
  const ErroreAvvio({super.key, required this.errore});
  final String errore;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline_rounded, size: 48, color: Color(0xFFB42318)),
                const SizedBox(height: 16),
                const Text('L\'agenda non riesce ad aprire i dati', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Chiudi completamente l\'app e riaprila. Se il problema resta, non disinstallarla (perderesti i dati): contatta l\'assistenza con questo messaggio.'),
                const SizedBox(height: 16),
                SelectableText(errore, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ]),
            ),
          ),
        ),
      );
}
