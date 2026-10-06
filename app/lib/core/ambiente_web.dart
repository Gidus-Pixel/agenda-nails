/// Su web si leggono dai parametri dell'indirizzo: ?agenda_demo=1&agenda_schermata=agenda
Future<void> prepara() async {}

String? variabile(String nome) => Uri.base.queryParameters[nome.toLowerCase()];
