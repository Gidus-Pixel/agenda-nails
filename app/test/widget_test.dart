import 'package:flutter_test/flutter_test.dart';
import 'package:agenda_nails/main.dart';

void main() {
  testWidgets('si avvia', (tester) async {
    await tester.pumpWidget(const AppProva());
    expect(find.text('Agenda'), findsOneWidget);
  });
}
