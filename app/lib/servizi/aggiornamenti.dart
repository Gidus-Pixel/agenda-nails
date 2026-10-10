import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

import '../core/util.dart';
import '../dati/dati.dart';

/// Una versione pubblicata (file versione.json accanto all'APK nella pagina Releases).
class VersioneDisponibile {
  VersioneDisponibile({required this.build, required this.versione, required this.apk, this.note = '', this.data});
  final int build;
  final String versione, apk, note;
  final DateTime? data;

  static VersioneDisponibile? da(dynamic j) {
    final m = comeDoc(j);
    final b = comeInt(m['build']);
    final apk = comeStr(m['apk']);
    if (b == null || !apk.startsWith('https://')) return null;
    return VersioneDisponibile(build: b, versione: comeStr(m['versione']), apk: apk, note: comeStr(m['note']), data: DateTime.tryParse(comeStr(m['data']))?.toLocal());
  }
}

/// Controllo degli aggiornamenti per l'APK installato fuori dal Play Store.
/// Non scarica né installa nulla da solo: avvisa e apre il download nel browser.
class Aggiornamenti extends ChangeNotifier {
  Aggiornamenti._();
  static final istanza = Aggiornamenti._();

  bool get supportati => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  int? buildAttuale;
  String versioneAttuale = '';
  VersioneDisponibile? disponibile;
  DateTime? ultimoControllo;
  String? errore;
  bool inCorso = false;

  static String indirizzo(Dati d) => comeStr(comeDoc(d.cfg['aggiornamenti'])['url']);

  /// true se la versione [v] è più nuova di quella installata e non è stata messa da parte.
  bool daProporre(Dati d) {
    final v = disponibile;
    return v != null && v.build != comeInt(d.meta('aggiornamentoIgnorato'));
  }

  Future<void> avvia(Dati d) async {
    if (!supportati) return;
    try {
      final p = await PackageInfo.fromPlatform();
      buildAttuale = int.tryParse(p.buildNumber);
      versioneAttuale = p.version;
    } catch (_) {}
    Timer(const Duration(seconds: 12), () => controlla(d));
  }

  /// Tornando nell'app: al massimo un controllo ogni 6 ore.
  void seServe(Dati d) {
    final u = ultimoControllo;
    if (supportati && (u == null || DateTime.now().difference(u).inHours >= 6)) controlla(d);
  }

  Future<VersioneDisponibile?> controlla(Dati d) async {
    final url = indirizzo(d);
    if (!supportati || url.isEmpty || inCorso) return disponibile;
    inCorso = true;
    errore = null;
    notifyListeners();
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception('risposta ${r.statusCode}');
      final v = VersioneDisponibile.da(jsonDecode(utf8.decode(r.bodyBytes)));
      final attuale = buildAttuale ?? 0;
      disponibile = v != null && v.build > attuale ? v : null;
      ultimoControllo = DateTime.now();
    } catch (e) {
      errore = 'Controllo non riuscito: verifica la connessione.';
      debugPrint('Aggiornamenti: $e');
    } finally {
      inCorso = false;
      notifyListeners();
    }
    return disponibile;
  }
}
