import 'package:intl/intl.dart';

/// Date locali. Regole (identiche alla web app):
/// - i giorni sono stringhe 'AAAA-MM-GG' costruite con l'ora LOCALE;
/// - gli istanti (inizio/fine appuntamenti) si salvano in ISO UTC;
/// - le somme di giorni usano il costruttore DateTime(a, m, g + n): corrette anche
///   nei giorni di cambio dell'ora legale.
class D {
  static const giorniKey = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom']; // DateTime.weekday 1..7
  static const giorniNome = {'lun': 'Lunedì', 'mar': 'Martedì', 'mer': 'Mercoledì', 'gio': 'Giovedì', 'ven': 'Venerdì', 'sab': 'Sabato', 'dom': 'Domenica'};
  /// Indice JavaScript del giorno (0 = domenica) usato nei blocchi ricorrenti.
  static int jsDay(DateTime d) => d.weekday % 7;

  static String p2(int n) => n.toString().padLeft(2, '0');
  static String key(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${p2(d.month)}-${p2(d.day)}';
  static DateTime daKey(String k) {
    final p = k.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }
  static DateTime combina(String k, String hhmm) {
    final p = k.split('-').map(int.parse).toList();
    final o = hhmm.split(':').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], o[0], o.length > 1 ? o[1] : 0);
  }
  static String hhmm(DateTime d) => '${p2(d.hour)}:${p2(d.minute)}';
  static int minDaHHMM(String s) {
    final o = s.split(':').map(int.parse).toList();
    return o[0] * 60 + (o.length > 1 ? o[1] : 0);
  }
  static String hhmmDaMin(int m) => '${p2(m ~/ 60)}:${p2(m % 60)}';
  static int minutiDelGiorno(DateTime d) => d.hour * 60 + d.minute;
  static DateTime inizioGiorno(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime aggiungiGiorni(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute, d.second, d.millisecond);
  static DateTime aggiungiMinuti(DateTime d, int n) => d.add(Duration(minutes: n));
  static DateTime inizioSettimana(DateTime d) => aggiungiGiorni(inizioGiorno(d), -(d.weekday - 1));
  static String oggiKey() => key(DateTime.now());
  static String giornoKey(DateTime d) => giorniKey[d.weekday - 1];
  static int minutiTra(DateTime a, DateTime b) => (b.difference(a).inSeconds / 60).round();
  static int diffGiorni(String aKey, String bKey) {
    final a = daKey(aKey), b = daKey(bKey);
    return DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
  }
  static String aggiungiGiorniKey(String k, int n) => key(aggiungiGiorni(daKey(k), n));
  static DateTime arrotondaSu(DateTime d, int minuti) {
    var r = DateTime(d.year, d.month, d.day, d.hour, d.minute);
    final resto = minutiDelGiorno(r) % minuti;
    if (resto != 0) r = r.add(Duration(minutes: minuti - resto));
    return r;
  }
  static DateTime daIso(String iso) => DateTime.parse(iso).toLocal();
  static bool stessoGiorno(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Formattazione italiana.
class F {
  static final _euro = NumberFormat.currency(locale: 'it_IT', symbol: '€', decimalDigits: 2);
  static String euro(int? cent) => cent == null ? '' : _euro.format(cent / 100);
  static String maiuscola(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  static String giornoLungo(DateTime d) {
    final stessoAnno = d.year == DateTime.now().year;
    return maiuscola(DateFormat(stessoAnno ? 'EEEE d MMMM' : 'EEEE d MMMM y', 'it').format(d));
  }
  static String giornoMsg(DateTime d) => DateFormat('EEEE d MMMM', 'it').format(d);
  static String giornoBreve(DateTime d) => DateFormat('EEE d MMM', 'it').format(d);
  static String giornoCorto(DateTime d) => maiuscola(DateFormat('EEE d', 'it').format(d));
  static String meseAnno(DateTime d) => maiuscola(DateFormat('MMMM y', 'it').format(d));
  static String data(DateTime? d) => d == null ? '' : DateFormat('dd/MM/y', 'it').format(d);
  static String dataKey(String? k) => (k == null || k.isEmpty) ? '' : data(D.daKey(k));
  static String dataOra(DateTime? d) => d == null ? '' : DateFormat('dd/MM/y, HH:mm', 'it').format(d);
  static String intervallo(DateTime a, DateTime b) => '${D.hhmm(a)}–${D.hhmm(b)}';
  static String durata(int? min) {
    if (min == null) return '';
    final h = min ~/ 60, m = min % 60;
    if (h == 0) return '$m min';
    return m == 0 ? '$h h' : '$h h $m min';
  }
  /// "25,50" → 2550; vuoto → null
  static int? centDaTesto(String? s) {
    if (s == null) return null;
    var t = s.trim().replaceAll('€', '').replaceAll(' ', '');
    if (t.isEmpty) return null;
    if (t.contains(',')) t = t.replaceAll('.', '').replaceAll(',', '.');
    final n = double.tryParse(t);
    return n == null ? null : (n * 100).round();
  }
  static String testoDaCent(int? c) => c == null ? '' : (c / 100).toStringAsFixed(2).replaceAll('.', ',');
}
