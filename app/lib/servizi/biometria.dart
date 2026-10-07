import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Face ID / Touch ID / impronta. Su web e dove non è disponibile risponde "non disponibile".
class Biometria {
  Biometria._();
  static final _auth = LocalAuthentication();

  /// Nome da mostrare: "Face ID", "Touch ID", "l'impronta" o null se non disponibile.
  static Future<String?> disponibile() async {
    if (kIsWeb) return null;
    try {
      if (!await _auth.isDeviceSupported() || !await _auth.canCheckBiometrics) return null;
      final tipi = await _auth.getAvailableBiometrics();
      if (tipi.isEmpty) return null;
      if (defaultTargetPlatform == TargetPlatform.iOS) return tipi.contains(BiometricType.face) ? 'Face ID' : 'Touch ID';
      return tipi.contains(BiometricType.face) && !tipi.contains(BiometricType.fingerprint) ? 'il riconoscimento del volto' : "l'impronta";
    } catch (_) {
      return null;
    }
  }

  /// true se la persona si è autenticata. Gli errori (annullato, troppi tentativi…) danno false.
  static Future<bool> verifica(String motivo) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(localizedReason: motivo, biometricOnly: true, persistAcrossBackgrounding: true);
    } catch (_) {
      return false;
    }
  }
}
