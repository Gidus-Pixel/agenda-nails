import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'comuni.dart';

/// Funzioni del telefono/tablet: link esterni, condivisione file, scelta file, fotocamera.
Future<void> apriLink(BuildContext context, Uri? uri) async {
  if (uri == null) return;
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) avviso(context, 'Impossibile aprire il collegamento.', errore: true);
}

Future<void> chiama(BuildContext context, String telefono) => apriLink(context, Uri(scheme: 'tel', path: telefono));

/// Condivide un file (foglio "Condividi" di iOS / Android): Salva su File, iCloud Drive, Drive, WhatsApp, email…
Future<bool> condividiFile(BuildContext context, Uint8List dati, String nome, {String tipo = 'application/json'}) async {
  final box = context.findRenderObject() as RenderBox?;
  final origine = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  final r = await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(dati, name: nome, mimeType: tipo)],
    fileNameOverrides: [nome],
    sharePositionOrigin: origine,
  ));
  return r.status == ShareResultStatus.success || r.status == ShareResultStatus.unavailable;
}

Future<void> condividiTesto(BuildContext context, String testo) async {
  final box = context.findRenderObject() as RenderBox?;
  final origine = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  await SharePlus.instance.share(ShareParams(text: testo, sharePositionOrigin: origine));
}

/// Sceglie un file (backup o configurazione) e ne restituisce nome e contenuto.
Future<({String nome, Uint8List dati})?> scegliFile() async {
  final f = await openFile();
  if (f == null) return null;
  return (nome: f.name, dati: await f.readAsBytes());
}

/// Foto dalla fotocamera o dalla libreria, già ridimensionata (lato lungo 1280 px, JPEG ~80%).
Future<Uint8List?> prendiFoto({required bool fotocamera}) async {
  final x = await ImagePicker().pickImage(
    source: fotocamera ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1280,
    maxHeight: 1280,
    imageQuality: 80,
  );
  return x == null ? null : await x.readAsBytes();
}
