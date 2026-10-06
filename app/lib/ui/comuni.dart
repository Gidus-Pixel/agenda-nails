import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/date.dart';
import '../dominio/agenda.dart';
import 'tema.dart';

bool eIOS(BuildContext c) => Theme.of(c).platform == TargetPlatform.iOS || Theme.of(c).platform == TargetPlatform.macOS;

/// Messaggi in basso di tutta l'app (validi anche dopo aver chiuso una pagina o un foglio).
final messaggero = GlobalKey<ScaffoldMessengerState>();

/// Messaggio in basso senza contesto: da usare dopo aver chiuso la pagina corrente.
void avvisa(String testo, {Future<void> Function()? annulla, bool errore = false}) {
  final m = messaggero.currentState;
  if (m == null) return;
  _mostra(m, m.context, testo, annulla: annulla, errore: errore);
}

/// Messaggio in basso, con "Annulla" facoltativo.
void avviso(BuildContext context, String testo, {Future<void> Function()? annulla, String? azione, VoidCallback? suAzione, bool errore = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  _mostra(m, context, testo, annulla: annulla, azione: azione, suAzione: suAzione, errore: errore);
}

void _mostra(ScaffoldMessengerState m, BuildContext context, String testo, {Future<void> Function()? annulla, String? azione, VoidCallback? suAzione, bool errore = false}) {
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(testo),
    backgroundColor: errore ? Theme.of(context).colorScheme.error : null,
    duration: Duration(seconds: annulla != null || suAzione != null ? 7 : 3),
    action: annulla != null
        ? SnackBarAction(label: 'Annulla', onPressed: () => annulla())
        : (suAzione != null && azione != null ? SnackBarAction(label: azione, onPressed: suAzione) : null),
  ));
}

/// Conferma con elenco di problemi (conflitti di agenda ecc.).
Future<bool> conferma(BuildContext context, {required String titolo, String? messaggio, Widget? contenuto, List<Problema> problemi = const [], String ok = 'Conferma', String annulla = 'Annulla', bool pericolo = false}) async {
  final cs = Theme.of(context).colorScheme;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titolo),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (messaggio != null) Text(messaggio),
        ?contenuto,
        if (problemi.isNotEmpty) ...[
          const SizedBox(height: S.m),
          Container(
            padding: const EdgeInsets.all(S.m),
            decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0x558A4B08))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.warning_amber_rounded, color: Color(0xFF8A4B08), size: 20), SizedBox(width: 6), Text('Attenzione', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF8A4B08)))]),
              const SizedBox(height: 6),
              for (final p in problemi) Padding(padding: const EdgeInsets.only(top: 4), child: Text('• ${p.msg}', style: const TextStyle(color: Color(0xFF6B3A06)))),
            ]),
          ),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(annulla)),
        FilledButton(
          style: (pericolo || problemi.isNotEmpty) ? FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

Future<String?> sceltaTra(BuildContext context, {required String titolo, String? messaggio, required List<(String valore, String testo, bool principale)> opzioni}) {
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titolo),
      content: messaggio == null ? null : Text(messaggio),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Indietro')),
        for (final o in opzioni) o.$3 ? FilledButton(onPressed: () => Navigator.pop(c, o.$1), child: Text(o.$2)) : OutlinedButton(onPressed: () => Navigator.pop(c, o.$1), child: Text(o.$2)),
      ],
    ),
  );
}

/// Selettore di data nello stile della piattaforma.
Future<DateTime?> scegliData(BuildContext context, DateTime iniziale) async {
  if (eIOS(context)) {
    var scelta = iniziale;
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (c) => _FoglioCupertino(
        child: CupertinoDatePicker(mode: CupertinoDatePickerMode.date, initialDateTime: iniziale, onDateTimeChanged: (d) => scelta = d, dateOrder: DatePickerDateOrder.dmy),
      ),
    );
    return ok == true ? scelta : null;
  }
  return showDatePicker(context: context, initialDate: iniziale, firstDate: DateTime(2020), lastDate: DateTime(2100), locale: const Locale('it'));
}

