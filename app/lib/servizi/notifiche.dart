import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdati;
import 'package:timezone/timezone.dart' as tz;

import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import '../dominio/agenda.dart';
import '../dominio/magazzino.dart';

/// Impostazioni delle notifiche (in configurazione, valgono per tutti i dispositivi della stessa agenda).
class OpzioniNotifiche {
  OpzioniNotifiche(Doc cfg)
      : riepilogo = comeDoc(cfg['notifiche'])['riepilogoSerale'] != false,
        oraRiepilogo = comeStr(comeDoc(cfg['notifiche'])['oraRiepilogo']).isEmpty ? '19:30' : comeStr(comeDoc(cfg['notifiche'])['oraRiepilogo']),
        appunti = comeDoc(cfg['notifiche'])['promemoriaAppunti'] != false,
        oraAppunti = comeStr(comeDoc(cfg['notifiche'])['oraPromemoria']).isEmpty ? '09:00' : comeStr(comeDoc(cfg['notifiche'])['oraPromemoria']),
        primaMinuti = comeInt(comeDoc(cfg['notifiche'])['primaAppuntamento']) ?? 0,
        magazzino = comeDoc(cfg['notifiche'])['magazzino'] != false;
  final bool riepilogo, appunti, magazzino;
  final String oraRiepilogo, oraAppunti;
  final int primaMinuti;
}

/// Una notifica da programmare (calcolata dai dati, senza dipendere dal plugin: si può testare).
class NotificaPrevista {
  NotificaPrevista(this.id, this.quando, this.titolo, this.testo, this.payload);
  final int id;
  final DateTime quando;
  final String titolo, testo, payload;
}

/// Calcola le notifiche dei prossimi giorni. iOS ne tiene al massimo 64: si resta ben sotto.
List<NotificaPrevista> calcolaNotifiche(Dati d, {DateTime? ora, int giorni = 7}) {
  final adesso = ora ?? DateTime.now();
  final op = OpzioniNotifiche(d.cfg);
  final out = <NotificaPrevista>[];
  final oggi = D.inizioGiorno(adesso);

  // 1) riepilogo serale degli appuntamenti del giorno dopo
  if (op.riepilogo && d.moduloAttivo('agenda')) {
    for (var g = 0; g < giorni; g++) {
      final giorno = D.aggiungiGiorni(oggi, g);
      final quando = D.combina(D.key(giorno), op.oraRiepilogo);
      if (!quando.isAfter(adesso)) continue;
      final domani = D.aggiungiGiorni(giorno, 1);
      final apps = appuntamentiTra(d, domani, D.aggiungiGiorni(domani, 1)).where((a) => ['prenotato', 'confermato'].contains(statoApp(a))).toList()
        ..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
      if (apps.isEmpty) continue;
      final primo = apps.first;
      final daAvvisare = apps.where((a) => a['promemoriaInviatoIl'] == null).length;
      out.add(NotificaPrevista(
        1000 + g,
        quando,
        'Domani: ${apps.length} ${apps.length == 1 ? 'appuntamento' : 'appuntamenti'}',
        'Il primo alle ${D.hhmm(inizioApp(primo))} con ${nomeClienteDi(d, primo)}${daAvvisare > 0 ? ' · $daAvvisare promemoria WhatsApp da inviare' : ''}',
        'oggi',
      ));
    }
  }

  // 2) promemoria degli appunti, alla data indicata
  if (op.appunti && d.moduloAttivo('appunti')) {
    final lista = d.elenco('appunti').where((a) => comeStr(a['promemoria']).isNotEmpty && a['fatto'] != true).toList()
      ..sort((a, b) => comeStr(a['promemoria']).compareTo(comeStr(b['promemoria'])));
    var i = 0;
    for (final a in lista) {
      final quando = D.combina(comeStr(a['promemoria']), op.oraAppunti);
      if (!quando.isAfter(adesso) || D.diffGiorni(D.key(oggi), comeStr(a['promemoria'])) > 60) continue;
      out.add(NotificaPrevista(2000 + i++, quando, 'Promemoria', comeStr(a['titolo']).isNotEmpty ? comeStr(a['titolo']) : comeStr(a['testo']), 'appunto:${a['id']}'));
      if (i >= 20) break;
    }
  }

  // 3) qualche minuto prima di ogni appuntamento (facoltativo)
  if (op.primaMinuti > 0 && d.moduloAttivo('agenda')) {
    final apps = appuntamentiTra(d, adesso, D.aggiungiGiorni(oggi, 3)).where((a) => ['prenotato', 'confermato'].contains(statoApp(a))).toList()
      ..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
    var i = 0;
    for (final a in apps) {
      final quando = inizioApp(a).subtract(Duration(minutes: op.primaMinuti));
      if (!quando.isAfter(adesso)) continue;
      final cli = d.get('clienti', comeStr(a['clienteId']));
      out.add(NotificaPrevista(3000 + i++, quando, 'Alle ${D.hhmm(inizioApp(a))}: ${nomeClienteDi(d, a)}', [serviziTesto(a), if (haAvvertenze(cli)) '⚠️ ${comeStr(cli!['avvertenze'])}'].where((x) => x.isNotEmpty).join(' · '), 'appuntamento:${a['id']}'));
      if (i >= 25) break;
    }
  }

  // 4) magazzino: un avviso la mattina dopo, se ci sono prodotti da riordinare o in scadenza
  if (op.magazzino && d.moduloAttivo('magazzino')) {
    final avv = avvisiMagazzino(d);
    final sotto = avv.sottoScorta.length + avv.negativi.where((x) => !avv.sottoScorta.any((y) => y.p['id'] == x.p['id'])).length;
    final scad = avv.inScadenza.length + avv.scaduti.length + avv.paoSuperato.length;
    if (sotto + scad > 0) {
      var quando = D.combina(D.key(oggi), op.oraAppunti);
      if (!quando.isAfter(adesso)) quando = D.combina(D.key(D.aggiungiGiorni(oggi, 1)), op.oraAppunti);
      out.add(NotificaPrevista(4000, quando, 'Magazzino', [if (sotto > 0) '$sotto ${sotto == 1 ? 'prodotto' : 'prodotti'} da riordinare', if (scad > 0) '$scad in scadenza o aperti da troppo'].join(' · '), 'magazzino'));
    }
  }
  return out;
}

