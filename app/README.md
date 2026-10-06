# Agenda — app per iPhone, iPad e Android

App nativa (Flutter) con le stesse funzioni della versione web: agenda con trascinamento,
clienti e storico lavori con foto, magazzino (giacenze, scadenze, PAO), fornitori e ordini con
carico automatico, appunti con promemoria, report con CSV, impostazioni, backup e cloud cifrato.
I dati sono **compatibili con la versione web**: un backup fatto da una parte si ripristina dall'altra,
e lo stesso cloud cifrato tiene allineati browser, iPhone, iPad e Android.

## Come si costruisce

Non serve installare nulla sul computer: ad ogni modifica nella cartella `app/` GitHub Actions
(flusso "App iOS e Android") esegue:

1. analisi del codice e test automatici (cifratura confrontata con WebCrypto, cambio dell'ora,
   conflitti di agenda, numeri di telefono, backup creati dalla versione web);
2. l'**APK Android** installabile (artefatto `agenda-android` della corsa);
3. la compilazione **iOS** e le foto delle schermate sul simulatore iPhone e iPad
   (ramo `ci-schermate`);
4. un'anteprima web (ramo `anteprima`).

I log dei passaggi finiscono nei rami `ci-log-verifica` e `ci-log-ios`.

## Provarla

- **Android**: dal telefono apri la pagina Releases del repository → "Agenda per Android
  (anteprima)" → `agenda-android.apk` e aprilo (bisogna consentire l'installazione da quella
  fonte). Il file si aggiorna da solo a ogni modifica dell'app.
- **iPhone / iPad**: Apple consente di installare app fuori dall'App Store solo tramite
  **TestFlight**, che richiede l'iscrizione all'Apple Developer Program (99 €/anno) a nome di chi
  pubblica l'app. Una volta attivo l'account si aggiungono a GitHub i segreti per la firma e il
  flusso carica ogni versione su TestFlight; le estetiste installano l'app TestFlight e ricevono
  l'invito per email.

## Personalizzare per un'altra estetista

Dall'app: Altro → Attività, Aspetto (colore del marchio), Orari, Servizi; poi Altro → Backup e
cloud → Configurazione → Esporta. Il file si importa sull'installazione della nuova estetista
(anche nella versione web: il formato è lo stesso).

## Struttura

- `lib/core` — date locali (fuso Europe/Rome, cambio dell'ora), telefono/WhatsApp, configurazione
- `lib/dati` — archivio (SQLite su iOS/Android) e cache in memoria
- `lib/dominio` — regole: conflitti di agenda, richiami, backup, cifratura, cloud, privacy
- `lib/ui` — schermate (Oggi, Agenda, Clienti, Altro)
- `test` — test automatici
