# Agenda Nails

Agenda gestionale per nail artist ed estetiste, in italiano, pensata per l'uso quotidiano al banco di lavoro da tablet, telefono o computer.

**Apri l'app:** https://gidus-pixel.github.io/agenda-nails/

## Cosa fa

- **Agenda**: viste giorno, settimana, mese ed elenco. Prenotazione con uno o più servizi, con durata e prezzo calcolati in automatico. Gli appuntamenti si spostano trascinandoli oppure con il pulsante "Sposta". L'app controlla sovrapposizioni, orari di apertura, pause, ferie e tempo di sterilizzazione tra un appuntamento e l'altro. Supporta gli appuntamenti ripetuti: si possono spostare, modificare o annullare anche tutti i successivi della serie. Con un tocco si apre il promemoria WhatsApp già scritto, e ogni appuntamento si può esportare in `.ics`.
- **Clienti e storico**: preferenze (forma, lunghezza, colori, tecnica), avvertenze e sensibilità, consensi con data e scheda lavoro con foto prima/dopo. Da ogni cliente si può ripetere l'ultimo lavoro. Per ciascuna sono disponibili statistiche e la lista "da ricontattare" per i refill.
- **Magazzino**: la giacenza è sempre calcolata dalla somma dei movimenti (carico, scarico, consumo, vendita, reso, rettifica). Avvisi per sotto scorta, scadenza e PAO superato, più il valore del magazzino a costo. I consumi delle schede lavoro vengono scalati solo per i prodotti spuntati.
- **Fornitori e ordini**: anagrafica completa e spesa per periodo. L'ordine si può inviare via WhatsApp o email con il testo già pronto. Il ricevimento può essere totale o parziale, con carico automatico in magazzino. Le bozze d'ordine si creano direttamente dai prodotti sotto scorta.
- **Appunti**: tag, colori, appunti fissati in alto, ricerca e promemoria con data. Ogni appunto si può collegare a una cliente, un fornitore, un prodotto o un appuntamento.
- **Report**: incassi, servizi più richiesti, mancate presentazioni, consumi, vendite e spesa per fornitore. Esportazione CSV compatibile con Excel in italiano.
- **Sicurezza e dati**:
  - blocco con PIN;
  - backup completo, con o senza foto, eventualmente cifrato con password (AES-256);
  - condivisione del backup;
  - backup automatico giornaliero in una cartella (Chrome/Edge su computer).
- **Privacy (GDPR)**:
  - consensi con data;
  - dati sanitari conservati solo con consenso;
  - esportazione dei dati di una cliente;
  - cancellazione con anonimizzazione dello storico.

## Dove sono i dati

Tutti i dati restano **solo nel browser del dispositivo** (IndexedDB): non vengono inviati a nessun server, nemmeno a GitHub. Per questo è importante fare i backup e conservarli altrove.

L'agenda è un gestionale interno e **non sostituisce gli adempimenti fiscali** (documento commerciale/registratore telematico, fatturazione).

## Come si usa

- **Da tablet o telefono (consigliato)**:
  1. Apri l'indirizzo qui sopra con Chrome (Android) o Safari (iPad/iPhone).
  2. Installa l'app: su Chrome dal menu ⋮ → *Installa app*, su Safari da Condividi → *Aggiungi alla schermata Home*.
  3. Da quel momento funziona anche senza internet.
- **Da computer**: puoi usare l'indirizzo https oppure scaricare la cartella e aprire `index.html` con un doppio clic. Per avere il calendario anche senza internet, tieni la cartella `vendor/` accanto al file.

## Preparare l'agenda per una nuova estetista

1. Apri l'app e compila **Impostazioni**: attività, colori, orari, servizi, operatrici e messaggi.
2. In **Impostazioni → Dati → Esporta configurazione** salva il file `configurazione-….json`.
3. Sul dispositivo dell'estetista apri l'app e scegli **Importa configurazione** (dalla schermata Oggi o da Impostazioni).

In alternativa puoi compilare l'oggetto `CONFIG` in cima a `index.html`. Se sullo stesso browser devono convivere due agende, imposta `CONFIG.installazione` con un nome breve diverso per ciascuna.

## File

| File | A cosa serve |
|---|---|
| `index.html` | l'intera app (HTML + CSS + JavaScript, nessun passaggio di build) |
| `vendor/fullcalendar-6.1.21.min.js` | copia locale del calendario, usata se la CDN non è raggiungibile |
| `sw.js` | service worker: app installabile e uso offline |
| `manifest.webmanifest`, `icone/` | nome, icone e colori dell'app installata |

## Pubblicare un aggiornamento

1. Modifica i file.
2. Aumenta `VERSIONE` in `sw.js` e `VERSIONE_APP` in `index.html`.
3. Fai il push su `main`.

All'apertura successiva l'app mostra "È disponibile una nuova versione — Aggiorna". I dati non vengono toccati: le eventuali migrazioni dello schema sono automatiche.

## Licenze di terze parti

- [FullCalendar](https://fullcalendar.io) 6.1.21 (bundle standard), licenza MIT: vedi `vendor/FULLCALENDAR-LICENSE.md`. Non vengono usati i plugin a pagamento (scheduler, resource, timeline).
