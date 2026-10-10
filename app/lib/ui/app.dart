import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/config.dart';
import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import '../dominio/cloud.dart';
import '../dominio/ripristino.dart';
import '../servizi/aggiornamenti.dart';
import '../servizi/backup_android.dart';
import '../servizi/notifiche.dart';
import '../servizi/scorciatoie.dart';
import '../servizi/widget_home.dart';
import 'agenda/modulo_appuntamento.dart';
import 'clienti/modulo_cliente.dart';
import 'agenda/dettaglio_appuntamento.dart';
import 'agenda/pagina_agenda.dart';
import 'appunti/pagina_appunti.dart';
import 'blocco.dart';
import 'clienti/pagina_clienti.dart';
import 'comuni.dart';
import 'fornitori/pagina_fornitori.dart';
import 'fornitori/ordini.dart';
import 'impostazioni/pagina_altro.dart';
import 'magazzino/pagina_magazzino.dart';
import 'oggi.dart';
import 'report/pagina_report.dart';
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

/// Comandi tra le schede (es. "apri l'agenda su quel giorno"). Le schede hanno un nome:
/// oggi, agenda, clienti, magazzino, ordini, fornitori, appunti, report, altro.
class Navigazione extends ChangeNotifier {
  String scheda = 'oggi';
  DateTime? giornoAgenda;
  void vai(String s, {DateTime? giorno}) {
    scheda = s;
    if (giorno != null) giornoAgenda = giorno;
    notifyListeners();
  }
}

final navigazione = Navigazione();

/// Navigatore principale (per aprire pagine da una notifica).
final navigatore = GlobalKey<NavigatorState>();

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
            navigatorKey: navigatore,
            builder: (context, figlio) => Blocco(dati: dati, child: figlio ?? const SizedBox()),
            home: Guscio(schermataIniziale: schermataIniziale),
          );
        },
      ),
    );
  }
}

class _Voce {
  const _Voce(this.chiave, this.titolo, this.icona, this.iconaScelta);
  final String chiave, titolo;
  final IconData icona, iconaScelta;
}

const _tutte = [
  _Voce('oggi', 'Oggi', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
  _Voce('agenda', 'Agenda', Icons.calendar_month_outlined, Icons.calendar_month_rounded),
  _Voce('clienti', 'Clienti', Icons.people_outline_rounded, Icons.people_rounded),
  _Voce('magazzino', 'Magazzino', Icons.inventory_2_outlined, Icons.inventory_2_rounded),
  _Voce('ordini', 'Ordini', Icons.local_shipping_outlined, Icons.local_shipping_rounded),
  _Voce('fornitori', 'Fornitori', Icons.storefront_outlined, Icons.storefront_rounded),
  _Voce('appunti', 'Appunti', Icons.sticky_note_2_outlined, Icons.sticky_note_2_rounded),
  _Voce('report', 'Report', Icons.insights_outlined, Icons.insights_rounded),
  _Voce('altro', 'Altro', Icons.tune_outlined, Icons.tune_rounded),
];

/// Pagina principale di una sezione (usata come scheda o aperta sopra le altre sul telefono).
Widget paginaSezione(String chiave) => switch (chiave) {
      'agenda' => const PaginaAgenda(),
      'clienti' => const PaginaClienti(),
      'magazzino' => const PaginaMagazzino(),
      'ordini' => const PaginaOrdini(),
      'fornitori' => const PaginaFornitori(),
      'appunti' => const PaginaAppunti(),
      'report' => const PaginaReport(),
      'altro' => const PaginaAltro(),
      _ => const PaginaOggi(),
    };

/// Apre una sezione: come scheda se è nella barra, altrimenti come pagina sopra (telefono).
void apriSezione(BuildContext context, String chiave) {
  if (vociVisibili(context).any((v) => v.chiave == chiave)) {
    navigazione.vai(chiave);
  } else {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => paginaSezione(chiave)));
  }
}

/// Sezioni nella barra: sul telefono le principali (le altre sono in "Altro"), su tablet tutte.
List<_Voce> vociVisibili(BuildContext context) {
  final d = context.dati;
  final tablet = eTablet(context);
  bool attiva(String k) => switch (k) {
        'oggi' || 'altro' => true,
        'clienti' => d.moduloAttivo('clienti'),
        'agenda' => d.moduloAttivo('agenda'),
        'magazzino' => d.moduloAttivo('magazzino'),
        _ => tablet && d.moduloAttivo(k),
      };
  return [for (final v in _tutte) if (attiva(v.chiave)) v];
}

/// Struttura principale: barra in basso sul telefono, barra laterale su tablet.
class Guscio extends StatefulWidget {
  const Guscio({super.key, this.schermataIniziale});
  final String? schermataIniziale;
  @override
  State<Guscio> createState() => _GuscioState();
}

class _GuscioState extends State<Guscio> with WidgetsBindingObserver {
  final Map<String, Widget> _pagine = {};