/// Selettore di ora (24 ore) a passi di [passo] minuti.
Future<TimeOfDay?> scegliOra(BuildContext context, TimeOfDay iniziale, {int passo = 5}) async {
  if (eIOS(context)) {
    var scelta = DateTime(2000, 1, 1, iniziale.hour, iniziale.minute - iniziale.minute % passo);
    final ok = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (c) => _FoglioCupertino(
        child: CupertinoDatePicker(mode: CupertinoDatePickerMode.time, use24hFormat: true, minuteInterval: passo, initialDateTime: scelta, onDateTimeChanged: (d) => scelta = d),
      ),
    );
    return ok == true ? TimeOfDay(hour: scelta.hour, minute: scelta.minute) : null;
  }
  return showTimePicker(
    context: context,
    initialTime: iniziale,
    builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!),
  );
}

class _FoglioCupertino extends StatelessWidget {
  const _FoglioCupertino({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 300,
      decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: SafeArea(
        top: false,
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            CupertinoButton(child: const Text('Annulla'), onPressed: () => Navigator.pop(context, false)),
            CupertinoButton(child: const Text('Fatto', style: TextStyle(fontWeight: FontWeight.w700)), onPressed: () => Navigator.pop(context, true)),
          ]),
          Expanded(child: child),
        ]),
      ),
    );
  }
}

/// Riquadro con titolo, usato in tutte le schermate.
class Sezione extends StatelessWidget {
  const Sezione({required this.titolo, required this.child, this.azione, this.padding = const EdgeInsets.fromLTRB(S.l, S.m, S.l, S.l)});
  final String titolo;
  final Widget child;
  final Widget? azione;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [Expanded(child: Text(titolo, style: t.titleMedium)), ?azione]),
          const SizedBox(height: S.s),
          child,
        ]),
      ),
    );
  }
}

class Etichetta extends StatelessWidget {
  const Etichetta(this.testo, {this.colore, this.sfondo, this.icona});
  final String testo;
  final Color? colore, sfondo;
  final IconData? icona;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = colore ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: sfondo ?? c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icona != null) ...[Icon(icona, size: 13, color: c), const SizedBox(width: 3)],
        Text(testo, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

class StatoPill extends StatelessWidget {
  const StatoPill(this.stato);
  final String stato;
  @override
  Widget build(BuildContext context) {
    final s = statiAppuntamentoUi(stato);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: s.$2, borderRadius: BorderRadius.circular(99)),
      child: Text(s.$1, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

(String, Color) statiAppuntamentoUi(String stato) => switch (stato) {
      'confermato' => ('Confermato', const Color(0xFF1F7A55)),
      'completato' => ('Completato', const Color(0xFF7B5EA7)),
      'annullato' => ('Annullato', const Color(0xFF8A9096)),
      'non_presentata' => ('Non presentata', const Color(0xFFB42318)),
      _ => ('Prenotato', const Color(0xFF6B778C)),
    };

class Avvertenze extends StatelessWidget {
  const Avvertenze(this.testo);
  final String testo;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(S.m),
        decoration: BoxDecoration(color: const Color(0xFFFDECEA), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFB42318), width: 1.5)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.warning_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: S.s),
          Expanded(child: Text(testo, style: const TextStyle(color: Color(0xFF8C1B12), fontWeight: FontWeight.w600))),
        ]),
      );
}

class Riquadro extends StatelessWidget {
  const Riquadro({required this.testo, this.titolo, this.tipo = 'info', this.azioni = const []});
  final String? titolo;
  final String testo;
  final String tipo; // info | avviso | pericolo | ok
  final List<Widget> azioni;
  @override
  Widget build(BuildContext context) {
    final scuro = Theme.of(context).brightness == Brightness.dark;
    final (Color sf, Color fg, IconData ic) = switch (tipo) {
      'avviso' => (scuro ? const Color(0xFF382A14) : const Color(0xFFFFF4E0), scuro ? const Color(0xFFFFCC80) : const Color(0xFF7A4206), Icons.info_outline_rounded),
      'pericolo' => (scuro ? const Color(0xFF3A1D1B) : const Color(0xFFFDECEA), scuro ? const Color(0xFFFF8A80) : const Color(0xFF9A1B12), Icons.error_outline_rounded),
      'ok' => (scuro ? const Color(0xFF16301F) : const Color(0xFFE6F4EC), scuro ? const Color(0xFF7FD8A8) : const Color(0xFF0F6B45), Icons.check_circle_outline_rounded),
      _ => (scuro ? const Color(0xFF1E2433) : const Color(0xFFEEF2FB), scuro ? const Color(0xFFB9C7EE) : const Color(0xFF2A3D6B), Icons.lightbulb_outline_rounded),
    };
    return Container(
      padding: const EdgeInsets.all(S.m),
      decoration: BoxDecoration(color: sf, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(ic, color: fg, size: 22),
        const SizedBox(width: S.s),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (titolo != null) Text(titolo!, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
            Text(testo, style: TextStyle(color: fg)),
            if (azioni.isNotEmpty) Padding(padding: const EdgeInsets.only(top: S.s), child: Wrap(spacing: S.s, runSpacing: S.s, children: azioni)),
          ]),
        ),
      ]),
    );
  }
}

