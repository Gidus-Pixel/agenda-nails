import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../../core/date.dart';
import '../../core/util.dart';
import '../../dati/dati.dart';
import '../../dominio/agenda.dart';
import '../comuni.dart';
import '../tema.dart';

/// Calendario a colonne (giorno / 3 giorni / settimana) con:
/// - tocco su uno spazio libero → nuovo appuntamento a quell'ora;
/// - pressione lunga e trascinamento → sposta (anche su un altro giorno);
/// - maniglia in basso → cambia la durata;
/// - pause, ferie e orari di chiusura disegnati sullo sfondo.
class Calendario extends StatefulWidget {
  const Calendario({
    required this.dati,
    required this.giorni,
    required this.suTocco,
    required this.suApri,
    required this.suSposta,
    this.mostraAnnullati = false,
    this.operatrice,
    this.suTockoBlocco,
  });
  final Dati dati;
  final List<DateTime> giorni;
  final void Function(DateTime inizio) suTocco;
  final void Function(Doc app) suApri;
  final Future<bool> Function(Doc app, DateTime inizio, DateTime fine) suSposta;
  final void Function(Doc blocco)? suTockoBlocco;
  final bool mostraAnnullati;
  final String? operatrice;

  @override
  State<Calendario> createState() => _CalendarioState();
}

class _Trascinamento {
  _Trascinamento(this.app, this.ridimensiona, this.giorno0);
  final Doc app;
  final bool ridimensiona;
  final int giorno0;
  int deltaMin = 0;
  int deltaGiorni = 0;
}

class _CalendarioState extends State<Calendario> {
  final _scroll = ScrollController();
  final _chiaveGriglia = GlobalKey();
  _Trascinamento? _tr;
  Offset? _inizioPuntatore;
  Timer? _orologio;
  bool _primoScroll = true;

  double get _pxOra => eTablet(context) ? 84 : 76;
  double get _pxMin => _pxOra / 60;

  ({int min, int max}) _limiti() {
    var min = 8 * 60, max = 20 * 60;
    final o = widget.dati.cfg['orari'];
    if (o is Map) {
      final tutti = o.values.whereType<List>().expand((x) => x).whereType<List>().toList();
      if (tutti.isNotEmpty) {
        min = tutti.map((x) => D.minDaHHMM(comeStr(x[0]))).reduce(math.min) - 60;
        max = tutti.map((x) => D.minDaHHMM(comeStr(x[1]))).reduce(math.max) + 60;
      }
    }
    // allarga se ci sono appuntamenti fuori orario
    for (final a in _appuntamenti()) {
      final i = inizioApp(a), f = fineApp(a);
      if (D.stessoGiorno(i, f)) {
        min = math.min(min, D.minutiDelGiorno(i));
        max = math.max(max, D.minutiDelGiorno(f));
      }
    }
    min = math.max(0, (min ~/ 60) * 60);
    max = math.min(1440, ((max + 59) ~/ 60) * 60);
    return (min: min, max: max);
  }

