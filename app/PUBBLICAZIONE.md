# Pubblicare l'app: iPhone/iPad (TestFlight), Android e cloud

Il codice è pronto: per ciascuna di queste tre cose manca solo un passaggio che **deve fare il
titolare dell'account**. Account, password e chiavi non vanno mai condivisi: si inseriscono una
sola volta nei "segreti" di GitHub, dove restano cifrati.

---

## 0. Provarla subito sul proprio iPhone/iPad (gratis, senza account sviluppatore)

Va bene per provarla tu, non per le clienti: con un Apple ID gratuito l'app **scade dopo 7 giorni**
e va reinstallata (i dati restano: basta reinstallarla sopra). Al massimo 3 app installate così.

1. Su un PC Windows installa **iTunes e iCloud scaricati dal sito Apple** (non quelli del Microsoft
   Store), poi **Sideloadly** da <https://sideloadly.io>. Su Mac basta Sideloadly.
2. Scarica `agenda-ios.ipa` dalla pagina **Releases** del repository →
   "Agenda per iPhone e iPad (anteprima da firmare)". Si aggiorna a ogni modifica dell'app.
3. Collega l'iPhone col cavo e sul telefono tocca **Autorizza** (Trust).
4. In Sideloadly trascina il file `.ipa`, scrivi il tuo Apple ID e premi **Start**. Ti verranno
   chiesti la password e il codice a due fattori, che vanno solo ad Apple per firmare l'app.
5. Sull'iPhone:
   - attiva **Impostazioni → Privacy e sicurezza → Modalità sviluppatore**: il telefono si
     riavvia, poi confermi;
   - vai in **Impostazioni → Generali → VPN e gestione dispositivi** → il tuo Apple ID →
     **Autorizza**.
6. Apri l'app **Agenda**. Dopo 7 giorni ripeti il punto 4: Sideloadly può anche rinnovarla da solo
   se lasci il PC acceso con l'iPhone sulla stessa rete Wi-Fi.

Con l'Apple ID gratuito funzionano anche Face ID e le notifiche.

---

## 1. iPhone e iPad con TestFlight

TestFlight è l'app di Apple per installare le versioni di prova. Le estetiste la scaricano
dall'App Store, ricevono un invito per email e installano l'agenda con un tocco. Gli
aggiornamenti arrivano da soli.

### 1.1 Iscrizione all'Apple Developer Program (una volta, 99 €/anno)

1. Serve un **Apple Account con l'autenticazione a due fattori** attiva, e il nome e l'indirizzo
   legali reali.
2. Iscriviti da <https://developer.apple.com/programs/enroll/>, meglio dall'app **Apple Developer**
   su iPhone, dove si paga direttamente.
3. Scegli il tipo di account:
   - **Persona fisica**: è il più rapido, spesso approvato in un giorno. Sull'App Store come
     venditore compare il tuo nome e cognome.
   - **Organizzazione** (ditta o società): sull'App Store compare il nome dell'azienda, ed è più
     adatto se rivendi l'app con un tuo marchio. Serve il **numero D-U-N-S** dell'azienda, che è
     gratuito e si chiede da Apple durante l'iscrizione ma richiede qualche giorno.

### 1.2 Creare l'app in App Store Connect (una volta)

1. Vai su <https://appstoreconnect.apple.com> → **App** → **+** → **Nuova app**.
2. Compila così:
   - **Piattaforma**: iOS.
   - **Nome**: il nome commerciale, per esempio "Agenda Nails". Deve essere unico sull'App Store.
   - **Lingua principale**: Italiano.
   - **ID pacchetto (Bundle ID)**: `it.agendanails.agendaNails`. Se non compare nell'elenco,
     crealo prima da <https://developer.apple.com/account/resources/identifiers/list> → **+** →
     *App IDs* → *App*, con l'ID esplicito `it.agendanails.agendaNails`.
   - **SKU**: un codice a tua scelta, per esempio `agenda-nails`.

### 1.3 Chiave API per GitHub (una volta)

1. In App Store Connect: **Utenti e accessi** → **Integrazioni** → **App Store Connect API** →
   *Chiavi del team* → **+**.
2. Nome: `GitHub`. Accesso: **Admin**. Serve Admin perché la firma usa il certificato di
   distribuzione gestito da Apple nel cloud: con ruoli più bassi Apple rifiuta la firma.
3. Annota due valori:
   - l'**ID chiave** (Key ID);
   - l'**ID emittente** (Issuer ID), che si trova sopra l'elenco delle chiavi.
4. Scarica il file `AuthKey_XXXXXXXXXX.p8`. **Si può scaricare una sola volta**: conservalo in un
   posto sicuro.
5. Trova il **Team ID**, 10 caratteri, su <https://developer.apple.com/account> → *Membership details*.

### 1.4 Segreti su GitHub (una volta)

Nel repository vai su **Settings** → **Secrets and variables** → **Actions** →
**New repository secret** e crea:

