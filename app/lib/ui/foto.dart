import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app.dart';

final Map<String, Uint8List> _cache = {};

Future<Uint8List?> bytesFotoCache(BuildContext context, String id) async {
  final c = _cache[id];
  if (c != null) return c;
  final b = await context.dati.bytesFoto(id);
  if (b != null) {
    if (_cache.length > 80) _cache.remove(_cache.keys.first);
    _cache[id] = b;
  }
  return b;
}

/// Miniatura di una foto salvata (caricata dall'archivio del dispositivo).
class FotoMiniatura extends StatefulWidget {
  const FotoMiniatura({super.key, required this.id, this.dimensione = 92, this.etichetta, this.bytes, this.suRimuovi});
  final String id;
  final double dimensione;
  final String? etichetta;
  final Uint8List? bytes;
  final VoidCallback? suRimuovi;
  @override
  State<FotoMiniatura> createState() => _FotoMiniaturaState();
}

class _FotoMiniaturaState extends State<FotoMiniatura> {
  Uint8List? _b;
  bool _caricata = false;

  @override
  void initState() {
    super.initState();
    _b = widget.bytes;
    if (_b == null) {
      bytesFotoCache(context, widget.id).then((b) {
        if (mounted) setState(() {
          _b = b;
          _caricata = true;
        });
      });
    } else {
      _caricata = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = widget.dimensione;
    return SizedBox(
      width: s,
      height: s + (widget.etichetta != null ? 18 : 0),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(children: [
          GestureDetector(
            onTap: _b == null ? null : () => mostraFotoGrande(context, _b!, widget.etichetta ?? 'Foto'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: s,
                height: s,
                color: cs.surfaceContainer,
                child: _b != null
                    ? Image.memory(_b!, fit: BoxFit.cover, cacheWidth: (s * 3).round(), gaplessPlayback: true)
                    : Icon(_caricata ? Icons.broken_image_outlined : Icons.image_outlined, color: cs.outline),
              ),
            ),
          ),
          if (widget.etichetta != null) Text(widget.etichetta!, style: Theme.of(context).textTheme.labelSmall),
        ]),
        if (widget.suRimuovi != null)
          Positioned(
            right: -8,
            top: -8,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError, minimumSize: const Size(32, 32), padding: EdgeInsets.zero),
              iconSize: 18,
              tooltip: 'Rimuovi foto',
              onPressed: widget.suRimuovi,
              icon: const Icon(Icons.close_rounded),
            ),
          ),
      ]),
    );
  }
}

void mostraFotoGrande(BuildContext context, Uint8List b, String titolo) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (c) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(titolo, style: const TextStyle(color: Colors.white))),
      body: Center(child: InteractiveViewer(maxScale: 5, child: Image.memory(b))),
    ),
  ));
}
