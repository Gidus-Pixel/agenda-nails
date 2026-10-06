# Cloud dell'agenda: backup automatico e sincronizzazione

Piccolo servizio su **Cloudflare** (Worker + database D1 **nell'Unione europea**) che fa due cose:

- **backup automatico**: ogni modifica fatta nell'agenda viene salvata nel cloud entro pochi secondi;
- **sincronizzazione**: iPad, iPhone e computer dello stesso salone vedono gli stessi dati.

## Privacy: il server non può leggere i dati

Ogni elemento (cliente, appuntamento, foto…) viene **cifrato sul dispositivo** con AES-256. La chiave è ricavata dalla *password del cloud* scelta dall'estetista e non lascia mai il dispositivo.

Il server riceve solo blocchi illeggibili. Anche i "nomi" dei record sono nascosti: al loro posto c'è un HMAC. Né tu, né Cloudflare, né chi dovesse entrare nel server può vedere nomi, telefoni, appuntamenti, foto o dati sanitari.

> Se l'estetista dimentica la password del cloud, i dati nel cloud non si possono recuperare. I dati sui suoi dispositivi restano utilizzabili: da lì si può impostare una nuova password con "Cambia password del cloud".

## Costi

Il piano gratuito di Cloudflare Workers e D1 basta per decine di saloni. Una foto pesa in media 150–300 KB e un salone con qualche centinaio di foto occupa poche decine di MB. Controlla i limiti aggiornati sul sito di Cloudflare.

## Messa online (una sola volta, circa 15 minuti)

Tutto passa da GitHub: un'automazione (GitHub Actions) crea il database, lo prepara e pubblica il servizio.

1. **Account Cloudflare** (gratuito): registrati su https://dash.cloudflare.com/sign-up.
2. **Attiva i Workers**: nella dashboard apri *Workers & Pages*. La prima volta Cloudflare ti fa scegliere il sottodominio `workers.dev`, per esempio `tuonome`.
3. **ID dell'account**: nella home della dashboard (colonna di destra) copia l'*Account ID*.
4. **Token API**:
   1. Vai su *My Profile → API Tokens → Create Token*.
   2. Parti dal modello **Edit Cloudflare Workers**.
   3. Aggiungi il permesso **Account › D1 › Edit**.
   4. Crea il token e copialo.
5. **Segreti su GitHub**: nel repository vai su *Settings → Secrets and variables → Actions → New repository secret* e crea:
   - `CLOUDFLARE_API_TOKEN`: il token del punto 4;
   - `CLOUDFLARE_ACCOUNT_ID`: l'ID del punto 3;
   - `ADMIN_TOKEN`: una password lunga scelta da te (serve per la pagina di gestione).
6. **Pubblica**: tab *Actions → Pubblica cloud → Run workflow*. Alla fine il log mostra l'indirizzo, per esempio `https://agenda-cloud.tuonome.workers.dev`.
7. **Collega l'app**: in `index.html` scrivi l'indirizzo in `CONFIG.cloud.url`. In alternativa l'estetista lo inserisce in Impostazioni → Dati → Cloud.

Da quel momento ogni modifica alla cartella `cloud/` viene ripubblicata da sola.

## Gestione dei saloni (codici di attivazione)

Apri `cloud/admin.html`, per esempio https://gidus-pixel.github.io/agenda-nails/cloud/admin.html, e inserisci indirizzo del servizio e `ADMIN_TOKEN`. Da lì puoi:

- **creare un codice di attivazione** per ogni nuova estetista: il codice vale per una attivazione e va copiato subito, perché il server non lo conserva in chiaro;
- vedere gli abbonamenti (dispositivi collegati, spazio usato, ultimo accesso);
- **sospendere / riattivare** un abbonamento, per esempio se non viene pagato: l'app continua a funzionare in locale, ma il cloud si ferma;
- **eliminare** i dati cloud di un salone che lascia il servizio.

## Come lo usa l'estetista

1. **Primo dispositivo** (per esempio l'iPad al banco): *Impostazioni → Dati → Cloud → Primo dispositivo*. Inserisce il codice di attivazione e sceglie la password del cloud: tutti i dati vengono caricati.
2. **Altri dispositivi** (per esempio l'iPhone):
   1. Sul primo dispositivo tocca *Collega un altro dispositivo*: compare un codice di 10 caratteri, valido 15 minuti.
   2. Sull'iPhone apre l'agenda installata e va su *Cloud → Collega a un'agenda già attiva*.
   3. Inserisce il codice e la password.
3. Da lì in poi la sincronizzazione è automatica:
   - all'apertura dell'app;
   - dopo ogni modifica;
   - ogni 2 minuti.
   
   L'icona della nuvola in alto mostra lo stato: verde = sincronizzato, arancione = offline, rosso = serve attenzione.

**Regola sui conflitti**: se la stessa scheda viene modificata su due dispositivi, vince la modifica più recente.

**Dispositivo perso**: da un altro dispositivo, *Cloud → Dispositivi collegati → Scollega*.

**Ripristino di un backup** con il cloud attivo: il cloud e tutti i dispositivi passano ai dati del backup. Su ciascun dispositivo viene prima creato un punto di ripristino.

## Prova in locale

```sh
cd cloud
npm install
printf 'ADMIN_TOKEN=prova\n' > .dev.vars
npm run migra-locale
npm run dev        # http://127.0.0.1:8787
```
