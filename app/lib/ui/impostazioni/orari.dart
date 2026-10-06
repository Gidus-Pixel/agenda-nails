import 'package:flutter/material.dart';

import '../../core/date.dart';
import '../../core/util.dart';
import '../app.dart';
import '../comuni.dart';
import '../tema.dart';
import 'pagina_altro.dart';

/// Orari di apertura per giorno, con pausa (fino a 3 fasce al giorno).
class PaginaOrari extends StatefulWidget {
  const PaginaOrari({super.key});
  @override
  State<PaginaOrari> createState() => _PaginaOrariState();
}

class _PaginaOrariState extends State<PaginaOrari> {
  late Map<String, List<List<String>>> _o;

  @override
  void initState() {
    super.initState();
    final o = Ambito.of(context).dati.cfg['orari'];
    _o = {
      for (final g in D.giorniKey)
        g: o is Map
            ? (o[g] as List? ?? const []).whereType<List>().map((x) => [comeStr(x[0]), comeStr(x[1])]).toList()
            : (g == 'dom' || g == 'lun' ? <List<String>>[] : [['09:00', '13:00'], ['14:30', '19:30']]),
    };
  }

  String? _errore() {
    for (final g in D.giorniKey) {
      final iv = _o[g]!;
      for (var i = 0; i < iv.length; i++) {
        if (D.minDaHHMM(iv[i][1]) <= D.minDaHHMM(iv[i][0])) return '${D.giorniNome[g]}: la fascia ${iv[i][0]}–${iv[i][1]} finisce prima di iniziare.';
        if (i > 0 && D.minDaHHMM(iv[i][0]) < D.minDaHHMM(iv[i - 1][1])) return '${D.giorniNome[g]}: le fasce si sovrappongono.';
      }
    }
    return null;
  }

  Future<void> _salva() async {
    final e = _errore();
    if (e != null) {
      avviso(context, e, errore: true);
      return;
    }
    await modificaConfig(context, (c) => c['orari'] = {for (final g in D.giorniKey) g: _o[g]});
    if (mounted) {
      Navigator.pop(context);
      avvisa('Orari salvati');
    }
  }

  Future<String?> _ora(String v) async {
    final m = D.minDaHHMM(v);
    final o = await scegliOra(context, TimeOfDay(hour: m ~/ 60, minute: m % 60));
    return o == null ? null : '${D.p2(o.hour)}:${D.p2(o.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final err = _errore();
    return Scaffold(
      appBar: AppBar(title: const Text('Orari di apertura'), actions: [Padding(padding: const EdgeInsets.only(right: S.s), child: TextButton(onPressed: _salva, child: const Text('Salva')))]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: const EdgeInsets.fromLTRB(S.l, S.s, S.l, S.xxl * 2), children: [
              const Riquadro(testo: 'Per una pausa pranzo usa due fasce (es. 9:00–13:00 e 14:30–19:30). L\'agenda mostra in grigio gli orari chiusi e avvisa se un appuntamento cade fuori orario.'),
              if (err != null) ...[const SizedBox(height: S.m), Riquadro(tipo: 'pericolo', testo: err)],
              const SizedBox(height: S.l),
              for (final g in D.giorniKey)
                Card(
                  margin: const EdgeInsets.only(bottom: S.s),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(S.l, S.s, S.s, S.s),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(child: Text(D.giorniNome[g]!, style: t.titleMedium)),
                        Text(_o[g]!.isEmpty ? 'Chiuso' : 'Aperto', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        Switch(
                          value: _o[g]!.isNotEmpty,
                          onChanged: (v) => setState(() => _o[g] = v ? [['09:00', '13:00'], ['14:30', '19:30']] : []),
                        ),
                      ]),
                      for (var i = 0; i < _o[g]!.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            SizedBox(width: 64, child: Text(i == 0 ? 'Fascia' : 'poi', style: t.bodySmall)),
                            OutlinedButton(
                              onPressed: () async {
                                final v = await _ora(_o[g]![i][0]);
                                if (v != null) setState(() => _o[g]![i][0] = v);
                              },
                              child: Text(_o[g]![i][0]),
                            ),
                            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                            OutlinedButton(
                              onPressed: () async {
                                final v = await _ora(_o[g]![i][1]);
                                if (v != null) setState(() => _o[g]![i][1] = v);
                              },
                              child: Text(_o[g]![i][1]),
                            ),
                            const Spacer(),
                            IconButton(tooltip: 'Togli fascia', onPressed: () => setState(() => _o[g]!.removeAt(i)), icon: const Icon(Icons.remove_circle_outline_rounded)),
                          ]),
                        ),
                      if (_o[g]!.isNotEmpty && _o[g]!.length < 3)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => setState(() {
                              final ultima = _o[g]!.last;
                              final da = (D.minDaHHMM(ultima[1]) + 60).clamp(0, 23 * 60);
                              _o[g]!.add([D.hhmmDaMin(da), D.hhmmDaMin((da + 120).clamp(0, 1439))]);
                            }),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Aggiungi fascia (dopo una pausa)'),
                          ),
                        ),
                    ]),
                  ),
                ),
              const SizedBox(height: S.s),
              OutlinedButton.icon(
                onPressed: () {
                  final primo = D.giorniKey.firstWhere((g) => _o[g]!.isNotEmpty, orElse: () => 'mar');
                  setState(() {
                    for (final g in D.giorniKey) {
                      if (_o[g]!.isNotEmpty && g != primo) _o[g] = [for (final x in _o[primo]!) [...x]];
                    }
                  });
                },
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copia il primo giorno aperto sugli altri giorni aperti'),
              ),
              const SizedBox(height: S.l),
              FilledButton(onPressed: _salva, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Salva orari')),
            ]),
          ),
        ),
      ),
    );
  }
}