| Nome | Valore |
|---|---|
| `APPLE_API_KEY_ID` | l'ID chiave |
| `APPLE_API_ISSUER_ID` | l'ID emittente |
| `APPLE_API_KEY_P8` | tutto il testo del file `.p8`, aperto con un editor di testo e incollato con le righe `-----BEGIN PRIVATE KEY-----` e `-----END PRIVATE KEY-----` |
| `APPLE_TEAM_ID` | il Team ID |

### 1.5 Mandare una versione su TestFlight

1. Su GitHub apri **Actions** → **App iOS e Android** → **Run workflow**.
2. Lascia spuntato "Carica questa versione su TestFlight" e conferma.

Dopo circa 30–40 minuti la versione è su App Store Connect. Apple la elabora in altri 10–30 minuti,
poi compare in **TestFlight**. Ogni invio ha un numero di build crescente, assegnato in automatico.

### 1.6 Invitare chi la usa

- **Tester interni**: fino a 100 persone che fanno parte del tuo team App Store Connect. Le aggiungi
  da *Utenti e accessi*, poi in TestFlight → *Test interno*. Non serve la revisione di Apple.
- **Tester esterni**: per esempio le estetiste clienti, invitate per email o con un link pubblico.
  La prima versione passa una breve revisione di Apple (*Beta App Review*), di solito entro un giorno.
  Devi compilare anche un indirizzo email di contatto e una descrizione del test.

> Ogni build TestFlight scade dopo **90 giorni**. Per l'uso quotidiano a lungo termine il passo
> successivo è pubblicarla sull'App Store. Va bene anche come **app non in elenco**
> (*Unlisted App Distribution*): non compare nelle ricerche e si installa solo dal link che dai
> alle tue clienti.

**Crittografia**: l'app dichiara `ITSAppUsesNonExemptEncryption = NO`, perché usa solo algoritmi
standard (HTTPS e AES per i backup dell'utente). In questo modo Apple non chiede i documenti
sull'esportazione a ogni versione.

---

## 2. Android

- **Subito, senza account**: ogni modifica dell'app aggiorna il file `agenda-android.apk` nella
  pagina **Releases** del repository ("Agenda per Android (anteprima)"). Si apre dal telefono e si
  installa, consentendo l'installazione da quella fonte.
- **Firma stabile (una volta)**: ogni APK è firmato con la stessa chiave, salvata cifrata in
  `android/firma-android.p12`. Così ogni nuova versione si installa **sopra** quella vecchia e i
  dati restano. Serve un solo segreto su GitHub: **Settings → Secrets and variables → Actions →
  New repository secret** con nome `ANDROID_KEYSTORE_PASSWORD` e come valore la password della
  chiave. Conserva la password anche in un posto sicuro, per esempio un gestore di password: senza,
  non si possono più pubblicare aggiornamenti della stessa app, né su Google Play.
  > Le versioni di prova fatte **prima** della firma stabile non si aggiornano: fai un backup,
  > disinstallale, installa la nuova versione e ripristina il backup. Va fatto una sola volta.
- **Logo**: il disegno è in `assets/icona/` (`simbolo.svg` e i colori in `colori.txt`). Da lì
  `python3 tools/genera_icone.py` rigenera tutte le icone per Android, compresa l'icona a tema di
  Android 13+, per iOS e per il web, e la schermata di avvio.
- **Google Play**, in futuro: serve un account Google Play Console (25 $ una tantum). I nuovi
  account personali devono fare un test chiuso con almeno 12 tester per 14 giorni prima della
  pubblicazione.

---

## 3. Cloud cifrato (Cloudflare)

Le istruzioni complete sono in [`../cloud/README.md`](../cloud/README.md). In breve:

1. Crea un account gratuito su <https://dash.cloudflare.com/sign-up>, poi apri *Workers & Pages*
   per scegliere il sottodominio `workers.dev`.
2. Copia l'**Account ID** dalla home della dashboard.
3. Crea un **token API**:
   1. Vai su *My Profile* → *API Tokens* → *Create Token*.
   2. Parti dal modello **Edit Cloudflare Workers**.
   3. Aggiungi il permesso **Account › D1 › Edit**.
4. Su GitHub crea questi segreti:
   - `CLOUDFLARE_API_TOKEN`;
   - `CLOUDFLARE_ACCOUNT_ID`;
   - `ADMIN_TOKEN`: una password lunga a tua scelta.
5. Pubblica: **Actions** → **Pubblica cloud** → **Run workflow**. Alla fine il log mostra
   l'indirizzo, per esempio `https://agenda-cloud.tuonome.workers.dev`.
6. Dai l'indirizzo alle estetiste. Nell'app lo trovano in **Altro → Backup e cloud → Cloud** →
   *Indirizzo del servizio*. Per non farlo scrivere a nessuno puoi metterlo come predefinito:
   - nella versione web: `CONFIG.cloud.url` in `index.html`;
   - nell'app: `'cloud': {'url': '…'}` in `app/lib/core/config.dart`.
7. Crea i **codici di attivazione** dalla pagina `cloud/admin.html`.
