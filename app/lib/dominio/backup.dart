import 'dart:convert';
import 'dart:typed_data';

import '../core/config.dart';
import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import 'cifratura.dart';

const magicCifrato = 'AGENDA-NAILS-CIFRATO-1\n';

/// Backup completo, nello STESSO formato della web app: si può ripristinare indifferentemente
/// su web, iPhone, iPad o Android.
Future<Uint8List> creaBackup(Dati d, {bool conFoto = true}) async {
  final dati = <String, dynamic>{};
  for (final a in archivi) {
    if (a == 'foto') continue;
    var righe = d.elenco(a, archiviati: true);
    if (a == 'meta') righe = righe.where((m) => !metaLocali.contains(m['id']) && !comeStr(m['id']).startsWith('elim:')).toList();
    dati[a] = righe;
  }
  final foto = <Doc>[];
  if (conFoto) {
    for (final f in d.elenco('foto', archiviati: true)) {
      final b = await d.bytesFoto(comeStr(f['id']));
      if (b == null) continue;
      final tipo = comeStr(f['blobTipo']).isEmpty ? 'image/jpeg' : comeStr(f['blobTipo']);
      final copia = Map<String, dynamic>.from(f)..remove('blobTipo');
      copia['dataURL'] = 'data:$tipo;base64,${base64Encode(b)}';
      foto.add(copia);
    }
  }
  dati['foto'] = foto;
  final obj = {
    'app': appId, 'tipo': 'backup-completo', 'schemaVersion': schemaVersion, 'versioneApp': versioneApp,
    'esportatoIl': adessoIso(), 'attivita': d.nomeAttivita, 'conFoto': conFoto, 'dati': dati,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(obj)));
}

String nomeFileBackup(Dati d, {bool cifrato = false}) {
  final ora = DateTime.now();
  var nome = norm(d.nomeAttivita).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
  if (nome.isEmpty) nome = 'agenda';
  return 'backup-$nome-${D.key(ora)}-${D.hhmm(ora).replaceAll(':', '')}${cifrato ? '.agendabak' : '.json'}';
}

bool eBackupCifrato(Uint8List b) => b.length > magicCifrato.length && utf8.decode(b.sublist(0, magicCifrato.length), allowMalformed: true) == magicCifrato;

/// Backup cifrato con password (stesso formato della web app).
Future<Uint8List> cifraBackup(Uint8List chiaro, String password, {String attivita = ''}) async {
  final sale = Cifratura.casuali(16), iv = Cifratura.casuali(12);
  const iter = 310000;
  final chiave = await Cifratura.pbkdf2(password, sale, iter, 256);
  final tutto = await Cifratura.cifra(chiave, chiaro, iv: iv);
  final testa = jsonEncode({
    'app': appId, 'tipo': 'backup-cifrato', 'formato': 1,
    'kdf': {'nome': 'PBKDF2', 'hash': 'SHA-256', 'iterazioni': iter, 'sale': b64(sale)},
    'cifratura': {'nome': 'AES-GCM', 'lunghezza': 256, 'iv': b64(iv)},
    'esportatoIl': adessoIso(), 'attivita': attivita,
  });
  final out = BytesBuilder(copy: false)
    ..add(utf8.encode(magicCifrato))
    ..add(utf8.encode(testa))
    ..add([10])
    ..add(tutto.sublist(12));
  return out.toBytes();
}

Future<Uint8List> decifraBackup(Uint8List file, String password) async {
  final inizio = magicCifrato.length;
  final fine = file.indexOf(10, inizio);
  if (fine < 0) throw const FormatException('File cifrato danneggiato.');
  final testa = comeDoc(jsonDecode(utf8.decode(file.sublist(inizio, fine))));
  if (testa['app'] != appId || testa['tipo'] != 'backup-cifrato') throw const FormatException('Questo file non è un backup cifrato di questa agenda.');
  final kdf = comeDoc(testa['kdf']);
  final chiave = await Cifratura.pbkdf2(password, daB64(comeStr(kdf['sale'])), comeInt(kdf['iterazioni']) ?? 310000, 256);
  return Cifratura.decifraSeparato(chiave, daB64(comeStr(comeDoc(testa['cifratura'])['iv'])), file.sublist(fine + 1));
}

class BackupLetto {
  BackupLetto(this.obj);
  final Doc obj;
  Doc get dati => comeDoc(obj['dati']);
  int conta(String a) => (dati[a] as List?)?.length ?? 0;
  bool get conFoto => obj['conFoto'] != false;
  String get attivita => comeStr(obj['attivita']);
  DateTime? get creato => comeStr(obj['esportatoIl']).isEmpty ? null : D.daIso(comeStr(obj['esportatoIl']));
}

BackupLetto leggiBackup(Uint8List chiaro) {
  final dynamic j;
  try {
    j = jsonDecode(utf8.decode(chiaro));
  } catch (_) {
    throw const FormatException('Il file non è leggibile (non è un backup valido).');
  }
  final obj = comeDoc(j);
  if (obj['app'] != appId) throw const FormatException('Questo file non è un backup di questa agenda.');
  if (obj['tipo'] == 'configurazione') throw const FormatException('Questo è un file di configurazione, non un backup completo.');
  if (obj['tipo'] != 'backup-completo' || obj['dati'] is! Map) throw const FormatException('Il file non contiene un backup completo.');
  final v = comeInt(obj['schemaVersion']);
  if (v == null) throw const FormatException('Versione del backup non riconosciuta.');
  if (v > schemaVersion) throw FormatException("Il backup è stato creato con una versione più recente dell'agenda (schema $v). Aggiorna l'app prima di ripristinarlo.");
  return BackupLetto(obj);
}

/// Sostituisce tutti i dati del dispositivo con quelli del backup.
Future<void> applicaBackup(Dati d, BackupLetto b) async {
  final dati = <String, List<Doc>>{};
  for (final a in archivi) {
    if (a == 'foto') continue;
    dati[a] = comeListaDoc(b.dati[a]);
  }
  final fotoBytes = <String, Uint8List>{};
  final foto = <Doc>[];
  if (b.conFoto) {
    for (final f in comeListaDoc(b.dati['foto'])) {
      final url = comeStr(f['dataURL']);
      final i = url.indexOf(',');
      if (i < 0) continue;
      final tipo = RegExp(r'data:([^;]+)').firstMatch(url)?.group(1) ?? 'image/jpeg';
      final rec = Map<String, dynamic>.from(f)..remove('dataURL');
      rec['blobTipo'] = tipo;
      foto.add(rec);
      fotoBytes[comeStr(f['id'])] = base64Decode(url.substring(i + 1));
    }
  }
  dati['foto'] = foto;
  await d.sostituisciTutto(dati, fotoBytes: fotoBytes, tieniFotoAttuali: !b.conFoto);
}
