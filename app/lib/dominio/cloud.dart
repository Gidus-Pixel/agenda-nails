import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/date.dart';
import '../core/util.dart';
import '../dati/dati.dart';
import 'cifratura.dart';

/// Cloud cifrato: STESSO protocollo e STESSA cifratura della web app, così web, iPhone, iPad e
/// Android dello stesso salone si sincronizzano tra loro. Il server vede solo dati illeggibili.
const _testoVerifica = 'agenda-nails:password-ok';
const _iterazioni = 310000;
final List<String> archiviCloud = archivi.where((a) => a != 'meta').toList();

class ErroreCloud implements Exception {
  ErroreCloud(this.messaggio, {this.codice = '', this.stato = 0});
  final String messaggio, codice;
  final int stato;
  @override
  String toString() => messaggio;
}

class Cloud extends ChangeNotifier {
  Cloud(this.d) {
    d.suModifica = (_) => programma();
  }
  final Dati d;
  ({String stato, String testo}) esito = (stato: 'spento', testo: '');
  Future<Map<String, dynamic>?>? _inCorso;
  Timer? _timer, _periodico;
  Uint8List? _aes, _hmac;

  Doc get stato => comeDoc(d.meta('cloud'));
  bool get attivo => stato['token'] != null && stato['chiave'] != null && stato['attivo'] == true;
  bool get configurato => stato.isNotEmpty;
  String get url => (comeStr(stato['url']).isNotEmpty ? comeStr(stato['url']) : comeStr(comeDoc(d.cfg['cloud'])['url'])).replaceAll(RegExp(r'/+$'), '');

  Future<void> avvia() async {
    _caricaChiavi();
    if (comeBool(stato['serveNuovaPassword'])) {
      _esito('errore', 'Serve di nuovo la password del cloud');
    } else if (comeBool(stato['scollegato'])) {
      _esito('errore', 'Dispositivo scollegato dal cloud');
    } else if (attivo) {
      _esito('ok', stato['ultimaSync'] != null ? 'Ultima sincronizzazione ${F.dataOra(D.daIso(comeStr(stato['ultimaSync'])))}' : 'Cloud attivo');
      programma(const Duration(milliseconds: 1500));
    }
    _periodico?.cancel();
    _periodico = Timer.periodic(const Duration(minutes: 2), (_) => sincronizza());
  }

  void _caricaChiavi() {
    final s = stato;
    _aes = s['chiave'] != null ? daB64(comeStr(s['chiave'])) : null;
    _hmac = s['hmac'] != null ? daB64(comeStr(s['hmac'])) : null;
  }

  Future<void> _salva(Map<String, dynamic> modifiche) async {
    final s = {...stato, ...modifiche}..removeWhere((k, v) => v == null);
    await d.scriviMeta('cloud', s);
    _caricaChiavi();
    notifyListeners();
  }

  void _esito(String s, String t) {
    esito = (stato: s, testo: t);
    notifyListeners();
  }

  void programma([Duration ritardo = const Duration(seconds: 4)]) {
    if (!attivo) return;
    _timer?.cancel();
    _timer = Timer(ritardo, () => sincronizza());
  }

