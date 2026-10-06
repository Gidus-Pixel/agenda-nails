-- Cloud dell'agenda: il server conserva solo dati CIFRATI sul dispositivo.
-- Non vede nomi, telefoni, appuntamenti né foto: solo blocchi illeggibili.

-- Codici di attivazione emessi dal fornitore dell'app (uno per estetista/abbonamento)
CREATE TABLE IF NOT EXISTS licenze (
  codice_hash TEXT PRIMARY KEY,          -- SHA-256 del codice: il codice in chiaro non viene salvato
  nota        TEXT NOT NULL DEFAULT '',  -- es. nome del salone, per riconoscerlo nell'elenco
  max_spazi   INTEGER NOT NULL DEFAULT 1,
  usati       INTEGER NOT NULL DEFAULT 0,
  revocata    INTEGER NOT NULL DEFAULT 0,
  creato      TEXT NOT NULL
);

-- Uno "spazio" = i dati di un'attività, condivisi tra i suoi dispositivi
CREATE TABLE IF NOT EXISTS spazi (
  id           TEXT PRIMARY KEY,
  licenza_hash TEXT NOT NULL,
  sale         TEXT NOT NULL,              -- sale per derivare la chiave dalla password (non segreto)
  verificatore TEXT NOT NULL,              -- testo noto cifrato: serve a riconoscere la password sbagliata
  generazione  INTEGER NOT NULL DEFAULT 1, -- cambia quando i dati vengono sostituiti in blocco (ripristino, nuova password)
  seq          INTEGER NOT NULL DEFAULT 0, -- contatore delle modifiche
  creato       TEXT NOT NULL,
  aggiornato   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS dispositivi (
  id         TEXT PRIMARY KEY,
  spazio     TEXT NOT NULL,
  nome       TEXT NOT NULL DEFAULT '',
  token_hash TEXT NOT NULL UNIQUE,
  creato     TEXT NOT NULL,
  ultimo     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS dispositivi_spazio ON dispositivi(spazio);

-- Record cifrati. "chiave" è un HMAC calcolato sul dispositivo: non rivela tipo né id del record.
CREATE TABLE IF NOT EXISTS record (
  spazio TEXT NOT NULL,
  chiave TEXT NOT NULL,
  seq    INTEGER NOT NULL,
  dati   BLOB NOT NULL,
  PRIMARY KEY (spazio, chiave)
);
CREATE INDEX IF NOT EXISTS record_seq ON record(spazio, seq);

-- Codici brevi per collegare un nuovo dispositivo (validi 15 minuti, monouso)
CREATE TABLE IF NOT EXISTS codici (
  codice_hash TEXT PRIMARY KEY,
  spazio      TEXT NOT NULL,
  scade       TEXT NOT NULL,
  tentativi   INTEGER NOT NULL DEFAULT 0
);
