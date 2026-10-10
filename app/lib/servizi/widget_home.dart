import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import '../dominio/agenda.dart';

/// Testi del widget "Agenda di oggi" per i prossimi giorni, chiave = data (aaaa-mm-gg).
/// Il widget sceglie da solo il giorno corrente: resta giusto anche se l'app non viene aperta
/// per qualche giorno.
Map<String, Doc> datiWidget(Dati d, {DateTime? ora, int giorni = 7, int maxRighe = 5}) {
  final oggi = D.inizioGiorno(ora ?? DateTime.now());
  final out = <String, Doc>{};
  for (var g = 0; g < giorni; g++) {
    final giorno = D.aggiungiGiorni(oggi, g);
    final apps = appuntamentiTra(d, giorno, D.aggiungiGiorni(giorno, 1)).where((a) => !['annullato', 'non_presentata'].contains(statoApp(a))).toList()
      ..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
    final righe = <String>[
      for (final a in apps.take(apps.length > maxRighe ? maxRighe - 1 : maxRighe))
        [
          '${D.hhmm(inizioApp(a))}  ${nomeClienteDi(d, a)}',
          if (serviziTesto(a).isNotEmpty) serviziTesto(a),
        ].join(' · '),
      if (apps.length > maxRighe) 'e altri ${apps.length - maxRighe + 1}…',
    ];
    out[D.key(giorno)] = {
      'titolo': 'Oggi · ${F.giornoBreve(giorno)}',
      'sottotitolo': apps.isEmpty ? 'Nessun appuntamento' : '${apps.length} ${apps.length == 1 ? 'appuntamento' : 'appuntamenti'}',
      'righe': righe,
    };
  }
  return out;
}

/// Widget nella schermata Home (Android).
class WidgetHome {
  static Timer? _timer;
  static bool get supportato => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void programma(Dati d, [Duration ritardo = const Duration(seconds: 2)]) {
    if (!supportato || !d.moduloAttivo('agenda')) return;
    _timer?.cancel();
    _timer = Timer(ritardo, () => aggiorna(d));
  }

  static Future<void> aggiorna(Dati d) async {
    if (!supportato) return;
    try {
      await HomeWidget.saveWidgetData<String>('giorni', jsonEncode(datiWidget(d)));
      await HomeWidget.updateWidget(qualifiedAndroidName: 'it.agendanails.agenda_nails.WidgetOggi');
    } catch (e) {
      debugPrint('Widget non aggiornato: $e');
    }
  }
}
