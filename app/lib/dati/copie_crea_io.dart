import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/util.dart';
import 'copie.dart';

ArchivioCopie creaArchivioCopie() => ArchivioCopieFile();

/// Due file per copia: <id>.info.json (piccolo) e <id>.dati.json (tutti i dati, foto escluse).
class ArchivioCopieFile implements ArchivioCopie {
  Directory? _dir;

  Future<Directory> _cartella() async {
    final d = _dir ?? Directory('${(await getApplicationSupportDirectory()).path}/ripristino');
    if (!await d.exists()) await d.create(recursive: true);
    return _dir = d;
  }

  static bool _idValido(String id) => RegExp(r'^[A-Za-z0-9-]+$').hasMatch(id);

  @override
  Future<List<Doc>> elenco() async {
    final dir = await _cartella();
    final out = <Doc>[];
    await for (final f in dir.list()) {
      if (f is! File || !f.path.endsWith('.info.json')) continue;
      try {
        out.add(comeDoc(jsonDecode(await f.readAsString())));
      } catch (_) {
        // file rovinato (es. scrittura interrotta): si ignora
      }
    }
    return out;
  }

  @override
  Future<Doc?> dati(String id) async {
    if (!_idValido(id)) return null;
    final f = File('${(await _cartella()).path}/$id.dati.json');
    if (!await f.exists()) return null;
    return comeDoc(jsonDecode(await f.readAsString()));
  }

  @override
  Future<void> salva(Doc info, Doc dati) async {
    final id = comeStr(info['id']);
    if (!_idValido(id)) throw ArgumentError('id non valido');
    final dir = await _cartella();
    // prima i dati, poi l'intestazione: una copia compare nell'elenco solo se è completa
    final tmp = File('${dir.path}/$id.dati.tmp');
    await tmp.writeAsString(jsonEncode(dati), flush: true);
    await tmp.rename('${dir.path}/$id.dati.json');
    await File('${dir.path}/$id.info.json').writeAsString(jsonEncode(info), flush: true);
  }

  @override
  Future<void> elimina(String id) async {
    if (!_idValido(id)) return;
    final dir = await _cartella();
    for (final n in ['$id.info.json', '$id.dati.json']) {
      final f = File('${dir.path}/$n');
      if (await f.exists()) await f.delete();
    }
  }
}
