import 'dart:convert';
import 'dart:math';

typedef Doc = Map<String, dynamic>;

final Random _rnd = Random.secure();

/// UUID v4 come `crypto.randomUUID()` della versione web.
String uid() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// ISO in UTC con millisecondi, identico a `Date.toISOString()` di JavaScript
/// (necessario per confrontare `updatedAt` tra web e app).
String isoJs(DateTime d) {
  final u = DateTime.fromMillisecondsSinceEpoch(d.millisecondsSinceEpoch, isUtc: true);
  String p(int n, [int w = 2]) => n.toString().padLeft(w, '0');
  return '${p(u.year, 4)}-${p(u.month)}-${p(u.day)}T${p(u.hour)}:${p(u.minute)}:${p(u.second)}.${p(u.millisecond, 3)}Z';
}

String adessoIso() => isoJs(DateTime.now());

/// Copia profonda di dati JSON.
T clona<T>(T v) => v == null ? v : jsonDecode(jsonEncode(v)) as T;

Doc clonaDoc(Doc d) => (jsonDecode(jsonEncode(d)) as Map).cast<String, dynamic>();

int? comeInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.isFinite ? v.round() : null;
  if (v is String) return int.tryParse(v) ?? double.tryParse(v.replaceAll(',', '.'))?.round();
  return null;
}

double? comeDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.replaceAll(',', '.'));
  return null;
}

String comeStr(dynamic v) => v == null ? '' : v.toString();

bool comeBool(dynamic v) => v == true || v == 1 || v == 'true';

List<Doc> comeListaDoc(dynamic v) => v is List ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Doc>[];

List<String> comeListaStr(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : <String>[];

Doc comeDoc(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

/// Testo normalizzato per le ricerche (minuscolo, senza accenti).
String norm(String s) {
  const da = 'àáâäãåèéêëìíîïòóôöõùúûüçñ';
  const a = 'aaaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = da.indexOf(ch);
    b.write(i >= 0 ? a[i] : ch);
  }
  return b.toString();
}

/// Unione profonda di mappe JSON (come `unisciProfondo` della web app).
dynamic unisciProfondo(dynamic base, dynamic sopra) {
  if (sopra == null) return clona(base);
  if (base is Map && sopra is Map) {
    final r = <String, dynamic>{...clona(base.cast<String, dynamic>())};
    sopra.forEach((k, v) {
      r[k.toString()] = base.containsKey(k) ? unisciProfondo(base[k], v) : clona(v);
    });
    return r;
  }
  return clona(sopra);
}
