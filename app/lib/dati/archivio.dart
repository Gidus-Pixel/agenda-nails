import 'dart:convert';
import 'dart:typed_data';

import '../core/util.dart';
import 'archivio_crea_stub.dart' if (dart.library.io) 'archivio_crea_io.dart' as crea;

/// Archivio persistente a "documenti" (come IndexedDB nella web app):
/// ogni collezione contiene documenti JSON con chiave `id`; i byte delle foto sono a parte.
abstract class Archivio {
  Future<void> apri();
  Future<Map<String, List<Doc>>> caricaTutto(List<String> collezioni);
  Future<void> scrivi(String collezione, List<Doc> documenti);
  Future<void> elimina(String collezione, List<String> ids);
  Future<void> sostituisciTutto(Map<String, List<Doc>> dati);
  Future<Uint8List?> leggiBytes(String id);
  Future<void> scriviBytes(String id, Uint8List dati);
  Future<void> eliminaBytes(List<String> ids);
  Future<List<String>> idBytes();
}

/// SQLite su iOS/Android; in memoria su web (anteprima) e nei test.
Archivio creaArchivio({String nome = 'agenda-nails'}) => crea.creaArchivio(nome);

class ArchivioMemoria implements Archivio {
  final Map<String, Map<String, String>> _doc = {};
  final Map<String, Uint8List> _bytes = {};

  @override
  Future<void> apri() async {}

  @override
  Future<Map<String, List<Doc>>> caricaTutto(List<String> collezioni) async => {
        for (final c in collezioni) c: (_doc[c]?.values ?? const <String>[]).map((s) => comeDoc(jsonDecode(s))).toList(),
      };

  @override
  Future<void> scrivi(String collezione, List<Doc> documenti) async {
    final m = _doc.putIfAbsent(collezione, () => {});
    for (final d in documenti) {
      m[comeStr(d['id'])] = jsonEncode(d);
    }
  }

  @override
  Future<void> elimina(String collezione, List<String> ids) async {
    final m = _doc[collezione];
    if (m == null) return;
    for (final id in ids) {
      m.remove(id);
    }
  }

  @override
  Future<void> sostituisciTutto(Map<String, List<Doc>> dati) async {
    _doc.clear();
    for (final e in dati.entries) {
      await scrivi(e.key, e.value);
    }
  }

  @override
  Future<Uint8List?> leggiBytes(String id) async => _bytes[id];

  @override
  Future<void> scriviBytes(String id, Uint8List dati) async => _bytes[id] = dati;

  @override
  Future<void> eliminaBytes(List<String> ids) async {
    for (final id in ids) {
      _bytes.remove(id);
    }
  }

  @override
  Future<List<String>> idBytes() async => _bytes.keys.toList();
}
