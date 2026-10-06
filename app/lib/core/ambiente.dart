import 'ambiente_web.dart' if (dart.library.io) 'ambiente_io.dart' as imp;

/// Variabili usate per le schermate automatiche (simulatore iOS / anteprima web):
/// AGENDA_DEMO=1 carica i dati di prova, AGENDA_SCHERMATA apre una schermata.
String? variabileAmbiente(String nome) => imp.variabile(nome);
