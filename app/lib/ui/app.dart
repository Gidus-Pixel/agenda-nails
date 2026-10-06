import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/config.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import '../dominio/cloud.dart';
import 'agenda/pagina_agenda.dart';
import 'clienti/pagina_clienti.dart';
import 'comuni.dart';
import 'impostazioni/pagina_altro.dart';
import 'oggi.dart';
import 'tema.dart';

/// Rende disponibili dati e cloud a tutte le schermate.
class Ambito extends InheritedWidget {
  const Ambito({super.key, required this.dati, required this.cloud, required super.child});
  final Dati dati;
  final Cloud cloud;
  static Ambito of(BuildContext c) => c.getInheritedWidgetOfExactType<Ambito>()!;
  @override
  bool updateShouldNotify(Ambito old) => old.dati != dati || old.cloud != cloud;
}

extension AmbitoX on BuildContext {
  Dati get dati => Ambito.of(this).dati;
  Cloud get cloud => Ambito.of(this).cloud;
}

/// Contesto del navigatore principale: resta valido anche dopo aver chiuso un foglio o una finestra.
BuildContext radice(BuildContext c) => Navigator.of(c, rootNavigator: true).context;

/// Comandi tra le schede (es. "apri l'agenda su quel giorno").
class Navigazione extends ChangeNotifier {
  int scheda = 0;
  DateTime? giornoAgenda;
  void vai(int s, {DateTime? giorno}) {
    scheda = s;
    if (giorno != null) giornoAgenda = giorno;
    notifyListeners();
  }
}

final navigazione = Navigazione();

/// Schermata richiesta all'avvio (schermate automatiche per i test): oggi, agenda, agenda-settimana, appuntamento, clienti, cliente, impostazioni, dati.
String? schermataAvvio;

class AppAgenda extends StatelessWidget {
  const AppAgenda({super.key, required this.dati, required this.cloud, this.schermataIniziale});
  final Dati dati;
  final Cloud cloud;
  final String? schermataIniziale;

  @override
  Widget build(BuildContext context) {
    return Ambito(
      dati: dati,
      cloud: cloud,
      child: ListenableBuilder(
        listenable: dati,
        builder: (context, _) {
          final cfg = dati.cfg;
          final primario = Color(coloreDaHex(comeDoc(cfg['brand'])['primario']) ?? 0xFFB4646E);
          final tema = comeStr(cfg['tema']);
          return MaterialApp(
            title: dati.nomeAttivita.isEmpty ? 'Agenda' : dati.nomeAttivita,
            debugShowCheckedModeBanner: false,
            scaffoldMessengerKey: messaggero,
            theme: Tema.crea(primario: primario, luminosita: Brightness.light),
            darkTheme: Tema.crea(primario: primario, luminosita: Brightness.dark),
            themeMode: switch (tema) { 'chiaro' => ThemeMode.light, 'scuro' => ThemeMode.dark, _ => ThemeMode.system },
            locale: const Locale('it', 'IT'),
            supportedLocales: const [Locale('it', 'IT')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: Guscio(schermataIniziale: schermataIniziale),
          );
        },
      ),
    );
  }
}

class _Voce {
  const _Voce(this.titolo, this.icona, this.iconaScelta, this.pagina);
  final String titolo;
  final IconData icona, iconaScelta;
  final Widget pagina;
}

/// Struttura principale: barra in basso sul telefono, barra laterale su tablet.
class Guscio extends StatefulWidget {
  const Guscio({super.key, this.schermataIniziale});
  final String? schermataIniziale;
  @override
  State<Guscio> createState() => _GuscioState();
}

class _GuscioState extends State<Guscio> with WidgetsBindingObserver {
  late final List<_Voce> _voci = [
    const _Voce('Oggi', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, PaginaOggi()),
    const _Voce('Agenda', Icons.calendar_month_outlined, Icons.calendar_month_rounded, PaginaAgenda()),
    const _Voce('Clienti', Icons.people_outline_rounded, Icons.people_rounded, PaginaClienti()),
    const _Voce('Altro', Icons.tune_outlined, Icons.tune_rounded, PaginaAltro()),
  ];

  @override
  void initState() {
    super.initState();
    navigazione.addListener(_cambio);
    WidgetsBinding.instance.addObserver(this);
    final s = widget.schermataIniziale;
    if (s != null) {
      navigazione.scheda = switch (s) {
        'agenda' || 'agenda-settimana' || 'appuntamento' => 1,
        'clienti' || 'cliente' => 2,
        'impostazioni' || 'impostazioni-orari' || 'dati' => 3,
        _ => 0,
      };
    }
  }

  @override
  void dispose() {
    navigazione.removeListener(_cambio);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _cambio() => setState(() {});

  /// Tornando nell'app si sincronizza e si aggiornano gli orari ("adesso"); uscendo si salva nel cloud.
  @override
  void didChangeAppLifecycleState(AppLifecycleState stato) {
    final cloud = context.cloud;
    if (stato == AppLifecycleState.resumed) {
      cloud.programma(const Duration(milliseconds: 600));
      context.dati.aggiorna();
    } else if (stato == AppLifecycleState.paused) {
      cloud.sincronizza();
    }
  }

  @override
  Widget build(BuildContext context) {
    final i = navigazione.scheda;
    final corpo = IndexedStack(index: i, children: [for (final v in _voci) v.pagina]);
    if (eTablet(context)) {
      final cs = Theme.of(context).colorScheme;
      return Scaffold(
        body: Row(children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: i,
              onDestinationSelected: (n) => navigazione.vai(n),
              labelType: NavigationRailLabelType.all,
              groupAlignment: -0.85,
              leading: Padding(
                padding: const EdgeInsets.only(bottom: S.l, top: S.s),
                child: Icon(Icons.spa_rounded, color: cs.primary, size: 30),
              ),
              destinations: [for (final v in _voci) NavigationRailDestination(icon: Icon(v.icona), selectedIcon: Icon(v.iconaScelta), label: Text(v.titolo))],
            ),
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          Expanded(child: corpo),
        ]),
      );
    }
    return Scaffold(
      body: corpo,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (n) => navigazione.vai(n),
        destinations: [for (final v in _voci) NavigationDestination(icon: Icon(v.icona), selectedIcon: Icon(v.iconaScelta), label: v.titolo)],
      ),
    );
  }
}
