import 'util.dart';

/// Valori predefiniti dell'installazione: stessa forma dell'oggetto CONFIG della web app,
/// così configurazioni, backup e cloud sono compatibili tra web, iOS e Android.
const String appId = 'agenda-nails';
const int schemaVersion = 1;
const String versioneApp = '1.0.0';

final Doc configPredefinita = {
  'attivita': {'nome': '', 'titolare': '', 'citta': '', 'telefono': '', 'logo': null, 'prefissoInternazionale': '39'},
  'brand': {'primario': '#B4646E', 'secondario': '#F7EBEC', 'accento': '#3A2A2C', 'font': 'system-ui'},
  'tema': 'auto',
  'fusoOrario': 'Europe/Rome',
  'orari': null,
  'agenda': {'slotMinuti': 15, 'cuscinettoMinuti': 10, 'vistaPredefinita': 'timeGridWeek', 'vistaTelefono': 'timeGridDay', 'coloreEventiPer': 'servizio', 'mostraAnnullati': false},
  'operatrici': [
    {'id': 'op1', 'nome': '', 'colore': '#B4646E'}
  ],
  'servizi': [],
  'categorieServizi': ['Ricostruzione', 'Semipermanente', 'Manicure', 'Pedicure', 'Nail art', 'Rimozione', 'Altro'],
  'categorieProdotti': ['Gel costruttore', 'Base', 'Top', 'Semipermanente', 'Acrigel / Polygel', 'Tips', 'Primer / Prep', 'Lime e abrasivi', 'Monouso', 'Nail art', 'Igiene e disinfezione', 'Cosmetici in vendita', 'Altro'],
  'marche': [],
  'magazzino': {'moltiplicatoreRiordino': 2},
  'moduli': {'agenda': true, 'clienti': true, 'storico': true, 'magazzino': true, 'fornitori': true, 'ordini': true, 'appunti': true, 'report': true},
  'promemoriaWhatsApp': true,
  'messaggi': {
    'promemoria': "Ciao {nome}, ti ricordo l'appuntamento di {giorno} alle {ora} da {attivita}. Per spostarlo scrivimi qui 💅",
    'richiamo': "Ciao {nome}, è passato un po' di tempo dal tuo ultimo appuntamento ({servizio}) da {attivita}. Vuoi fissare il prossimo? 💅",
  },
  'messaggiOrdine': 'Buongiorno, vorrei ordinare quanto segue per {attivita}:',
  'avvisi': {'scadenzaGiorni': 30, 'backupGiorni': 7},
  'sicurezza': {'bloccoDopoMinuti': 0},
  'backupAutomatico': false,
  'cloud': {'url': ''},
  'installazione': '',
  'note': '',
};

const statiAppuntamento = <String, ({String nome, int colore})>{
  'prenotato': (nome: 'Prenotato', colore: 0xFF6B778C),
  'confermato': (nome: 'Confermato', colore: 0xFF1F7A55),
  'completato': (nome: 'Completato', colore: 0xFF7B5EA7),
  'annullato': (nome: 'Annullato', colore: 0xFF9AA0A6),
  'non_presentata': (nome: 'Non presentata', colore: 0xFFB42318),
};
const statiAttivi = ['prenotato', 'confermato', 'completato'];

const forme = ['Quadrata', 'Squoval', 'Tonda', 'Ovale', 'Mandorla', 'Ballerina / Coffin', 'Stiletto', 'Altro'];
const lunghezze = ['Naturale', 'Corta', 'Media', 'Lunga', 'Extra lunga'];
const tecniche = ['Gel', 'Acrigel / Polygel', 'Acrilico', 'Semipermanente', 'Smalto tradizionale', 'Rinforzo / Base rubber', 'Altro'];
const pagamenti = ['Contanti', 'Carta / Bancomat', 'Satispay', 'Bonifico', 'Buono / Gift card', 'Altro'];
const tipiBlocco = {'pausa': 'Pausa', 'ferie': 'Ferie', 'chiusura': 'Chiusura', 'personale': 'Impegno personale'};
const consensi = {'privacy': 'Privacy (trattamento dati)', 'sanitari': 'Dati sanitari (allergie, sensibilità)', 'foto': 'Foto dei lavori', 'marketing': 'Messaggi promozionali'};
const paletteServizi = [0xFFC97B84, 0xFF8E6C8A, 0xFF5B8E7D, 0xFFD19A66, 0xFF6C8EBF, 0xFFB5838D, 0xFF7A9E7E, 0xFFC4A35A, 0xFF9B7EBD, 0xFFD77A61];

/// Archivi del database: gli stessi nomi della web app (IndexedDB).
const archivi = ['impostazioni', 'meta', 'servizi', 'clienti', 'appuntamenti', 'blocchi', 'schede_lavoro', 'foto', 'prodotti', 'movimenti_magazzino', 'fornitori', 'ordini_fornitore', 'appunti'];
/// Dati legati a QUESTO dispositivo: non vanno nei backup né nel cloud.
const metaLocali = ['cloud', 'cartellaBackup', 'ultimoBackupAuto', 'persistenzaRichiesta', 'ultimoBackup', 'pin'];

String esadecimale(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
int? coloreDaHex(dynamic hex) {
  final s = comeStr(hex).replaceAll('#', '');
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : 0xFF000000 | n;
}
