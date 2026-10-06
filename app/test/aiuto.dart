import 'package:agenda_nails/core/util.dart';
import 'package:agenda_nails/dati/archivio.dart';
import 'package:agenda_nails/dati/dati.dart';

/// Dati in memoria con orari: mar–ven 9–13 / 14:30–19:30, sab 9–14.
Future<Dati> datiDiProva({bool orari = true}) async {
  final d = Dati(ArchivioMemoria());
  await d.avvia();
  if (orari) {
    final c = clonaDoc(d.cfg);
    c['attivita'] = {...comeDoc(c['attivita']), 'nome': 'Nails Test'};
    c['orari'] = {
      'lun': [], 'dom': [],
      for (final g in ['mar', 'mer', 'gio', 'ven']) g: [['09:00', '13:00'], ['14:30', '19:30']],
      'sab': [['09:00', '14:00']],
    };
    await d.salvaConfig(c);
  }
  return d;
}
