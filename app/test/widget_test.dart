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
  final d = await datiDiProva();
  await caricaDatiDemo(d, configura: true);
  await t.pumpWidget(AppAgenda(dati: d, cloud: Cloud(d)));
  await t.pumpAndSettle();
}

Future<void> scheda(WidgetTester t, IconData icona) async {
  await t.tap(find.byIcon(icona).first);
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

    await scheda(t, Icons.calendar_month_outlined);
    expect(find.textContaining('Tocca uno spazio libero'), findsOneWidget);
    await t.tap(find.widgetWithText(FloatingActionButton, 'Appuntamento').last);
    await t.pumpAndSettle();
    expect(find.text('Nuovo appuntamento'), findsOneWidget);
    expect(find.text('Fissa appuntamento'), findsOneWidget);
    await t.tap(find.byTooltip('Chiudi'));
    await t.pumpAndSettle();

    await scheda(t, Icons.people_outline_rounded);
    expect(find.textContaining('Prova'), findsWidgets);
    await t.tap(find.text('Beatrice Prova'));
    await t.pumpAndSettle();
    expect(find.text('Storico lavori'), findsOneWidget);
    expect(find.textContaining('DATO DI PROVA'), findsOneWidget); // avvertenze in evidenza
    await t.pageBack();
    await t.pumpAndSettle();

    await scheda(t, Icons.tune_outlined);
    expect(find.text('Backup e cloud'), findsOneWidget);
    await t.tap(find.text('Backup e cloud'));
    await t.pumpAndSettle();
    expect(find.text('Backup manuale'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('iPad: barra laterale, settimana, clienti affiancate', (t) async {
    await avvia(t, const Size(1180, 820));
    expect(find.byType(NavigationRail), findsOneWidget);
    await scheda(t, Icons.calendar_month_outlined);
    expect(find.text('Settimana'), findsWidgets);
    await scheda(t, Icons.people_outline_rounded);
    expect(find.textContaining('Scegli una cliente'), findsOneWidget);
    await t.tap(find.text('Anna Prova'));
    await t.pumpAndSettle();
    expect(find.text('Storico lavori'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
