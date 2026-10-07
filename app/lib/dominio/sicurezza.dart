import 'dart:typed_data';

import '../core/util.dart';
import '../dati/dati.dart';
import 'cifratura.dart';

/// PIN dell'app: stesso formato della web app (meta "pin", solo su questo dispositivo:
/// non va nei backup né nel cloud). PBKDF2-SHA256, 150000 iterazioni, 256 bit.
/// Protegge da occhi indiscreti: NON cifra i dati.
const iterazioniPin = 150000;

bool pinImpostato(Dati d) => d.meta('pin') is Map;
bool biometriaAttiva(Dati d) => pinImpostato(d) && comeDoc(d.meta('pin'))['biometria'] == true;

/// Numero di cifre del PIN (se noto): permette di verificarlo appena digitato.
int? cifrePin(Dati d) => comeInt(comeDoc(d.meta('pin'))['cifre']);

bool pinValido(String pin) => RegExp(r'^\d{4,8}$').hasMatch(pin);

Future<void> impostaPin(Dati d, String pin, {bool? biometria}) async {
  final sale = Cifratura.casuali(16);
  final hash = await Cifratura.pbkdf2(pin, sale, iterazioniPin, 256);
  final prima = comeDoc(d.meta('pin'));
  await d.scriviMeta('pin', {'sale': b64(sale), 'hash': b64(hash), 'iterazioni': iterazioniPin, 'cifre': pin.length, 'biometria': biometria ?? prima['biometria'] == true});
  d.aggiorna();
}

Future<bool> verificaPin(Dati d, String pin) async {
  final p = comeDoc(d.meta('pin'));
  if (p.isEmpty) return true;
  final h = await Cifratura.pbkdf2(pin, Uint8List.fromList(daB64(comeStr(p['sale']))), comeInt(p['iterazioni']) ?? iterazioniPin, 256);
  return b64(h) == comeStr(p['hash']);
}

Future<void> impostaBiometria(Dati d, bool attiva) async {
  final p = comeDoc(d.meta('pin'));
  if (p.isEmpty) return;
  await d.scriviMeta('pin', {...p, 'biometria': attiva});
  d.aggiorna();
}

Future<void> rimuoviPin(Dati d) async {
  await d.eliminaMeta(['pin']);
  d.aggiorna();
}
