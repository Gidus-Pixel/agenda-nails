import 'package:agenda_nails/core/telefono.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizzazione dei numeri italiani', () {
    expect(normalizzaTelefono('333 123 4567'), '+393331234567');
    expect(normalizzaTelefono('+39 333 1234567'), '+393331234567');
    expect(normalizzaTelefono('0039 3331234567'), '+393331234567');
    expect(normalizzaTelefono('06 12345678'), '+390612345678'); // fisso: lo 0 resta
    expect(normalizzaTelefono('393331234567'), '+393331234567');
    expect(normalizzaTelefono(''), '');
  });

  test('numero per WhatsApp: solo cifre, senza + né 00', () {
    expect(numeroWhatsApp('333 1234567'), '393331234567');
    expect(numeroWhatsApp('06 12345678'), '390612345678');
    expect(numeroWhatsApp('+41 79 123 45 67'), '41791234567');
  });

  test('link wa.me con testo codificato', () {
    final u = linkWhatsApp('3331234567', 'Ciao Anna, a domani alle 10:30 💅');
    expect(u.toString(), startsWith('https://wa.me/393331234567?text=Ciao%20Anna%2C%20a%20domani'));
    expect(linkWhatsApp('', 'x'), isNull);
  });

  test('modello del messaggio', () {
    expect(compilaModello('Ciao {nome}, {giorno} alle {ora} da {attivita}', {'nome': 'Anna', 'giorno': 'martedì 6 ottobre', 'ora': '10:30', 'attivita': 'Nails'}), 'Ciao Anna, martedì 6 ottobre alle 10:30 da Nails');
    expect(compilaModello('{sconosciuto}', {}), '{sconosciuto}');
  });
}
