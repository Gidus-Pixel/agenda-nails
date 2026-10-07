import 'copie_crea_stub.dart' if (dart.library.io) 'copie_crea_io.dart' as crea;
import '../core/util.dart';

/// Dove si tengono i punti di ripristino: separati dall'archivio principale, così una
/// cancellazione o un ripristino sbagliato non li tocca.
/// Ogni copia ha un'intestazione leggera (per l'elenco) e i dati completi, letti solo al ripristino.
abstract class ArchivioCopie {
  Future<List<Doc>> elenco();
  Future<Doc?> dati(String id);
  Future<void> salva(Doc info, Doc dati);
  Future<void> elimina(String id);
}

/// Su iOS/Android file nella cartella di supporto dell'app; su web (anteprima) in memoria.
ArchivioCopie creaArchivioCopie() => crea.creaArchivioCopie();

class ArchivioCopieMemoria implements ArchivioCopie {
  final Map<String, (Doc, Doc)> _c = {};
  @override
  Future<List<Doc>> elenco() async => [for (final v in _c.values) clonaDoc(v.$1)];
  @override
  Future<Doc?> dati(String id) async => _c[id] == null ? null : clonaDoc(_c[id]!.$2);
  @override
  Future<void> salva(Doc info, Doc dati) async => _c[comeStr(info['id'])] = (clonaDoc(info), clonaDoc(dati));
  @override
  Future<void> elimina(String id) async => _c.remove(id);
}
