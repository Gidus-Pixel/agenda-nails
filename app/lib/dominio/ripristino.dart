import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import '../core/date.dart';
import '../core/util.dart';
import '../dati/copie.dart';
import '../dati/dati.dart';
import 'backup.dart';

/* =====================================================================================
   PUNTI DI RIPRISTINO AUTOMATICI (come nella versione web)
   Una copia al giorno di tutti i dati (foto escluse: restano quelle presenti) in un
   archivio separato sullo stesso dispositivo, più una copia prima di ogni operazione che
   sostituisce o cancella dati in blocco. Proteggono dagli errori, NON dalla perdita del
   dispositivo: per quello servono i backup o il cloud.
   ===================================================================================== */

const maxCopie = {'giornaliera': 7, 'prima': 5, 'manuale': 5};
const motiviCopia = {'giornaliera': 'Automatica giornaliera', 'prima': 'Prima di un ripristino o di una pulizia', 'manuale': 'Creata a mano'};

/// Archivio delle copie: in memoria finché main() non imposta quello su file (iOS/Android).
ArchivioCopie archivioCopie = ArchivioCopieMemoria();

/// Notifica l'interfaccia quando l'elenco cambia.
final copieCambiate = ValueNotifier<int>(0);

/// Elenco (solo intestazioni), dalla più recente.
Future<List<Doc>> elencoCopie() async => (await archivioCopie.elenco())..sort((a, b) => comeStr(b['creata']).compareTo(comeStr(a['creata'])));

bool _vuoto(Dati d) => d.elenco('clienti', archiviati: true).isEmpty && d.elenco('appuntamenti', archiviati: true).isEmpty && d.elenco('prodotti', archiviati: true).isEmpty;

Future<Doc> creaCopia(Dati d, String motivo, {DateTime? ora}) async {
  final dati = <String, dynamic>{};
  for (final a in archivi) {
    if (a == 'foto') continue;
    var righe = d.elenco(a, archiviati: true);
    if (a == 'meta') righe = righe.where((m) => !metaLocali.contains(m['id']) && !comeStr(m['id']).startsWith('elim:')).toList();
    dati[a] = righe;
  }
  // le intestazioni delle foto restano (i byte no): ripristinando, le foto attuali rimangono
  int n(String a) => (dati[a] as List).length;
  final adesso = ora ?? DateTime.now();
  final info = <String, dynamic>{
    'id': uid(),
    'creata': isoJs(adesso),
    'giorno': D.key(adesso),
    'motivo': motivo,
    'schemaVersion': schemaVersion,
    'conteggi': {'clienti': n('clienti'), 'appuntamenti': n('appuntamenti'), 'schede': n('schede_lavoro'), 'prodotti': n('prodotti'), 'appunti': n('appunti')},
  };
  await archivioCopie.salva(info, dati);
  // tieni solo le più recenti per ogni motivo
  final stesse = (await elencoCopie()).where((c) => c['motivo'] == motivo).toList();
  for (final c in stesse.skip(maxCopie[motivo] ?? 5)) {
    await archivioCopie.elimina(comeStr(c['id']));
  }
  copieCambiate.value++;
  return info;
}

/// Copia "di sicurezza" prima di operazioni in blocco: non blocca mai l'operazione se fallisce.
Future<void> copiaPrima(Dati d) async {
  if (_vuoto(d)) return;
  try {
    await creaCopia(d, 'prima');
  } catch (e) {
    debugPrint('Punto di ripristino non creato: $e');
  }
}

/// Una copia al giorno (se l'archivio non è vuoto e non ne esiste già una di oggi).
Future<bool> copiaGiornaliera(Dati d, {DateTime? ora}) async {
  final oggi = D.key(ora ?? DateTime.now());
  if (_vuoto(d)) return false;
  if ((await elencoCopie()).any((c) => c['motivo'] == 'giornaliera' && c['giorno'] == oggi)) return false;
  await creaCopia(d, 'giornaliera', ora: ora);
  return true;
}

/// Torna a una copia. Prima salva la situazione attuale (motivo "prima"), così si può annullare.
Future<bool> ripristinaCopia(Dati d, String id) async {
  final elenco = await elencoCopie();
  final info = elenco.where((c) => c['id'] == id).firstOrNull;
  final dati = await archivioCopie.dati(id);
  if (info == null || dati == null) return false;
  await applicaBackup(d, BackupLetto({'app': appId, 'tipo': 'backup-completo', 'schemaVersion': info['schemaVersion'] ?? schemaVersion, 'conFoto': false, 'dati': dati}));
  return true;
}

Timer? _giro;

/// Avvio: prima copia dopo qualche secondo, poi un controllo ogni ora (e al ritorno nell'app).
void avviaCopieAutomatiche(Dati d) {
  Future<void> giro() async {
    try {
      await copiaGiornaliera(d);
    } catch (e) {
      debugPrint('Punto di ripristino non creato: $e');
    }
  }

  _giro?.cancel();
  Timer(const Duration(seconds: 8), giro);
  _giro = Timer.periodic(const Duration(hours: 1), (_) => giro());
}

/// Al ritorno nell'app (un telefono resta aperto per giorni senza riavviare l'app).
Future<void> controllaCopiaGiornaliera(Dati d) async {
  try {
    await copiaGiornaliera(d);
  } catch (_) {}
}