/// Notifiche locali programmate sul dispositivo (nessun server: funzionano anche offline).
class Notifiche {
  Notifiche._();
  static final istanza = Notifiche._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pronte = false;
  Timer? _timer;
  void Function(String payload)? suTocco;
  String? payloadAvvio;

  bool get supportate => !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  Future<void> avvia(Dati d) async {
    if (!supportate || _pronte) return;
    try {
      tzdati.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) suTocco?.call(p);
        },
      );
      final lancio = await _plugin.getNotificationAppLaunchDetails();
      if (lancio?.didNotificationLaunchApp == true) payloadAvvio = lancio?.notificationResponse?.payload;
      _pronte = true;
      await riprogramma(d);
    } catch (e) {
      debugPrint('Notifiche non disponibili: $e');
    }
  }

  /// Chiede il permesso (una volta). true se concesso.
  Future<bool> chiediPermesso() async {
    if (!supportate) return false;
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: false, sound: true) ?? false;
      final and = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (and != null) return await and.requestNotificationsPermission() ?? false;
    } catch (_) {}
    return false;
  }

  /// Da chiamare dopo ogni modifica dei dati (con un piccolo ritardo per raggrupparle).
  void programma(Dati d, [Duration ritardo = const Duration(seconds: 3)]) {
    if (!_pronte) return;
    _timer?.cancel();
    _timer = Timer(ritardo, () => riprogramma(d));
  }

  /// Notifica immediata di prova.
  Future<void> prova() async {
    if (!_pronte) return;
    await _plugin.show(
      id: 9999,
      title: 'Notifiche attive',
      body: 'Riceverai qui il riepilogo e i promemoria.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails('agenda', 'Agenda e promemoria', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
      ),
    );
  }

  Future<int> quanteProgrammate() async {
    if (!_pronte) return 0;
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _coda = Future.value();

  /// Ricalcola tutto da capo (una alla volta: due chiamate ravvicinate non si sovrappongono).
  Future<void> riprogramma(Dati d) {
    final f = _coda.then((_) => _riprogramma(d));
    _coda = f.catchError((_) {});
    return f;
  }

  Future<void> _riprogramma(Dati d) async {
    if (!_pronte) return;
    try {
      final loc = tz.getLocation(comeStr(d.cfg['fusoOrario']).isEmpty ? 'Europe/Rome' : comeStr(d.cfg['fusoOrario']));
      // solo quelle in attesa: le notifiche già arrivate restano nel centro notifiche
      await _plugin.cancelAllPendingNotifications();
      const dettagli = NotificationDetails(
        android: AndroidNotificationDetails('agenda', 'Agenda e promemoria', channelDescription: 'Riepilogo degli appuntamenti, promemoria degli appunti, avvisi di magazzino', importance: Importance.high, priority: Priority.high),
        iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true),
      );
      for (final n in calcolaNotifiche(d)) {
        await _plugin.zonedSchedule(
          id: n.id,
          scheduledDate: tz.TZDateTime.from(n.quando, loc),
          notificationDetails: dettagli,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: n.titolo,
          body: n.testo,
          payload: n.payload,
        );
      }
    } catch (e) {
      debugPrint('Programmazione notifiche non riuscita: $e');
    }
  }
}