  List<Doc> _appuntamenti() {
    if (widget.giorni.isEmpty) return [];
    final da = widget.giorni.first, a = D.aggiungiGiorni(widget.giorni.last, 1);
    return appuntamentiTra(widget.dati, da, a).where((x) {
      final st = statoApp(x);
      if (st == 'annullato' && !widget.mostraAnnullati) return false;
      if (widget.operatrice != null && comeStr(x['operatriceId']).isNotEmpty && x['operatriceId'] != widget.operatrice) return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _orologio = Timer.periodic(const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _orologio?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _scorriAllOra(int minTop) {
    if (!_primoScroll) return;
    _primoScroll = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final adesso = D.minutiDelGiorno(DateTime.now());
      final target = ((adesso - 60 - minTop).clamp(0, 24 * 60)) * _pxMin;
      _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent).toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lim = _limiti();
    _scorriAllOra(lim.min);
    final altezza = (lim.max - lim.min) * _pxMin;
    final apps = _appuntamenti();
    final blocchi = widget.giorni.isEmpty ? <IstanzaBlocco>[] : istanzeBlocchi(widget.dati, widget.giorni.first, D.aggiungiGiorni(widget.giorni.last, 1));
    const larghOre = 52.0;

    return Column(children: [
      // intestazione dei giorni
      if (widget.giorni.length > 1)
        Padding(
          padding: const EdgeInsets.only(left: larghOre),
          child: Row(children: [for (final g in widget.giorni) Expanded(child: _Intestazione(giorno: g))]),
        ),
      Expanded(
        child: SingleChildScrollView(
          controller: _scroll,
          physics: _tr != null ? const NeverScrollableScrollPhysics() : null,
          child: SizedBox(
            height: altezza + 16,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: larghOre, height: altezza + 16, child: _ColonnaOre(min: lim.min, max: lim.max, pxMin: _pxMin)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LayoutBuilder(builder: (context, vincoli) {
                    final larghCol = vincoli.maxWidth / widget.giorni.length;
                    return Stack(key: _chiaveGriglia, clipBehavior: Clip.none, children: [
                      // sfondo: righe, chiusure, blocchi, ora attuale
                      for (var i = 0; i < widget.giorni.length; i++)
                        Positioned(
                          left: i * larghCol,
                          width: larghCol,
                          top: 0,
                          height: altezza,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (det) => _toccoVuoto(widget.giorni[i], det.localPosition.dy, lim.min, blocchi),
                            child: CustomPaint(
                              painter: _Sfondo(
                                giorno: widget.giorni[i],
                                min: lim.min,
                                max: lim.max,
                                pxMin: _pxMin,
                                intervalli: widget.dati.cfg['orari'] is Map ? intervalliGiorno(widget.dati, widget.giorni[i]) : null,
                                linea: cs.outlineVariant,
                                chiuso: cs.onSurface.withValues(alpha: 0.045),
                                bordoSinistro: i > 0,
                              ),
                            ),
                          ),
                        ),
                      for (final b in blocchi) ..._blocco(b, larghCol, lim.min, cs),
                      for (final e in _disponi(apps, lim.min, larghCol)) e,
                      ..._lineaOra(lim, larghCol, cs),
                    ]);
                  }),
                ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }

  void _toccoVuoto(DateTime giorno, double dy, int minTop, List<IstanzaBlocco> blocchi) {
    final passo = widget.dati.slotMinuti;
    var m = minTop + (dy / _pxMin).floor();
    m = (m ~/ passo) * passo;
    final inizio = D.combina(D.key(giorno), D.hhmmDaMin(m.clamp(0, 1439)));
    final fineSlot = D.aggiungiMinuti(inizio, passo);
    final suBlocco = blocchi.where((b) => b.inizio.isBefore(fineSlot) && b.fine.isAfter(inizio)).toList();
    vibra();
    if (suBlocco.isNotEmpty && widget.suTockoBlocco != null) {
      widget.suTockoBlocco!(suBlocco.first.blocco);
      return;
    }
    widget.suTocco(inizio);
  }

  List<Widget> _blocco(IstanzaBlocco b, double larghCol, int minTop, ColorScheme cs) {
    final idx = widget.giorni.indexWhere((g) => D.stessoGiorno(g, b.inizio) || (b.inizio.isBefore(g) && b.fine.isAfter(g)));
    if (idx < 0) return [];
    final out = <Widget>[];
    for (var i = idx; i < widget.giorni.length; i++) {
      final g = widget.giorni[i];
      final inizioG = g, fineG = D.aggiungiGiorni(g, 1);
      if (!(b.inizio.isBefore(fineG) && b.fine.isAfter(inizioG))) continue;
      final da = b.inizio.isBefore(inizioG) ? 0 : D.minutiDelGiorno(b.inizio);
      final a = b.fine.isAfter(fineG) ? 1440 : (D.minutiDelGiorno(b.fine) == 0 && !D.stessoGiorno(b.fine, g) ? 1440 : D.minutiDelGiorno(b.fine));
      final top = (math.max(da, minTop) - minTop) * _pxMin;
      final h = (a - math.max(da, minTop)) * _pxMin;
      if (h <= 0) continue;
      out.add(Positioned(
        left: i * larghCol + 2,
        width: larghCol - 4,
        top: top,
        height: h,
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: cs.onSurface.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
            ),
            child: Text(
              '${tipiBlocco[b.blocco['tipo']] ?? 'Blocco'}${comeStr(b.blocco['titolo']).isNotEmpty ? ': ${b.blocco['titolo']}' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ));
    }
    return out;
  }

  List<Widget> _lineaOra(({int min, int max}) lim, double larghCol, ColorScheme cs) {
    final ora = DateTime.now();
    final i = widget.giorni.indexWhere((g) => D.stessoGiorno(g, ora));
    if (i < 0) return [];
    final m = D.minutiDelGiorno(ora);
    if (m < lim.min || m > lim.max) return [];
    final top = (m - lim.min) * _pxMin;
    return [
      Positioned(left: i * larghCol, width: larghCol, top: top - 1, height: 2, child: IgnorePointer(child: Container(color: cs.error))),
      Positioned(left: i * larghCol - 5, top: top - 5, width: 10, height: 10, child: IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle)))),
    ];
  }

  /// Disposizione degli appuntamenti che si sovrappongono: affiancati in colonne.
  List<Widget> _disponi(List<Doc> apps, int minTop, double larghCol) {
    final out = <Widget>[];
    for (var gi = 0; gi < widget.giorni.length; gi++) {
      final g = widget.giorni[gi];
      final delGiorno = apps.where((a) => D.stessoGiorno(inizioApp(a), g)).toList()..sort((a, b) => comeStr(a['inizio']).compareTo(comeStr(b['inizio'])));
      final gruppi = <List<Doc>>[];
      DateTime? fineGruppo;
      for (final a in delGiorno) {
        if (gruppi.isEmpty || !inizioApp(a).isBefore(fineGruppo!)) {
          gruppi.add([a]);
          fineGruppo = fineApp(a);
        } else {
          gruppi.last.add(a);
          if (fineApp(a).isAfter(fineGruppo)) fineGruppo = fineApp(a);
        }
      }
      for (final gr in gruppi) {
        final colonne = <List<Doc>>[];
        final colDi = <String, int>{};
        for (final a in gr) {
          var c = colonne.indexWhere((col) => !inizioApp(a).isBefore(fineApp(col.last)));
          if (c < 0) {
            colonne.add([a]);
            c = colonne.length - 1;
          } else {
            colonne[c].add(a);
          }
          colDi[comeStr(a['id'])] = c;
        }
        final n = colonne.length;
        for (final a in gr) {
          out.add(_evento(a, gi, colDi[comeStr(a['id'])]!, n, minTop, larghCol));
        }
      }
    }
    return out;
  }

  Widget _evento(Doc a, int giorno, int col, int nCol, int minTop, double larghCol) {
    final tr = _tr != null && _tr!.app['id'] == a['id'] ? _tr : null;
    final i = inizioApp(a), f = fineApp(a);
    var minI = D.minutiDelGiorno(i) - minTop;
    var durata = math.max(10, D.minutiTra(i, f));
    var g = giorno;
    if (tr != null) {
      if (tr.ridimensiona) {
        durata = math.max(widget.dati.slotMinuti, durata + tr.deltaMin);
      } else {
        minI += tr.deltaMin;
        g = (giorno + tr.deltaGiorni).clamp(0, widget.giorni.length - 1);
      }
    }
    final w = (larghCol - 6) / (tr != null ? 1 : nCol);
    final left = g * larghCol + 3 + (tr != null ? 0 : col * w);
    final top = minI * _pxMin;
    final h = math.max(26.0, durata * _pxMin - 2);
    final modificabile = !['completato', 'annullato', 'non_presentata'].contains(statoApp(a));
    return AnimatedPositioned(
      key: ValueKey(a['id']),
      duration: tr != null ? Duration.zero : const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: w,
      height: h,
      child: _Tessera(
        dati: widget.dati,
        app: a,
        sollevata: tr != null,
        anteprimaOrario: tr == null ? null : _orarioAnteprima(a, tr),
        modificabile: modificabile,
        suApri: () => widget.suApri(a),
        suInizioTrascina: modificabile ? (pos, ridimensiona) => _inizia(a, giorno, pos, ridimensiona) : null,
        suTrascina: (pos) => _aggiorna(pos, larghCol),
        suFineTrascina: () => _fine(),
      ),
    );
  }

  ({DateTime inizio, DateTime fine}) _nuoviOrari(Doc a, _Trascinamento tr) {
    final i = inizioApp(a), f = fineApp(a);
    if (tr.ridimensiona) {
      final dur = math.max(widget.dati.slotMinuti, D.minutiTra(i, f) + tr.deltaMin);
      return (inizio: i, fine: D.aggiungiMinuti(i, dur));
    }
    final dur = D.minutiTra(i, f);
    final k = D.aggiungiGiorniKey(D.key(i), tr.deltaGiorni);
    final m = (D.minutiDelGiorno(i) + tr.deltaMin).clamp(0, 1439);
    final ni = D.combina(k, D.hhmmDaMin(m));
    return (inizio: ni, fine: D.aggiungiMinuti(ni, dur));
  }

  String _orarioAnteprima(Doc a, _Trascinamento tr) {
    final n = _nuoviOrari(a, tr);
    final g = widget.giorni.length > 1 && tr.deltaGiorni != 0 ? '${F.giornoCorto(n.inizio)} · ' : '';
    return '$g${F.intervallo(n.inizio, n.fine)}';
  }

  void _inizia(Doc a, int giorno, Offset pos, bool ridimensiona) {
    vibra(true);
    setState(() {
      _tr = _Trascinamento(a, ridimensiona, giorno);
      _inizioPuntatore = pos;
    });
  }

  void _aggiorna(Offset pos, double larghCol) {
    final tr = _tr;
    if (tr == null || _inizioPuntatore == null) return;
    final passo = widget.dati.slotMinuti;
    final dy = pos.dy - _inizioPuntatore!.dy, dx = pos.dx - _inizioPuntatore!.dx;
    final nuovoMin = ((dy / _pxMin) / passo).round() * passo;
    final nuoviGiorni = tr.ridimensiona || widget.giorni.length == 1 ? 0 : (dx / larghCol).round();
    if (nuovoMin != tr.deltaMin || nuoviGiorni != tr.deltaGiorni) {
      vibra();
      setState(() {
        tr.deltaMin = nuovoMin;
        tr.deltaGiorni = (tr.giorno0 + nuoviGiorni).clamp(0, widget.giorni.length - 1) - tr.giorno0;
      });
    }
    _autoScorri(pos);
  }

  void _autoScorri(Offset globale) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !_scroll.hasClients) return;
    final locale = box.globalToLocal(globale);
    const bordo = 60.0;
    if (locale.dy < bordo) {
      _scroll.jumpTo(math.max(0, _scroll.offset - 8));
    } else if (locale.dy > box.size.height - bordo) {
      _scroll.jumpTo(math.min(_scroll.position.maxScrollExtent, _scroll.offset + 8));
    }
  }

  Future<void> _fine() async {
    final tr = _tr;
    if (tr == null) return;
    if (tr.deltaMin == 0 && tr.deltaGiorni == 0) {
      setState(() => _tr = null);
      return;
    }
    final n = _nuoviOrari(tr.app, tr);
    await widget.suSposta(tr.app, n.inizio, n.fine);
    if (mounted) setState(() => _tr = null);
  }
}

class _Tessera extends StatelessWidget {
  const _Tessera({required this.dati, required this.app, required this.sollevata, required this.modificabile, required this.suApri, this.suInizioTrascina, required this.suTrascina, required this.suFineTrascina, this.anteprimaOrario});
  final Dati dati;
  final Doc app;
  final bool sollevata, modificabile;
  final String? anteprimaOrario;
  final VoidCallback suApri;
  final void Function(Offset globale, bool ridimensiona)? suInizioTrascina;
  final void Function(Offset globale) suTrascina;
  final VoidCallback suFineTrascina;

  @override
  Widget build(BuildContext context) {
    final colore = Color(coloreApp(dati, app));
    final testo = Tema.testoSu(colore);
    final cli = dati.get('clienti', comeStr(app['clienteId']));
    final nome = cli != null ? nomeCliente(cli) : comeStr(app['clienteNome']).isEmpty ? 'Cliente' : comeStr(app['clienteNome']);
    final st = statoApp(app);
    final barrato = st == 'annullato' || st == 'non_presentata';
    final icone = [if (haAvvertenze(cli)) '⚠️', if ((comeInt(app['accontoCent']) ?? 0) > 0) '💶', if (app['promemoriaInviatoIl'] != null) '💬'].join(' ');
    final i = inizioApp(app), f = fineApp(app);
    return GestureDetector(
      onTap: suApri,
      onLongPressStart: suInizioTrascina == null ? null : (d) => suInizioTrascina!(d.globalPosition, false),
      onLongPressMoveUpdate: (d) => suTrascina(d.globalPosition),
      onLongPressEnd: (_) => suFineTrascina(),
      child: AnimatedScale(
        scale: sollevata ? 1.03 : 1,
        duration: const Duration(milliseconds: 120),
        child: Opacity(
          opacity: barrato ? 0.55 : 1,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colore,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 1),
              boxShadow: sollevata ? [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))] : null,
            ),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
                child: LayoutBuilder(builder: (c, v) {
                  final basso = v.maxHeight < 40;
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      basso && anteprimaOrario == null ? '${D.hhmm(i)} · ${icone.isEmpty ? '' : '$icone '}$nome' : (anteprimaOrario ?? F.intervallo(i, f)),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(color: testo.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    if (!basso)
                      Text(
                        '${icone.isEmpty ? '' : '$icone '}$nome',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: testo, fontWeight: FontWeight.w700, fontSize: 13.5, decoration: barrato ? TextDecoration.lineThrough : null, decorationColor: testo),
                      ),
                    if (v.maxHeight > 58)
                      Text(serviziTesto(app), maxLines: v.maxHeight > 80 ? 2 : 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: testo.withValues(alpha: 0.92), fontSize: 12)),
                  ]);
                }),
              ),
              if (modificabile && suInizioTrascina != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 14,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (d) => suInizioTrascina!(d.globalPosition, true),
                    onVerticalDragUpdate: (d) => suTrascina(d.globalPosition),
                    onVerticalDragEnd: (_) => suFineTrascina(),
                    child: Center(child: Container(width: 28, height: 4, decoration: BoxDecoration(color: testo.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(2)))),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Intestazione extends StatelessWidget {
  const _Intestazione({required this.giorno});
  final DateTime giorno;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final oggi = D.stessoGiorno(giorno, DateTime.now());
    final settimana = F.maiuscola(F.giornoCorto(giorno).split(' ').first);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: [
        Text(settimana, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: oggi ? cs.primary : cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: oggi ? cs.primary : Colors.transparent, shape: BoxShape.circle),
          child: Text('${giorno.day}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: oggi ? cs.onPrimary : cs.onSurface)),
        ),
      ]),
    );
  }
}

