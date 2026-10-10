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
    "NSFaceIDUsageDescription": "<string>Serve per sbloccare l'agenda con Face ID invece del PIN.</string>",
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

def appdelegate(testo):
    # notifiche locali: il delegato del centro notifiche (mostra le notifiche anche ad app aperta)
    if "import UserNotifications" not in testo:
        testo = testo.replace("import UIKit", "import UIKit\nimport UserNotifications", 1)
    if "UNUserNotificationCenter.current().delegate" not in testo:
        testo = re.sub(r"(didFinishLaunchingWithOptions[^{]*\{\n)", r"\1    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate\n", testo, count=1)
    return testo

modifica("ios/Runner/AppDelegate.swift", appdelegate)

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

PERMESSI = ["android.permission.USE_BIOMETRIC", "android.permission.POST_NOTIFICATIONS", "android.permission.RECEIVE_BOOT_COMPLETED", "android.permission.VIBRATE"]
RICEVITORI = """        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
"""

def manifest2(testo):
    for p in PERMESSI:
        if p not in testo:
            testo = testo.replace("<application", f'<uses-permission android:name="{p}" />\n    <application', 1)
    if "ScheduledNotificationReceiver" not in testo:
        testo = testo.replace("</application>", RICEVITORI + "    </application>", 1)
    return testo

modifica("android/app/src/main/AndroidManifest.xml", manifest2)

def gradle(testo):
    # desugaring (notifiche programmate) e AppCompat (sblocco con impronta: tema compatibile)
    if "isCoreLibraryDesugaringEnabled" not in testo:
        testo = testo.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "desugar_jdk_libs" not in testo:
        testo = testo.rstrip() + """

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.appcompat:appcompat:1.7.1")
}
"""
    return testo

modifica("android/app/build.gradle.kts", gradle)

def attivita(testo):
    # local_auth richiede FlutterFragmentActivity
    testo = testo.replace("import io.flutter.embedding.android.FlutterActivity", "import io.flutter.embedding.android.FlutterFragmentActivity")
    return testo.replace(": FlutterActivity()", ": FlutterFragmentActivity()")

for kt in (APP / "android/app/src/main").rglob("MainActivity.kt"):
    modifica(str(kt.relative_to(APP)), attivita)

def stili(testo):
    return testo.replace('parent="@android:style/Theme.Light.NoTitleBar"', 'parent="Theme.AppCompat.Light.NoActionBar"').replace('parent="@android:style/Theme.Black.NoTitleBar"', 'parent="Theme.AppCompat.NoActionBar"')

modifica("android/app/src/main/res/values/styles.xml", stili)
modifica("android/app/src/main/res/values-night/styles.xml", stili)

# ---------------- Android: icona, avvio, firma ----------------
def manifest_icona(testo):
    if "android:roundIcon" not in testo:
        testo = testo.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@mipmap/ic_launcher"\n        android:roundIcon="@mipmap/ic_launcher_round"', 1)
    return testo

modifica("android/app/src/main/AndroidManifest.xml", manifest_icona)

AVVIO = """<?xml version="1.0" encoding="utf-8"?>
<!-- Schermata di avvio (Android 11 e precedenti): sfondo del marchio e logo al centro -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/avvio_sfondo" />
    <item>
        <bitmap android:gravity="center" android:src="@drawable/avvio_logo" />
    </item>
</layer-list>
"""
for cartella in ("drawable", "drawable-v21"):
    f = APP / f"android/app/src/main/res/{cartella}/launch_background.xml"
    if f.exists() and f.read_text(encoding="utf-8") != AVVIO:
        f.write_text(AVVIO, encoding="utf-8")
        print(f"aggiornato {cartella}/launch_background.xml")

# Android 12+: la schermata di avvio di sistema usa l'icona adattiva su questo sfondo
for cartella, padre in (("values-v31", "Theme.AppCompat.Light.NoActionBar"), ("values-night-v31", "Theme.AppCompat.NoActionBar")):
    f = APP / f"android/app/src/main/res/{cartella}/styles.xml"
    f.parent.mkdir(parents=True, exist_ok=True)
    testo = f"""<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="{padre}">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">@color/avvio_sfondo</item>
    </style>
</resources>
"""
    if not f.exists() or f.read_text(encoding="utf-8") != testo:
        f.write_text(testo, encoding="utf-8")
        print(f"aggiornato {cartella}/styles.xml")

FIRMA_IMPORT = """import java.io.FileInputStream
import java.util.Properties

"""
FIRMA_TESTA = """
// Firma stabile: android/key.properties (creato dalla pipeline con la password nei segreti di GitHub).
// Senza, si firma con la chiave di debug (gli aggiornamenti richiederebbero di disinstallare l'app).
val proprietaFirma = Properties()
val fileFirma = rootProject.file("key.properties")
if (fileFirma.exists()) {
    proprietaFirma.load(FileInputStream(fileFirma))
}

"""
FIRMA_CONFIG = """    signingConfigs {
        create("release") {
            if (fileFirma.exists()) {
                keyAlias = proprietaFirma["keyAlias"] as String
                keyPassword = proprietaFirma["keyPassword"] as String
                storeFile = file(proprietaFirma["storeFile"] as String)
                storePassword = proprietaFirma["storePassword"] as String
            }
        }
    }

    buildTypes {"""

def gradle_firma(testo):
    if "proprietaFirma" not in testo:
        testo = FIRMA_IMPORT + testo
        # in Kotlin DSL nulla può precedere il blocco plugins {}: le proprietà vanno subito dopo
        testo = testo.replace("\nandroid {", FIRMA_TESTA + "android {", 1)
        testo = testo.replace("    buildTypes {", FIRMA_CONFIG, 1)
        testo = re.sub(r'signingConfig = signingConfigs\.getByName\("debug"\)',
                       'signingConfig = if (fileFirma.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")', testo, count=1)
    return testo

modifica("android/app/build.gradle.kts", gradle_firma)

print("piattaforme pronte")
sys.exit(0)
