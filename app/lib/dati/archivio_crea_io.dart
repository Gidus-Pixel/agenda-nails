import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/util.dart';
import 'archivio.dart';

/// iOS / Android: SQLite (sqflite). Nei test si passa direttamente un ArchivioMemoria.
Archivio creaArchivio(String nome) => ArchivioSqlite(nome);

class ArchivioSqlite implements Archivio {
  ArchivioSqlite(this.nome);
  final String nome;
  late Database _db;

  @override
  Future<void> apri() async {
    final cartella = await getDatabasesPath();
    _db = await openDatabase(
      p.join(cartella, '$nome.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('CREATE TABLE doc (collezione TEXT NOT NULL, id TEXT NOT NULL, dati TEXT NOT NULL, PRIMARY KEY (collezione, id))');
        await db.execute('CREATE TABLE bytes (id TEXT PRIMARY KEY, dati BLOB NOT NULL)');
      },
    );
  }

  @override
  Future<Map<String, List<Doc>>> caricaTutto(List<String> collezioni) async {
    final out = {for (final c in collezioni) c: <Doc>[]};
    final righe = await _db.query('doc', columns: ['collezione', 'dati']);
    for (final r in righe) {
      final c = r['collezione'] as String;
      (out[c] ??= <Doc>[]).add(comeDoc(jsonDecode(r['dati'] as String)));
    }
    return out;
  }

  @override
  Future<void> scrivi(String collezione, List<Doc> documenti) async {
    if (documenti.isEmpty) return;
    final b = _db.batch();
    for (final d in documenti) {
      b.insert('doc', {'collezione': collezione, 'id': comeStr(d['id']), 'dati': jsonEncode(d)}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  @override
  Future<void> elimina(String collezione, List<String> ids) async {
    if (ids.isEmpty) return;
    final b = _db.batch();
    for (final id in ids) {
      b.delete('doc', where: 'collezione = ? AND id = ?', whereArgs: [collezione, id]);
    }
    await b.commit(noResult: true);
  }

  @override
  Future<void> sostituisciTutto(Map<String, List<Doc>> dati) async {
    await _db.transaction((tx) async {
      await tx.delete('doc');
      final b = tx.batch();
      for (final e in dati.entries) {
        for (final d in e.value) {
          b.insert('doc', {'collezione': e.key, 'id': comeStr(d['id']), 'dati': jsonEncode(d)}, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await b.commit(noResult: true);
    });
  }

  @override
  Future<Uint8List?> leggiBytes(String id) async {
    final r = await _db.query('bytes', columns: ['dati'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    final v = r.first['dati'];
    return v is Uint8List ? v : (v is List<int> ? Uint8List.fromList(v) : null);
  }

  @override
  Future<void> scriviBytes(String id, Uint8List dati) async {
    await _db.insert('bytes', {'id': id, 'dati': dati}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> eliminaBytes(List<String> ids) async {
    if (ids.isEmpty) return;
    final b = _db.batch();
    for (final id in ids) {
      b.delete('bytes', where: 'id = ?', whereArgs: [id]);
    }
    await b.commit(noResult: true);
  }

  @override
  Future<List<String>> idBytes() async => (await _db.query('bytes', columns: ['id'])).map((r) => r['id'] as String).toList();
}
