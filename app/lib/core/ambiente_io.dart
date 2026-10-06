import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

final Map<String, String> _daFile = {};

/// Solo nelle versioni di prova (debug): le schermate automatiche sul simulatore possono
/// scrivere "agenda-avvio.txt" (righe NOME=valore) nella cartella Documenti dell'app.
Future<void> prepara() async {
  if (!kDebugMode) return;
  try {
    final f = File('${(await getApplicationDocumentsDirectory()).path}/agenda-avvio.txt');
    if (!await f.exists()) return;
    for (final r in (await f.readAsString()).split('\n')) {
      final i = r.indexOf('=');
      if (i > 0) _daFile[r.substring(0, i).trim()] = r.substring(i + 1).trim();
    }
  } catch (_) {}
}

String? variabile(String nome) => Platform.environment[nome] ?? _daFile[nome];
