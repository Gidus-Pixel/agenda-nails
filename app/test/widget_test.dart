import 'package:agenda_nails/dominio/cloud.dart';
import 'package:agenda_nails/dominio/demo.dart';
import 'package:agenda_nails/ui/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'aiuto.dart';

Future<void> avvia(WidgetTester t, Size logica) async {
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = logica * 2;
  addTearDown(t.view.reset);
  navigazione.scheda = 0;
  final d = await datiDiProva();
  await caricaDatiDemo(d, configura: true);
  await t.pumpWidget(AppAgenda(dati: d, cloud: Cloud(d)));
  await t.pumpAndSettle();
}

/// Tocca una voce della barra di navigazione (in basso sul telefono, laterale su tablet).
Future<void> scheda(WidgetTester t, String nome) async {
  final barra = find.byWidgetPredicate((w) => w is NavigationBar || w is NavigationRail);
  await t.tap(find.descendant(of: barra, matching: find.text(nome)));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it');
    Intl.defaultLocale = 'it';
  });

  testWidgets('telefono: oggi, agenda, nuovo appuntamento, clienti, scheda cliente, altro', (t) async {
    await avvia(t, const Size(390, 844));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining('Buon'), findsWidgets);

    await scheda(t, 'Agenda');
    expect(find.text('Oggi'), findsWidgets); // pulsante "Oggi" dell'agenda
    await t.tap(find.widgetWithText(FloatingActionButton, 'Appuntamento').last);
    await t.pumpAndSettle();
    expect(find.text('Nuovo appuntamento'), findsOneWidget);
    expect(find.text('Fissa appuntamento'), findsOneWidget);
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pumpAndSettle();

    await scheda(t, 'Clienti');
    expect(find.textContaining('Prova'), findsWidgets);
    await t.tap(find.text('Beatrice Prova').first);
    await t.pumpAndSettle();
    expect(find.text('Storico lavori'), findsOneWidget);
    expect(find.textContaining('DATO DI PROVA'), findsOneWidget); // avvertenze in evidenza
    t.state<NavigatorState>(find.byType(Navigator).first).pop();
    await t.pumpAndSettle();

    await scheda(t, 'Altro');
    expect(find.text('Backup e cloud'), findsOneWidget);
    await t.tap(find.text('Backup e cloud'));
    await t.pumpAndSettle();
    expect(find.text('Backup manuale'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('iPad: barra laterale, settimana, clienti affiancate', (t) async {
    await avvia(t, const Size(1180, 820));
    expect(find.byType(NavigationRail), findsOneWidget);
    await scheda(t, 'Agenda');
    expect(find.text('Settimana'), findsWidgets);
    await scheda(t, 'Clienti');
    expect(find.textContaining('Scegli una cliente'), findsOneWidget);
    await t.tap(find.text('Anna Prova').first);
    await t.pumpAndSettle();
    expect(find.text('Storico lavori'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