  /* ---------------- HTTP ---------------- */
  Future<Map<String, dynamic>> _chiama(String percorso, {String metodo = 'GET', Object? corpo, bool autenticato = true, String? base}) async {
    final b = (base ?? url).replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty) throw ErroreCloud('Indirizzo del servizio cloud non impostato.', codice: 'url');
    final headers = <String, String>{
      if (corpo != null) 'Content-Type': 'application/json',
      if (autenticato && stato['token'] != null) 'Authorization': 'Bearer ${stato['token']}',
    };
    final uri = Uri.parse(b + percorso);
    http.Response r;
    try {
      final f = switch (metodo) {
        'POST' => http.post(uri, headers: headers, body: corpo == null ? null : jsonEncode(corpo)),
        'DELETE' => http.delete(uri, headers: headers),
        _ => http.get(uri, headers: headers),
      };
      r = await f.timeout(const Duration(seconds: 45));
    } catch (_) {
      throw ErroreCloud('Cloud non raggiungibile (sei offline?)', codice: 'rete');
    }
    Map<String, dynamic> j = {};
    try {
      j = comeDoc(jsonDecode(utf8.decode(r.bodyBytes)));
    } catch (_) {}
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw ErroreCloud(comeStr(j['messaggio']).isEmpty ? 'Errore del cloud (${r.statusCode})' : comeStr(j['messaggio']), codice: comeStr(j['errore']), stato: r.statusCode);
    }
    return j;
  }

  /* ---------------- chiavi e pacchetti ---------------- */
  static Future<({Uint8List aes, Uint8List hmac})> derivaChiavi(String password, String saleB64) async {
    final bits = await Cifratura.pbkdf2(password, daB64(saleB64), _iterazioni, 512);
    return (aes: bits.sublist(0, 32), hmac: bits.sublist(32));
  }

  static Future<String> creaVerificatore(Uint8List aes) async => b64(await Cifratura.cifra(aes, utf8.encode(_testoVerifica)));
  static Future<bool> controllaVerificatore(Uint8List aes, String ver) async {
    try {
      return utf8.decode(await Cifratura.decifra(aes, daB64(ver))) == _testoVerifica;
    } catch (_) {
      return false;
    }
  }

  static Future<String> chiaveRecord(Uint8List hmac, String archivio, String id) async => b64url(await Cifratura.hmac(hmac, utf8.encode('$archivio\u0000$id')));

  static Uint8List impacchetta(Object oggetto, [Uint8List? binario]) {
    final j = utf8.encode(jsonEncode(oggetto));
    final out = Uint8List(5 + j.length + (binario?.length ?? 0));
    out[0] = 1;
    ByteData.sublistView(out).setUint32(1, j.length);
    out.setRange(5, 5 + j.length, j);
    if (binario != null) out.setRange(5 + j.length, out.length, binario);
    return out;
  }

  static ({Doc oggetto, Uint8List? binario}) spacchetta(Uint8List b) {
    if (b.isEmpty || b[0] != 1) throw ErroreCloud('Formato cloud non riconosciuto');
    final n = ByteData.sublistView(b).getUint32(1);
    final oggetto = comeDoc(jsonDecode(utf8.decode(b.sublist(5, 5 + n))));
    final resto = b.sublist(5 + n);
    return (oggetto: oggetto, binario: resto.isEmpty ? null : resto);
  }

  /* ---------------- invio ---------------- */
  Future<int> _invia({bool tutto = false, void Function(int, int)? avanzamento}) async {
    final inizio = adessoIso();
    final dopo = tutto ? '' : comeStr(stato['ultimoPush']);
    final voci = <({String archivio, Doc? record, Doc? lapide})>[];
    for (final a in archiviCloud) {
      for (final r in d.elenco(a, archiviati: true)) {
        final u = comeStr(r['updatedAt']);
        if (dopo.isEmpty || u.isEmpty || u.compareTo(dopo) > 0) voci.add((archivio: a, record: r, lapide: null));
      }
    }
    final lapidi = d.elenco('meta', archiviati: true).where((m) => comeStr(m['id']).startsWith('elim:')).toList();
    for (final l in lapidi) {
      voci.add((archivio: comeStr(comeDoc(l['valore'])['archivio']), record: null, lapide: l));
    }
    var lotto = <Map<String, String>>[];
    var byte = 0;
    var inviati = 0;
    Future<void> spedisci() async {
      if (lotto.isEmpty) return;
      final r = await _chiama('/v1/push', metodo: 'POST', corpo: {'generazione': stato['generazione'], 'record': lotto});
      final seq = comeInt(r['seq']) ?? 0;
      if (seq - lotto.length == (comeInt(stato['ultimoSeq']) ?? 0)) await _salva({'ultimoSeq': seq});
      inviati += lotto.length;
      avanzamento?.call(inviati, voci.length);
      lotto = [];
      byte = 0;
    }

    for (final v in voci) {
      Uint8List chiaro;
      String id;
      if (v.record != null) {
        final r = Map<String, dynamic>.from(v.record!);
        id = comeStr(r['id']);
        Uint8List? bin;
        if (v.archivio == 'foto') {
          bin = await d.bytesFoto(id);
          r['blobTipo'] = comeStr(r['blobTipo']).isEmpty ? 'image/jpeg' : r['blobTipo'];
        }
        chiaro = impacchetta({'a': v.archivio, 'r': r}, bin);
      } else {
        final val = comeDoc(v.lapide!['valore']);
        id = comeStr(val['recordId']);
        chiaro = impacchetta({'a': v.archivio, 'id': id, 'eliminato': true, 'quando': val['quando']});
      }
      final cif = await Cifratura.cifra(_aes!, chiaro);
      final dB64 = b64(cif);
      if (lotto.isNotEmpty && (byte + dB64.length > 4 * 1024 * 1024 || lotto.length >= 200)) await spedisci();
      lotto.add({'k': await chiaveRecord(_hmac!, v.archivio, id), 'd': dB64});
      byte += dB64.length;
    }
    await spedisci();
    if (lapidi.isNotEmpty) await d.eliminaMeta(lapidi.map((l) => comeStr(l['id'])).toList());
    await _salva({'ultimoPush': inizio});
    return voci.length;
  }

  /* ---------------- ricezione ---------------- */
  Future<({int totale, bool config})> _ricevi() async {
    var totale = 0;
    var config = false;
    for (var giro = 0; giro < 1000; giro++) {
      final r = await _chiama('/v1/pull?dopo=${comeInt(stato['ultimoSeq']) ?? 0}&limite=300');
      if (comeInt(r['generazione']) != comeInt(stato['generazione'])) {
        await _cambioGenerazione(comeInt(r['generazione']) ?? 1);
        return (totale: totale, config: true);
      }
      final perArchivio = <String, List<Doc>>{};
      final eliminati = <String, List<String>>{};
      for (final x in comeListaDoc(r['record'])) {
        try {
          final p = spacchetta(await Cifratura.decifra(_aes!, daB64(comeStr(x['d']))));
          final a = comeStr(p.oggetto['a']);
          if (!archiviCloud.contains(a)) continue;
          if (p.oggetto['eliminato'] == true) {
            final id = comeStr(p.oggetto['id']);
            final loc = d.get(a, id);
            if (loc != null && comeStr(loc['updatedAt']).compareTo(comeStr(p.oggetto['quando'])) <= 0) (eliminati[a] ??= []).add(id);
            continue;
          }
          final rec = comeDoc(p.oggetto['r']);
          final loc = d.get(a, comeStr(rec['id']));
          final ru = comeStr(rec['updatedAt']), lu = comeStr(loc?['updatedAt']);
          if (loc != null && ru == lu && a != 'foto') continue;
          if (loc == null || ru.compareTo(lu) >= 0) {
            if (a == 'foto' && p.binario != null) {
              await d.salvaBytesFoto(comeStr(rec['id']), p.binario!);
              rec['blobTipo'] = comeStr(rec['blobTipo']).isEmpty ? 'image/jpeg' : rec['blobTipo'];
            }
            (perArchivio[a] ??= []).add(rec);
            if (a == 'impostazioni') config = true;
          }
        } catch (e) {
          debugPrint('Record del cloud non leggibile: $e');
        }
      }
      for (final e in perArchivio.entries) {
        await d.scriviGrezzi(e.key, e.value, notifica: false);
        totale += e.value.length;
      }
      for (final e in eliminati.entries) {
        await d.eliminaGrezzi(e.key, e.value);
        totale += e.value.length;
      }
      await _salva({'ultimoSeq': comeInt(r['ultimo']) ?? comeInt(stato['ultimoSeq']) ?? 0});
      if (r['altri'] != true) break;
    }
    if (totale > 0) d.aggiorna();
    return (totale: totale, config: config);
  }

  Future<void> _cambioGenerazione(int nuova) async {
    final st = await _chiama('/v1/stato');
    if (!await controllaVerificatore(_aes!, comeStr(st['verificatore']))) {
      await _salva({'serveNuovaPassword': true, 'attivo': false});
      throw ErroreCloud('La password del cloud è stata cambiata su un altro dispositivo: inseriscila di nuovo.', codice: 'password');
    }
    for (final a in archiviCloud) {
      await d.eliminaGrezzi(a, d.elenco(a, archiviati: true).map((x) => comeStr(x['id'])).toList());
    }
    await _salva({'generazione': nuova, 'ultimoSeq': 0, 'ultimoPush': adessoIso()});
    await _ricevi();
  }

  /* ---------------- ciclo ---------------- */
  Future<Map<String, dynamic>?> sincronizza({bool manuale = false, bool tutto = false}) {
    if (!attivo || _aes == null) return Future.value(null);
    return _inCorso ??= _sincronizza(manuale: manuale, tutto: tutto).whenComplete(() => _inCorso = null);
  }

  Future<Map<String, dynamic>?> _sincronizza({bool manuale = false, bool tutto = false}) async {
    _esito('sync', 'Sincronizzazione…');
    try {
      final ric = await _ricevi();
      int inviati;
      try {
        inviati = await _invia(tutto: tutto);
      } on ErroreCloud catch (e) {
        if (e.stato != 409) rethrow;
        await _ricevi();
        inviati = await _invia(tutto: tutto);
      }
      await _salva({'ultimaSync': adessoIso(), 'ultimoErrore': null});
      _esito('ok', 'Sincronizzato alle ${D.hhmm(DateTime.now())}');
      return {'ricevuti': ric.totale, 'inviati': inviati};
    } on ErroreCloud catch (e) {
      _esito(e.codice == 'rete' ? 'offline' : 'errore', e.messaggio);
      await _salva({'ultimoErrore': e.messaggio});
      if (e.stato == 401) await _salva({'attivo': false, 'scollegato': true});
      if (manuale) rethrow;
      return null;
    }
  }

  /* ---------------- attivazione e collegamento ---------------- */
  Future<void> attiva({required String base, required String licenza, required String password, required String nome, void Function(int, int)? avanzamento}) async {
    final sale = b64(Cifratura.casuali(16));
    final k = await derivaChiavi(password, sale);
    final r = await _chiama('/v1/attiva', metodo: 'POST', autenticato: false, base: base, corpo: {'licenza': licenza, 'sale': sale, 'verificatore': await creaVerificatore(k.aes), 'nomeDispositivo': nome});
    await _salva({
      'url': base, 'spazioId': r['spazioId'], 'dispositivoId': r['dispositivoId'], 'token': r['token'], 'chiave': b64(k.aes), 'hmac': b64(k.hmac),
      'sale': sale, 'generazione': r['generazione'], 'ultimoSeq': 0, 'ultimoPush': '', 'attivo': true, 'attivatoIl': adessoIso(), 'serveNuovaPassword': false, 'scollegato': false,
    });
    await _invia(tutto: true, avanzamento: avanzamento);
    await _salva({'ultimaSync': adessoIso()});
    _esito('ok', 'Cloud attivo');
  }

  /// Ritorna false se la password è sbagliata (il dispositivo resta collegato in attesa della password giusta).
  Future<bool> collega({required String base, required String codice, required String password, required String nome}) async {
    final r = await _chiama('/v1/collega', metodo: 'POST', autenticato: false, base: base, corpo: {'codice': codice, 'nomeDispositivo': nome});
    await _salva({
      'url': base, 'spazioId': r['spazioId'], 'dispositivoId': r['dispositivoId'], 'token': r['token'], 'sale': r['sale'], 'generazione': r['generazione'],
      'ultimoSeq': 0, 'ultimoPush': '', 'attivo': false, 'serveNuovaPassword': true, 'scollegato': false, 'verificatore': r['verificatore'],
    });
    return impostaPassword(password);
  }

  Future<bool> impostaPassword(String password) async {
    var ver = comeStr(stato['verificatore']);
    var sale = comeStr(stato['sale']);
    if (ver.isEmpty) {
      final info = await _chiama('/v1/stato');
      ver = comeStr(info['verificatore']);
      sale = comeStr(info['sale']);
    }
    final k = await derivaChiavi(password, sale);
    if (!await controllaVerificatore(k.aes, ver)) return false;
    final s = {...stato, 'chiave': b64(k.aes), 'hmac': b64(k.hmac), 'sale': sale, 'serveNuovaPassword': false}..remove('verificatore');
    await d.scriviMeta('cloud', s);
    _caricaChiavi();
    notifyListeners();
    return true;
  }

  /// Dopo il collegamento: unisce o sostituisce i dati locali con quelli del cloud.
  Future<void> completaCollegamento({required bool unisci, void Function(int, int)? avanzamento}) async {
    if (!unisci) {
      for (final a in archiviCloud) {
        await d.eliminaGrezzi(a, d.elenco(a, archiviati: true).map((x) => comeStr(x['id'])).toList());
      }
    }
    await _salva({'attivo': true, 'attivatoIl': stato['attivatoIl'] ?? adessoIso(), 'ultimoPush': unisci ? '' : adessoIso()});
    await _ricevi();
    if (unisci) await _invia(tutto: true, avanzamento: avanzamento);
    await _salva({'ultimaSync': adessoIso()});
    _esito('ok', 'Cloud attivo');
    d.aggiorna();
  }

  /// Password cambiata altrove: si riscarica tutto con la nuova chiave.
  Future<void> riallineaDopoNuovaPassword() async {
    await _salva({'attivo': true});
    final info = await _chiama('/v1/stato');
    await _cambioGenerazione(comeInt(info['generazione']) ?? 1);
    await _salva({'ultimaSync': adessoIso()});
    _esito('ok', 'Cloud attivo');
  }

  Future<void> cambiaPassword(String nuova) async {
    final sale = b64(Cifratura.casuali(16));
    final k = await derivaChiavi(nuova, sale);
    final r = await _chiama('/v1/reset', metodo: 'POST', corpo: {'sale': sale, 'verificatore': await creaVerificatore(k.aes)});
    await _salva({'chiave': b64(k.aes), 'hmac': b64(k.hmac), 'sale': sale, 'generazione': r['generazione'], 'ultimoSeq': 0, 'ultimoPush': ''});
    await sincronizza(manuale: true, tutto: true);
  }

  /// Dopo il ripristino di un backup: il cloud (e gli altri dispositivi) passano a questi dati.
  Future<void> sostituisciTuttoNelCloud() async {
    if (!attivo) return;
    final r = await _chiama('/v1/reset', metodo: 'POST', corpo: {'sale': stato['sale'], 'verificatore': await creaVerificatore(_aes!)});
    await d.eliminaMeta(d.elenco('meta', archiviati: true).map((m) => comeStr(m['id'])).where((id) => id.startsWith('elim:')).toList());
    await _salva({'generazione': r['generazione'], 'ultimoSeq': 0, 'ultimoPush': ''});
    await sincronizza(tutto: true);
  }

  Future<Map<String, dynamic>> info() => _chiama('/v1/stato');
  Future<Map<String, dynamic>> codiceCollegamento() => _chiama('/v1/collega/codice', metodo: 'POST');
  Future<void> revoca(String dispositivoId) => _chiama('/v1/dispositivi/$dispositivoId', metodo: 'DELETE');

  Future<void> scollega({bool remoto = true}) async {
    if (remoto && stato['dispositivoId'] != null) {
      try {
        await revoca(comeStr(stato['dispositivoId']));
      } catch (_) {}
    }
    await d.eliminaMeta(['cloud']);
    _aes = null;
    _hmac = null;
    _esito('spento', '');
  }

  @override
  void dispose() {
    _timer?.cancel();
    _periodico?.cancel();
    super.dispose();
  }
}