class _ColonnaOre extends StatelessWidget {
  const _ColonnaOre({required this.min, required this.max, required this.pxMin});
  final int min, max;
  final double pxMin;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(children: [
      for (var m = min; m <= max; m += 60)
        Positioned(
          top: (m - min) * pxMin + 1,
          right: 8,
          child: Text(D.hhmmDaMin(m % 1440), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
    ]);
  }
}

class _Sfondo extends CustomPainter {
  _Sfondo({required this.giorno, required this.min, required this.max, required this.pxMin, required this.intervalli, required this.linea, required this.chiuso, required this.bordoSinistro});
  final DateTime giorno;
  final int min, max;
  final double pxMin;
  final List<List<int>>? intervalli;
  final Color linea, chiuso;
  final bool bordoSinistro;

  @override
  void paint(Canvas canvas, Size size) {
    // fasce di chiusura (fuori orario e pause)
    if (intervalli != null) {
      final p = Paint()..color = chiuso;
      var ultimo = min;
      for (final iv in intervalli!) {
        if (iv[0] > ultimo) canvas.drawRect(Rect.fromLTWH(0, (ultimo - min) * pxMin, size.width, (iv[0] - ultimo) * pxMin), p);
        ultimo = math.max(ultimo, iv[1]);
      }
      if (ultimo < max) canvas.drawRect(Rect.fromLTWH(0, (ultimo - min) * pxMin, size.width, (max - ultimo) * pxMin), p);
    }
    final pl = Paint()
      ..color = linea
      ..strokeWidth = 1;
    final pm = Paint()
      ..color = linea.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    for (var m = min; m <= max; m += 30) {
      final y = (m - min) * pxMin;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), m % 60 == 0 ? pl : pm);
    }
    if (bordoSinistro) canvas.drawLine(Offset.zero, Offset(0, size.height), pl);
  }

  @override
  bool shouldRepaint(_Sfondo o) => o.giorno != giorno || o.min != min || o.max != max || o.pxMin != pxMin || o.linea != linea || o.intervalli?.length != intervalli?.length;
}
