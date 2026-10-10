import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

import '../dati/dati.dart';

/// Scorciatoie tenendo premuta l'icona dell'app (Android 7.1+ e iPhone).
class Scorciatoie {
  static const _qa = QuickActions();

  static bool get supportate => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> avvia(Dati d, void Function(String tipo) suScelta) async {
    if (!supportate) return;
    try {
      await _qa.initialize(suScelta);
      await _qa.setShortcutItems([
        if (d.moduloAttivo('agenda')) const ShortcutItem(type: 'nuovo-appuntamento', localizedTitle: 'Nuovo appuntamento', icon: 'ic_sc_appuntamento'),
        if (d.moduloAttivo('agenda')) const ShortcutItem(type: 'agenda', localizedTitle: 'Agenda di oggi', icon: 'ic_sc_agenda'),
        if (d.moduloAttivo('clienti')) const ShortcutItem(type: 'nuova-cliente', localizedTitle: 'Nuova cliente', icon: 'ic_sc_cliente'),
        if (d.moduloAttivo('appunti')) const ShortcutItem(type: 'nuovo-appunto', localizedTitle: 'Nuovo appunto', icon: 'ic_sc_appunto'),
      ]);
    } catch (e) {
      debugPrint('Scorciatoie non disponibili: $e');
    }
  }
}
