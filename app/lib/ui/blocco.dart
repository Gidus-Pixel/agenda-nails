import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/util.dart';
import '../dati/dati.dart';
import '../dominio/sicurezza.dart';
import '../servizi/biometria.dart';
import 'tema.dart';

/// true = schermata di blocco visibile. "Blocca ora" (Impostazioni) lo mette a true.
final bloccoAttivo = ValueNotifier<bool>(false);

/// Minuti fuori dall'app dopo cui serve di nuovo il PIN (0 = subito).
int minutiBlocco(Dati d) => comeInt(comeDoc(d.cfg['sicurezza'])['bloccoAppMinuti']) ?? 1;

/// Avvolge tutta l'app: blocca all'avvio e al ritorno dopo un po' di tempo, e copre i dati
/// nell'anteprima del multitasking. Funziona sopra ogni pagina e finestra aperta.
class Blocco extends StatefulWidget {
  const Blocco({super.key, required this.dati, required this.child});
  final Dati dati;
  final Widget child;
  @override
  State<Blocco> createState() => _BloccoState();
}

class _BloccoState extends State<Blocco> with WidgetsBindingObserver {
  bool _coperta = false;
  DateTime? _uscitaIl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    bloccoAttivo.value = pinImpostato(widget.dati);
    bloccoAttivo.addListener(_aggiorna);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    bloccoAttivo.removeListener(_aggiorna);
    super.dispose();
  }

  void _aggiorna() => setState(() {});

  @override
  void didChangeAppLifecycleState(AppLifecycleState stato) {
    if (!pinImpostato(widget.dati)) {
      if (_coperta) setState(() => _coperta = false);
      return;
    }
    switch (stato) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        setState(() => _coperta = true);
      case AppLifecycleState.paused:
        _uscitaIl ??= DateTime.now();
        setState(() => _coperta = true);
      case AppLifecycleState.resumed:
        final via = _uscitaIl;
        _uscitaIl = null;
        if (via != null && DateTime.now().difference(via).inSeconds >= minutiBlocco(widget.dati) * 60) bloccoAttivo.value = true;
        setState(() => _coperta = false);
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloccata = bloccoAttivo.value && pinImpostato(widget.dati);
    return Stack(children: [
      // i contenuti restano montati (stato conservato) ma non ricevono tocchi né letture vocali
      ExcludeSemantics(excluding: bloccata, child: AbsorbPointer(absorbing: bloccata, child: widget.child)),
      if (bloccata) Positioned.fill(child: SchermataBlocco(dati: widget.dati, suSblocco: () => bloccoAttivo.value = false)),
      if (_coperta && !bloccata) Positioned.fill(child: _Copertura()),
    ]);
  }
}

class _Copertura extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(color: cs.surface, child: Center(child: Image.asset('assets/immagini/icona.png', width: 72, height: 72)));
  }
}

/// Tastierino del PIN, con Face ID / impronta se attivati.
class SchermataBlocco extends StatefulWidget {
  const SchermataBlocco({super.key, required this.dati, required this.suSblocco});
  final Dati dati;
  final VoidCallback suSblocco;
  @override
  State<SchermataBlocco> createState() => _SchermataBloccoState();
}

class _SchermataBloccoState extends State<SchermataBlocco> with SingleTickerProviderStateMixin {
  String _pin = '';
  String _msg = '';
  int _errori = 0;
  DateTime? _attesaFino;
  bool _verifico = false;
  String? _nomeBio;
  late final AnimationController _scuoti = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  Timer? _orologio;

  @override
  void initState() {
    super.initState();
    if (biometriaAttiva(widget.dati)) {
      Biometria.disponibile().then((n) {
        if (!mounted || n == null) return;
        setState(() => _nomeBio = n);
        _bio();
      });
    }
  }

  @override
  void dispose() {
    _scuoti.dispose();
    _orologio?.cancel();
    super.dispose();
  }

  Future<void> _bio() async {
    if (await Biometria.verifica("Sblocca l'agenda") && mounted) {
      HapticFeedback.mediumImpact();
      widget.suSblocco();
    }
  }

