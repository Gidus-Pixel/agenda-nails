import 'package:agenda_nails/core/date.dart';
import 'package:agenda_nails/core/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// I test girano con TZ=Europe/Rome (vedi il flusso di lavoro): i giorni del cambio dell'ora
/// devono avere 23 o 25 ore senza spostare le date.
void main() {
  setUpAll(() => initializeDateFormatting('it'));
  final roma = DateTime(2026, 7, 1).timeZoneOffset == const Duration(hours: 2) && DateTime(2026, 1, 1).timeZoneOffset == const Duration(hours: 1);

  test('chiavi di data locali (niente toISOString)', () {
    expect(D.key(DateTime(2026, 3, 5, 0, 30)), '2026-03-05');
    expect(D.key(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    expect(D.aggiungiGiorniKey('2026-12-31', 1), '2027-01-01');
    expect(D.diffGiorni('2026-10-24', '2026-10-26'), 2);
    expect(D.diffGiorni('2027-03-27', '2027-03-29'), 2);
    expect(D.giornoKey(D.daKey('2026-10-06')), 'mar');
    expect(D.jsDay(D.daKey('2026-10-04')), 0); // domenica
    expect(D.key(D.inizioSettimana(D.daKey('2026-10-04'))), '2026-09-28'); // la settimana inizia di lunedì
  });

  test('ora legale → solare (25 ottobre 2026)', () {
    final a = D.combina('2026-10-25', '00:00'), b = D.combina('2026-10-26', '00:00');
    expect(D.key(D.aggiungiGiorni(a, 1)), '2026-10-26');
    expect(D.hhmm(D.combina('2026-10-25', '10:00')), '10:00');
    expect(D.hhmm(D.aggiungiGiorni(D.combina('2026-10-24', '10:00'), 1)), '10:00');
    if (roma) expect(D.minutiTra(a, b), 25 * 60);
  });

  test('ora solare → legale (28 marzo 2027)', () {
    final a = D.combina('2027-03-28', '00:00'), b = D.combina('2027-03-29', '00:00');
    expect(D.key(D.aggiungiGiorni(D.combina('2027-03-27', '09:00'), 1)), '2027-03-28');
    expect(D.hhmm(D.aggiungiGiorni(D.combina('2027-03-27', '09:00'), 1)), '09:00');
    if (roma) expect(D.minutiTra(a, b), 23 * 60);
  });

  test('ISO identico a JavaScript', () {
    final t = DateTime.utc(2026, 10, 6, 10, 0, 0, 5);
    expect(isoJs(t), '2026-10-06T10:00:00.005Z');
    expect(isoJs(D.daIso('2026-10-06T10:00:00.000Z')), '2026-10-06T10:00:00.000Z');
  });

  test('importi in centesimi', () {
    expect(F.centDaTesto('12,50'), 1250);
    expect(F.centDaTesto('40'), 4000);
    expect(F.centDaTesto(''), isNull);
    expect(F.testoDaCent(5500), '55,00');
    expect(F.euro(4000).replaceAll(' ', ' '), '40,00 €');
  });
}
