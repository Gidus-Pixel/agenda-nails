import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../dati/dati.dart';
import '../dominio/backup.dart';

/// Copia per il "Backup di Google" di Android: un file con tutti i dati (senza foto, per stare
/// nei 25 MB concessi a ogni app) nella cartella che Android salva sul Google Drive dell'utente.
/// Se l'app viene reinstallata e Android ripristina il file, l'app propone di recuperare i dati.
/// Copia ritrovata all'avvio (da proporre nella schermata Oggi).
final backupAndroidTrovato = ValueNotifier<BackupLetto?>(null);

class BackupAndroid {
  static bool get supportato => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static DateTime? _ultimo;

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}/backup-google/agenda.json');

  static bool _vuoto(Dati d) => d.elenco('clienti', archiviati: true).isEmpty && d.elenco('appuntamenti', archiviati: true).isEmpty && d.elenco('prodotti', archiviati: true).isEmpty;

  /// Aggiorna il file (al massimo una volta ogni 30 minuti, salvo [subito]).
  static Future<void> salva(Dati d, {bool subito = false}) async {
    if (!supportato || _vuoto(d)) return;
    final u = _ultimo;
    if (!subito && u != null && DateTime.now().difference(u).inMinutes < 30) return;
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(await creaBackup(d, conFoto: false), flush: true);
      await tmp.rename(f.path);
      _ultimo = DateTime.now();
    } catch (e) {
      debugPrint('Copia per il backup di Android non scritta: $e');
    }
  }

  /// All'avvio con l'archivio vuoto: c'è un file ripristinato da Android?
  static Future<BackupLetto?> trovato(Dati d) async {
    if (!supportato || !_vuoto(d) || d.meta('backupAndroidIgnorato') == true) return null;
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final b = leggiBackup(await f.readAsBytes());
      if (b.conta('clienti') + b.conta('appuntamenti') + b.conta('prodotti') == 0) return null;
      return b;
    } catch (_) {
      return null;
    }
  }
}