  @override
  void initState() {
    super.initState();
    navigazione.addListener(_cambio);
    WidgetsBinding.instance.addObserver(this);
    final s = widget.schermataIniziale;
    if (s != null) {
      navigazione.scheda = switch (s) {
        'agenda' || 'agenda-settimana' || 'appuntamento' => 'agenda',
        'clienti' || 'cliente' => 'clienti',
        'magazzino' || 'prodotto' => 'magazzino',
        'ordini' || 'fornitori' || 'appunti' || 'report' => s,
        'impostazioni' || 'impostazioni-orari' || 'dati' || 'sicurezza' || 'notifiche' => 'altro',
        _ => 'oggi',
      };
      // sul telefono alcune sezioni non sono nella barra: si aprono sopra
      WidgetsBinding.instance.addPostFrameCallback((_) => _cambio());
    }
    // tocco su una notifica: con l'app aperta, oppure che ha avviato l'app
    Notifiche.istanza.suTocco = _daNotifica;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = Notifiche.istanza.payloadAvvio;
      Notifiche.istanza.payloadAvvio = null;
      if (p != null && p.isNotEmpty) _daNotifica(p);
      // scorciatoie tenendo premuta l'icona dell'app
      if (mounted) Scorciatoie.avvia(context.dati, (tipo) => WidgetsBinding.instance.addPostFrameCallback((_) => _daScorciatoia(tipo)));
    });
  }

  void _daScorciatoia(String tipo) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    switch (tipo) {
      case 'nuovo-appuntamento':
        navigazione.vai('agenda');
        apriModuloAppuntamento(context);
      case 'agenda':
        navigazione.vai('agenda', giorno: DateTime.now());
      case 'nuova-cliente':
        apriModuloCliente(context);
      case 'nuovo-appunto':
        apriAppunto(context);
    }
  }

  void _daNotifica(String p) {
    if (!mounted) return;
    final d = context.dati;
    // si chiudono eventuali pagine aperte sopra, poi si apre quella giusta
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (p.startsWith('appuntamento:')) {
      final a = d.get('appuntamenti', p.substring('appuntamento:'.length));
      if (a != null) {
        navigazione.vai('agenda', giorno: D.daIso(comeStr(a['inizio'])));
        apriAppuntamento(context, a);
      }
    } else if (p.startsWith('appunto:')) {
      final a = d.get('appunti', p.substring('appunto:'.length));
      if (a != null) apriAppunto(context, appunto: a);
    } else if (p == 'magazzino' && d.moduloAttivo('magazzino')) {
      navigazione.vai('magazzino');
    } else {
      navigazione.vai('oggi');
    }
  }

  @override
  void dispose() {
    navigazione.removeListener(_cambio);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _cambio() {
    if (!mounted) return;
    final voci = vociVisibili(context);
    if (!voci.any((v) => v.chiave == navigazione.scheda)) {
      // sezione non presente nella barra (telefono): si apre sopra, la scheda resta "Altro"
      final k = navigazione.scheda;
      navigazione.scheda = 'altro';
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => paginaSezione(k)));
    }
    setState(() {});
  }

  /// Tornando nell'app si sincronizza e si aggiornano gli orari ("adesso"); uscendo si salva nel cloud.
  @override
  void didChangeAppLifecycleState(AppLifecycleState stato) {
    final cloud = context.cloud;
    if (stato == AppLifecycleState.resumed) {
      cloud.programma(const Duration(milliseconds: 600));
      context.dati.aggiorna();
      Notifiche.istanza.programma(context.dati, const Duration(seconds: 1));
      WidgetHome.programma(context.dati, const Duration(seconds: 1));
      Aggiornamenti.istanza.seServe(context.dati);
      controllaCopiaGiornaliera(context.dati);
    } else if (stato == AppLifecycleState.paused) {
      cloud.sincronizza();
      BackupAndroid.salva(context.dati);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: context.dati,
      builder: (context, _) {
        final voci = vociVisibili(context);
        var i = voci.indexWhere((v) => v.chiave == navigazione.scheda);
        if (i < 0) i = 0;
        final corpo = IndexedStack(index: i, children: [
          for (final v in voci) KeyedSubtree(key: ValueKey(v.chiave), child: _pagine.putIfAbsent(v.chiave, () => paginaSezione(v.chiave))),
        ]);
        void scegli(int n) {
          vibra();
          navigazione.vai(voci[n].chiave);
        }

        if (eTablet(context)) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            body: Row(children: [
              SafeArea(
                right: false,
                child: LayoutBuilder(
                  builder: (context, v) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: v.maxHeight),
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          selectedIndex: i,
                          onDestinationSelected: scegli,
                          labelType: NavigationRailLabelType.all,
                          groupAlignment: -0.9,
                          leading: Padding(padding: const EdgeInsets.only(bottom: S.s, top: S.s), child: Image.asset('assets/immagini/icona.png', width: 36, height: 36)),
                          destinations: [for (final v in voci) NavigationRailDestination(icon: Icon(v.icona), selectedIcon: Icon(v.iconaScelta), label: Text(v.titolo))],
                        ),
                      ),
                    ),
                  ),
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
            onDestinationSelected: scegli,
            destinations: [for (final v in voci) NavigationDestination(icon: Icon(v.icona), selectedIcon: Icon(v.iconaScelta), label: v.titolo)],
          ),
        );
      },
    );
  }
}