class Vuoto extends StatelessWidget {
  const Vuoto(this.testo, {this.icona = Icons.inbox_outlined});
  final String testo;
  final IconData icona;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.xl, horizontal: S.l),
      child: Column(children: [
        Icon(icona, size: 36, color: cs.outline),
        const SizedBox(height: S.s),
        Text(testo, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.nome, {this.dimensione = 40, this.colore});
  final String nome;
  final double dimensione;
  final Color? colore;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final parti = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final iniziali = parti.isEmpty ? '?' : (parti.length == 1 ? parti[0][0] : '${parti[0][0]}${parti[1][0]}').toUpperCase();
    final c = colore ?? cs.primary;
    return Container(
      width: dimensione,
      height: dimensione,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: Text(iniziali, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: dimensione * 0.38)),
    );
  }
}

/// Tessera numerica (statistiche).
class Tessera extends StatelessWidget {
  const Tessera({required this.valore, required this.etichetta});
  final String valore, etichetta;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(S.m),
      decoration: BoxDecoration(color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(valore, style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))),
        const SizedBox(height: 2),
        Text(etichetta, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Griglia di tessere ad altezza naturale (niente altezze fisse: il testo grande non viene tagliato).
class GrigliaTessere extends StatelessWidget {
  const GrigliaTessere({super.key, required this.colonne, required this.children, this.spazio = S.s});
  final int colonne;
  final List<Widget> children;
  final double spazio;
  @override
  Widget build(BuildContext context) {
    final righe = <Widget>[];
    for (var i = 0; i < children.length; i += colonne) {
      final riga = children.sublist(i, (i + colonne).clamp(0, children.length));
      righe.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var j = 0; j < colonne; j++) ...[
            if (j > 0) SizedBox(width: spazio),
            Expanded(child: j < riga.length ? riga[j] : const SizedBox()),
          ],
        ]),
      ));
      if (i + colonne < children.length) righe.add(SizedBox(height: spazio));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: righe);
  }
}

/// Campo testo con etichetta sopra (più leggibile al banco).
class Campo extends StatelessWidget {
  const Campo({required this.etichetta, required this.controller, this.tastiera, this.righe = 1, this.aiuto, this.abilitato = true, this.suCambio, this.placeholder, this.autofocus = false, this.maiuscole = TextCapitalization.sentences});
  final String etichetta;
  final TextEditingController controller;
  final TextInputType? tastiera;
  final int righe;
  final String? aiuto, placeholder;
  final bool abilitato, autofocus;
  final ValueChanged<String>? suCambio;
  final TextCapitalization maiuscole;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: S.m),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(etichetta, style: t.labelLarge),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: tastiera,
          maxLines: righe,
          minLines: righe > 1 ? 2 : 1,
          enabled: abilitato,
          autofocus: autofocus,
          onChanged: suCambio,
          textCapitalization: maiuscole,
          decoration: InputDecoration(hintText: placeholder, helperText: aiuto, helperMaxLines: 3),
        ),
      ]),
    );
  }
}

void vibra([bool forte = false]) => forte ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();

String giornoRelativo(DateTime d) {
  final oggi = D.inizioGiorno(DateTime.now());
  final g = D.diffGiorni(D.key(oggi), D.key(d));
  if (g == 0) return 'Oggi';
  if (g == 1) return 'Domani';
  if (g == -1) return 'Ieri';
  return F.giornoLungo(d);
}