  Future<void> _tasto(String t) async {
    if (_verifico) return;
    final attesa = _attesaFino;
    if (attesa != null && DateTime.now().isBefore(attesa)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _msg = '';
      if (t == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 8) {
        _pin += t;
      }
    });
    // PIN di lunghezza nota: si verifica appena completo; altrimenti con "Conferma"
    final cifre = cifrePin(widget.dati);
    if (t != '<' && (cifre != null ? _pin.length == cifre : _pin.length == 8)) await _conferma();
  }

  Future<void> _conferma() async {
    if (_pin.length < 4 || _verifico) return;
    setState(() => _verifico = true);
    final ok = await verificaPin(widget.dati, _pin);
    if (!mounted) return;
    setState(() => _verifico = false);
    if (ok) {
      HapticFeedback.mediumImpact();
      widget.suSblocco();
    } else {
      _sbagliato();
    }
  }

  void _sbagliato() {
    HapticFeedback.heavyImpact();
    _scuoti.forward(from: 0);
    _errori++;
    setState(() {
      _pin = '';
      if (_errori >= 5) {
        _attesaFino = DateTime.now().add(Duration(seconds: 30 * (_errori - 4)));
        _orologio?.cancel();
        _orologio = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() {});
          if (DateTime.now().isAfter(_attesaFino!)) _orologio?.cancel();
        });
        _msg = 'Troppi tentativi sbagliati.';
      } else {
        _msg = 'PIN errato';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final attesa = _attesaFino != null && DateTime.now().isBefore(_attesaFino!) ? _attesaFino!.difference(DateTime.now()).inSeconds + 1 : 0;
    final nome = widget.dati.nomeAttivita;
    Widget tasto(String v, {Widget? figlio, String? etichetta}) => Padding(
          padding: const EdgeInsets.all(8),
          child: Semantics(
            button: true,
            label: etichetta ?? v,
            child: Material(
              color: v.isEmpty ? Colors.transparent : cs.surfaceContainer,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: v.isEmpty ? null : () => v == 'bio' ? _bio() : _tasto(v),
                child: SizedBox(width: 76, height: 76, child: Center(child: figlio ?? Text(v, style: t.headlineMedium?.copyWith(fontFamily: Tema.font, fontWeight: FontWeight.w500)))),
              ),
            ),
          ),
        );
    return Material(
      color: cs.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Image.asset('assets/immagini/icona.png', width: 64, height: 64, semanticLabel: 'Logo'),
              const SizedBox(height: S.s),
              Text(nome.isEmpty ? 'Agenda' : nome, style: t.headlineSmall),
              const SizedBox(height: S.l),
              Text(attesa > 0 ? 'Riprova tra $attesa secondi' : 'Inserisci il PIN', style: t.titleMedium),
              const SizedBox(height: S.m),
              AnimatedBuilder(
                animation: _scuoti,
                builder: (c, figlio) => Transform.translate(offset: Offset(math.sin(_scuoti.value * math.pi * 6) * 14 * (1 - _scuoti.value), 0), child: figlio),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < (cifrePin(widget.dati) ?? (_pin.length > 4 ? _pin.length : 4)); i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 7),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i < _pin.length ? cs.primary : Colors.transparent, border: Border.all(color: cs.primary, width: 1.6)),
                    ),
                ]),
              ),
              SizedBox(height: 28, child: Center(child: Text(_msg, style: t.bodyMedium?.copyWith(color: cs.error)))),
              for (final riga in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']]) Row(mainAxisSize: MainAxisSize.min, children: [for (final v in riga) tasto(v)]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _nomeBio != null
                    ? tasto('bio', etichetta: 'Usa $_nomeBio', figlio: Icon(_nomeBio == 'Face ID' ? Icons.face_retouching_natural_rounded : Icons.fingerprint_rounded, size: 34, color: cs.primary))
                    : tasto(''),
                tasto('0'),
                tasto('<', etichetta: 'Cancella', figlio: Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant)),
              ]),
              SizedBox(
                height: 48,
                child: _verifico
                    ? const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))
                    : (_pin.length >= 4 && cifrePin(widget.dati) == null ? TextButton(onPressed: _conferma, child: const Text('Conferma')) : null),
              ),
              const SizedBox(height: S.m),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.xl),
                child: Text('Il PIN protegge da occhi indiscreti. Se lo dimentichi: reinstalla l\'app e ripristina un backup (o ricollegati al cloud).', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
