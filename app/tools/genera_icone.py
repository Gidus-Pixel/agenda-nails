#!/usr/bin/env python3
"""Genera tutte le icone dell'app (Android, iOS, web) dal disegno in assets/icona/.

Per cambiare logo: sostituisci assets/icona/simbolo.svg (solo il simbolo, su sfondo trasparente,
in un quadrato 512x512 con il disegno dentro il cerchio centrale di diametro ~400) e il colore di
sfondo in assets/icona/colori.txt, poi esegui:  python3 tools/genera_icone.py
Serve: pip install cairosvg pillow   (si esegue in locale; i file generati vanno nel repository).
"""
import io
import pathlib
import re

import cairosvg
from PIL import Image

APP = pathlib.Path(__file__).resolve().parent.parent
ICONA = APP / "assets" / "icona"
colori = dict(r.split("=", 1) for r in (ICONA / "colori.txt").read_text().split() if "=" in r)
SFONDO = colori.get("sfondo", "#B4646E")
SPLASH = colori.get("splash", "#F7EBEC")
simbolo = (ICONA / "simbolo.svg").read_text()
mono = (ICONA / "monocromatico.svg").read_text()


def interno(svg):
    return re.sub(r"^.*?<svg[^>]*>|</svg>\s*$", "", svg, flags=re.S)


def svg(contenuto, sfondo=None, scala=1.0, angoli=0):
    """Compone un'icona 512x512: sfondo (facoltativo, con angoli arrotondati) + simbolo scalato al centro."""
    t = (1 - scala) * 256
    fondo = f'<rect width="512" height="512" rx="{angoli}" fill="{sfondo}"/>' if sfondo else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">{fondo}'
            f'<g transform="translate({t} {t}) scale({scala})">{interno(contenuto)}</g></svg>')


def png(svg_testo, lato, opaco=False):
    dati = cairosvg.svg2png(bytestring=svg_testo.encode(), output_width=lato, output_height=lato)
    im = Image.open(io.BytesIO(dati)).convert("RGBA")
    if opaco:  # iOS: niente trasparenza
        base = Image.new("RGB", im.size, SFONDO)
        base.paste(im, mask=im.split()[3])
        im = base
    return im


def salva(im, percorso):
    percorso.parent.mkdir(parents=True, exist_ok=True)
    im.save(percorso, optimize=True)
    print("scritto", percorso.relative_to(APP.parent))


# ---------------- Android ----------------
RES = APP / "android/app/src/main/res"
DENSITA = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
for nome, k in DENSITA.items():
    # icona classica (Android 7 e precedenti): quadrato arrotondato
    salva(png(svg(simbolo, SFONDO, 0.92, 96), round(48 * k)), RES / f"mipmap-{nome}/ic_launcher.png")
    salva(png(svg(simbolo, SFONDO, 0.92, 256), round(48 * k)), RES / f"mipmap-{nome}/ic_launcher_round.png")
    # icona adattiva (Android 8+): livello in primo piano 108dp, simbolo nella zona sicura (66dp)
    salva(png(svg(simbolo, None, 0.66), round(108 * k)), RES / f"mipmap-{nome}/ic_launcher_foreground.png")
    # icona a tema (Android 13+): solo la sagoma, il colore lo sceglie il sistema
    salva(png(svg(mono, None, 0.66), round(108 * k)), RES / f"mipmap-{nome}/ic_launcher_monochrome.png")
    # schermata di avvio (Android 11 e precedenti)
    salva(png(svg(simbolo, SFONDO, 0.8, 120), round(96 * k)), RES / f"drawable-{nome}/avvio_logo.png")

adattiva = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
"""
for n in ("ic_launcher", "ic_launcher_round"):
    p = RES / f"mipmap-anydpi-v26/{n}.xml"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(adattiva)
(RES / "values-night").mkdir(parents=True, exist_ok=True)
(RES / "values-night/colori_avvio.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="avvio_sfondo">{colori.get("splash_scuro", "#1F1719")}</color>
</resources>
""")
(RES / "values/colori_icona.xml").write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">{SFONDO}</color>
    <color name="avvio_sfondo">{SPLASH}</color>
</resources>
""")

# ---------------- iOS ----------------
IOS = APP / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
for f in sorted(IOS.glob("Icon-App-*.png")):
    m = re.match(r"Icon-App-([\d.]+)x[\d.]+@(\d)x\.png", f.name)
    lato = round(float(m.group(1)) * int(m.group(2)))
    salva(png(svg(simbolo, SFONDO, 0.92), lato, opaco=True), f)

# ---------------- web (anteprima) ----------------
WEB = APP / "web"
if WEB.exists():
    salva(png(svg(simbolo, SFONDO, 0.92, 256), 32), WEB / "favicon.png")
    for lato in (192, 512):
        salva(png(svg(simbolo, SFONDO, 0.92, 256), lato), WEB / f"icons/Icon-{lato}.png")
        salva(png(svg(simbolo, SFONDO, 0.72), lato), WEB / f"icons/Icon-maskable-{lato}.png")
# versione web principale (cartella icone/ nella radice del repository)
RADICE = APP.parent / "icone"
if RADICE.exists():
    salva(png(svg(simbolo, SFONDO, 0.92), 180, opaco=True), RADICE / "apple-touch-icon.png")
    salva(png(svg(simbolo, SFONDO, 0.92, 256), 32), RADICE / "favicon-32.png")
    salva(png(svg(simbolo, SFONDO, 0.92, 256), 192), RADICE / "icona-192.png")
    salva(png(svg(simbolo, SFONDO, 0.92, 256), 512), RADICE / "icona-512.png")
    salva(png(svg(simbolo, SFONDO, 0.72), 512), RADICE / "icona-maskable-512.png")
# logo dentro l'app (schermata di blocco, barra laterale)
salva(png(svg(simbolo, SFONDO, 0.92, 256), 256), APP / "assets/immagini/icona.png")
# anteprima per controllo
salva(png(svg(simbolo, SFONDO, 0.92, 112), 512), ICONA / "anteprima.png")
