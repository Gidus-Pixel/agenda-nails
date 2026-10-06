#!/usr/bin/env python3
"""Personalizza i file iOS/Android generati da `flutter create` (idempotente).
Eseguito dalla pipeline di GitHub ad ogni build: le modifiche qui si applicano da sole."""
import pathlib
import re
import sys

APP = pathlib.Path(__file__).resolve().parent.parent
NOME = "Agenda"

def modifica(percorso, funzione):
    p = APP / percorso
    if not p.exists():
        print(f"(manca {percorso}, salto)")
        return
    prima = p.read_text(encoding="utf-8")
    dopo = funzione(prima)
    if dopo != prima:
        p.write_text(dopo, encoding="utf-8")
        print(f"aggiornato {percorso}")

# ---------------- iOS ----------------
CHIAVI_IOS = {
    "CFBundleDisplayName": f"<string>{NOME}</string>",
    "NSCameraUsageDescription": "<string>Serve per fotografare i lavori (prima e dopo) e i prodotti.</string>",
    "NSPhotoLibraryUsageDescription": "<string>Serve per scegliere le foto dei lavori dalla libreria.</string>",
    "NSPhotoLibraryAddUsageDescription": "<string>Serve per salvare le foto dei lavori nella libreria.</string>",
    "NSMicrophoneUsageDescription": "<string>Non viene usato: l'app scatta solo foto.</string>",
    "LSSupportsOpeningDocumentsInPlace": "<false/>",
    "UIFileSharingEnabled": "<true/>",
    "ITSAppUsesNonExemptEncryption": "<false/>",
}

def plist(testo):
    for chiave, valore in CHIAVI_IOS.items():
        blocco = f"<key>{chiave}</key>"
        if blocco in testo:
            testo = re.sub(rf"<key>{chiave}</key>\s*<[^>]+>(?:[^<]*</string>)?", f"{blocco}\n\t{valore}", testo, count=1)
        else:
            testo = testo.replace("<dict>", f"<dict>\n\t{blocco}\n\t{valore}", 1)
    return testo

modifica("ios/Runner/Info.plist", plist)

def podfile(testo):
    return re.sub(r"^#?\s*platform :ios, '[\d.]+'", "platform :ios, '15.0'", testo, count=1, flags=re.M)

modifica("ios/Podfile", podfile)

# ---------------- Android ----------------
def manifest(testo):
    testo = re.sub(r'android:label="[^"]*"', f'android:label="{NOME}"', testo, count=1)
    if "<queries>" not in testo:
        testo = testo.replace("</manifest>", """    <queries>
        <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="https" /></intent>
        <intent><action android:name="android.intent.action.VIEW" /><data android:scheme="tel" /></intent>
        <intent><action android:name="android.intent.action.SENDTO" /><data android:scheme="mailto" /></intent>
        <intent><action android:name="android.intent.action.SEND" /><data android:mimeType="*/*" /></intent>
    </queries>
</manifest>""")
    if "android.permission.INTERNET" not in testo:
        testo = testo.replace("<application", '<uses-permission android:name="android.permission.INTERNET" />\n    <application', 1)
    return testo

modifica("android/app/src/main/AndroidManifest.xml", manifest)

print("piattaforme pronte")
sys.exit(0)
