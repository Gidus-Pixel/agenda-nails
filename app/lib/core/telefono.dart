/// Numeri di telefono in formato internazionale "+393331234567" (come la web app).
/// - "+39 333 123 4567" / "0039…" → prefisso già presente
/// - "333 1234567" (cellulare) → +39 3331234567
/// - "06 12345678" (fisso) → +39 0612345678 (lo 0 del prefisso NON si toglie)
String normalizzaTelefono(String? raw, {String prefisso = '39'}) {
  if (raw == null) return '';
  final s = raw.trim();
  final cifre = s.replaceAll(RegExp(r'\D'), '');
  if (cifre.isEmpty) return '';
  final pref = prefisso.replaceAll(RegExp(r'\D'), '').isEmpty ? '39' : prefisso.replaceAll(RegExp(r'\D'), '');
  if (s.startsWith('+')) return '+$cifre';
  if (cifre.startsWith('00')) return '+${cifre.substring(2)}';
  if (cifre.startsWith(pref) && cifre.length >= pref.length + 9) return '+$cifre';
  return '+$pref$cifre';
}

String numeroWhatsApp(String tel, {String prefisso = '39'}) => normalizzaTelefono(tel, prefisso: prefisso).replaceAll(RegExp(r'\D'), '');

String telefonoLeggibile(String? tel) {
  if (tel == null || tel.isEmpty) return '';
  final m = RegExp(r'^\+39(\d+)$').firstMatch(tel);
  if (m == null) return tel;
  final n = m.group(1)!;
  if (n.startsWith('3') && n.length == 10) return '+39 ${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}';
  return '+39 $n';
}

Uri? linkWhatsApp(String? tel, String testo, {String prefisso = '39'}) {
  if (tel == null || tel.isEmpty) return null;
  final n = numeroWhatsApp(tel, prefisso: prefisso);
  if (n.isEmpty) return null;
  return Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(testo)}');
}

String compilaModello(String modello, Map<String, String> valori) =>
    modello.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) => valori[m.group(1)] ?? m.group(0)!);
